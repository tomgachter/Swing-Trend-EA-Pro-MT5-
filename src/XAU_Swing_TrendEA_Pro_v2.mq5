//+------------------------------------------------------------------+
//| XAU_Swing_TrendEA_Pro_v2.mq5                                     |
//| Prop-firm hardened swing/breakout Expert Advisor for XAUUSD (MT5)|
//| Session: 07:00-14:45, Bias votes: EMA20(H1)/EMA34(H4)/EMA50(D1)  |
//| Risk: ATR stop sizing, R-multiple partials/trailing/time-stop    |
//+------------------------------------------------------------------+
// v2.0 – 2025-02-12 – Prop risk guards tightened, weekday/hour filters,
//                     stricter bias discipline and deeper CSV telemetry.
#property strict

#include <Trade\Trade.mqh>

#include "modules/TesterCompat.mqh"
#include "modules/RegimeFilter.mqh"
#include "modules/SessionFilter.mqh"
#include "modules/BiasEngine.mqh"
#include "modules/EntryEngine.mqh"
#include "modules/Sizer.mqh"
#include "modules/BrokerUtils.mqh"
#include "modules/RiskEngine.mqh"
#include "modules/ExitEngine.mqh"

/*
 * --------------------------------------------------------------------
 * PUBLIC PARAMETER SUMMARY (10 inputs)
 * 1. RiskPerTradePercent      – percent of equity risked per trade.
 * 2. MaxDailyLossPercent      – realised + open loss cap per day in percent.
 * 3. MaxStaticDrawdownPercent – static equity drawdown kill switch in percent
 *                               (<=0 disables the static kill switch for testing).
 * 4. AllowLongs               – enable long trades.
 * 5. AllowShorts              – enable short trades.
 * 6. SessionStartHour         – broker hour for session start (minutes fixed to 00).
 * 7. SessionEndHour           – broker hour for session end (minutes fixed to 45).
 * 8. BiasMode                 – multi-timeframe bias discipline profile.
 * 9. RRProfile                – exit / R-multiple management profile.
 *10. EnableFallbackEntries    – allow relaxed/fallback entries outside the
 *                               A-session core window.
 *
 * BiasMode:
 *  - BIAS_STRICT     enforces unanimous EMA slope alignment, raises slope/score
 *                    thresholds and disables neutral-bias trades.
 *  - BIAS_BALANCED   mirrors the legacy "Balanced v2" bias discipline with
 *                    controlled neutral exposure and selective fallbacks.
 *  - BIAS_AGGRESSIVE relaxes slope thresholds slightly and allows wider
 *                    neutral-bias participation.
 *
 * RRProfile:
 *  - RR_CONSERVATIVE uses a single 1.5R target with optional late time-stop.
 *  - RR_BALANCED     (default) applies 50-60% partials near 1.1R, BE around 0.9R
 *                    and trails from ~1.6R towards a 1.9R hard target.
 *  - RR_RUNNER       leaves a runner beyond 1R with loose trailing and no hard TP.
 */

enum ENUM_BiasMode
{
   BIAS_STRICT = 0,
   BIAS_BALANCED = 1,
   BIAS_AGGRESSIVE = 2
};

enum ENUM_RRProfile
{
   RR_CONSERVATIVE = 0,
   RR_BALANCED     = 1,
   RR_RUNNER       = 2
};

// --- Public inputs --------------------------------------------------
input double        RiskPerTradePercent      = 0.35;  // % of equity per trade (net of stop distance)
input double        MaxDailyLossPercent      = 5.00;  // realised + open loss cap per day in %
input double        MaxStaticDrawdownPercent = 10.00; // static equity DD kill switch (<=0 disables)
input int           MaxOpenPositions         = 2;     // simultaneous positions cap
input int           MaxTradesPerDay          = 3;     // trades per calendar day cap (0 = unlimited)
input bool          AllowLongs               = true;  // enable long trades
input bool          AllowShorts              = true;  // enable short trades
input bool          AllowMonday              = false; // weekday filters (broker time)
input bool          AllowTuesday             = true;
input bool          AllowWednesday           = true;
input bool          AllowThursday            = true;
input bool          AllowFriday              = true;
input int           SessionStartHour         = 7;     // broker time, minutes fixed to 00
input int           SessionEndHour           = 14;    // broker time, minutes fixed internally to 45
input string        AllowedEntryHours        = "8,9,10,11,12"; // comma separated broker hours
input ENUM_BiasMode BiasMode                 = BIAS_BALANCED;
input ENUM_RRProfile RRProfile               = RR_BALANCED;
input double        StrictSlopeMultiplier    = 1.35;  // slope multiplier for strict bias mode
input double        BalancedSlopeMultiplier  = 1.10;  // slope multiplier for balanced bias mode
input double        AggressiveSlopeMultiplier= 0.85;  // slope multiplier for aggressive bias mode
input double        FallbackRiskFactor       = 0.60;  // multiplier for fallback position size
input bool          EnableFallbackEntries    = false; // allow relaxed fallback entries
input bool          EnableCsvLogging         = false; // write extended CSV trade logs

// --- Internal constants ---------------------------------------------
const ulong   MAGIC_NUMBER = 20241026;
const string  TRADE_COMMENT = "XAU_Swing_TrendEA_Pro";
const bool    DEBUG_MODE = false;
const bool    FORCE_VERBOSE_LOG = false;
const bool    RANDOMIZE_ENTRY_EXIT = false;
const bool    ENABLE_CHART_ANNOTATIONS = true;
const bool    ENABLE_TRADE_TELEMETRY = true;
const int     SLIPPAGE_BUDGET_POINTS = 80;
const int     MAX_SPREAD_POINTS = 200;
const int     PROP_DAY_START_HOUR = 0;
const bool    USE_STATIC_OVERALL_DD = true;
const ENUM_TIMEFRAMES ENTRY_TIMEFRAME = PERIOD_H1;
const int     SESSION_START_MINUTE = 0;
const int     SESSION_END_MINUTE_DEFAULT = 45;
const int     SESSION_CUTOFF_MINUTE = 45;
const double  AGGRESSIVE_DISCOUNT = 0.05;
const double  AGGRESSIVE_FLOOR = 0.60;
const double  TIME_STOP_PROTECT_R_DEFAULT = 0.5;
const double  FALLBACK_SLOPE_SCALE_BASE = 0.75;
const double  FALLBACK_SCORE_DISCOUNT_BASE = 0.90;
const string  TELEMETRY_FOLDER = "XAU_Swing_TrendEA_Pro";
const string  TELEMETRY_PREFIX_BASE = "xau_bias_rr";

// TODO: Backtest XAUUSD H1 2021-2025 (spread 20) with BIAS_BALANCED/RR_BALANCED and BIAS_STRICT/RR_CONSERVATIVE.

struct StrategyConfig
{
   int    biasVotesRequired;
   double biasSlopeThH1;
   double biasSlopeThH4;
   double biasSlopeThD1;
   double biasSlopeConfirmH1;
   double biasSlopeConfirmH4;
   double biasSlopeConfirmD1;
   double biasScoreThresholdCore;
   double biasScoreThresholdEdge;
   double biasScoreRegimeLowBoost;
   double biasScoreRegimeHighBoost;
   double coreQualityLong;
   double coreQualityShort;
   double edgeQualityLong;
   double edgeQualityShort;
   double pullbackBodyAtrMin;
   double breakoutImpulseAtrMin;
   int    breakoutRangeBars;
   bool   allowAggressiveEntries;
   bool   allowLongs;
   bool   allowShorts;
   bool   enableFallbackEntry;
   bool   enableWeekdayFallback;
   int    fallbackMinHour;
   int    fallbackMaxPer7D;
   bool   requireStrongFallback;
   bool   requireTrendForFallback;
   bool   allowFallbackWhenBiasNeutral;
   double fallbackSlopeScale;
   double fallbackScoreDiscount;
   double fallbackRiskScale;
   double neutralBiasRiskScale;
   bool   allowNeutralBiasOnEdge;
   double regimeLowQualityBoost;
   double regimeHighQualityBoost;
   double regimeLowRiskScale;
   double regimeHighRiskScale;
   bool   useDynamicRisk;
   int    maxNewTradesPerDay;
   int    maxLosingTradesPerDay;
   int    maxLosingTradesInARow;
   double riskScaleAfterLosingStreak;
   double partialTPFraction;
   double breakEvenR;
   double partialTP_R;
   double trailStart_R;
   double trailDistance_R;
   double timeStopProtectR;
   double finalTarget_R;
   int    timeStopBars;
   double initialStopATR;
   bool   useHardFinalTP;
   bool   useTimeStop;
   bool   useAdaptiveSL;
   int    adaptiveAfterBars;
   double adaptiveMultiplier;
   double adaptiveMinProfitR;
   int    lateEntryCutoffHour;
   int    lateEntryCutoffMinute;
   int    sessionEndMinute;
   int    sessionCutoffMinute;
   bool   disallowNeutralEntries;
   bool   bypassSlopeScoreCheck;
   bool   bypassSlopeVoteCheck;
   bool   requireDirectionalBias;
};

StrategyConfig MakeBalancedConfig()
{
   StrategyConfig cfg;
   cfg.biasVotesRequired = 2;
   cfg.biasSlopeThH1 = 0.024;
   cfg.biasSlopeThH4 = 0.020;
   cfg.biasSlopeThD1 = 0.017;
   cfg.biasSlopeConfirmH1 = 0.022;
   cfg.biasSlopeConfirmH4 = 0.018;
   cfg.biasSlopeConfirmD1 = 0.013;
   cfg.biasScoreThresholdCore = 0.070;
   cfg.biasScoreThresholdEdge = 0.095;
   cfg.biasScoreRegimeLowBoost = 0.018;
   cfg.biasScoreRegimeHighBoost = 0.008;
   cfg.coreQualityLong = 0.82;
   cfg.coreQualityShort = 0.82;
   cfg.edgeQualityLong = 0.90;
   cfg.edgeQualityShort = 0.90;
   cfg.pullbackBodyAtrMin = 0.50;
   cfg.breakoutImpulseAtrMin = 0.46;
   cfg.breakoutRangeBars = 7;
   cfg.allowAggressiveEntries = false;
   cfg.allowLongs = true;
   cfg.allowShorts = true;
   cfg.enableFallbackEntry = true;
   cfg.enableWeekdayFallback = true;
   cfg.fallbackMinHour = 12;
   cfg.fallbackMaxPer7D = 2;
   cfg.requireStrongFallback = true;
   cfg.requireTrendForFallback = false;
   cfg.allowFallbackWhenBiasNeutral = true;
   cfg.fallbackSlopeScale = FALLBACK_SLOPE_SCALE_BASE;
   cfg.fallbackScoreDiscount = FALLBACK_SCORE_DISCOUNT_BASE;
   cfg.fallbackRiskScale = 1.0;
   cfg.neutralBiasRiskScale = 0.50;
   cfg.allowNeutralBiasOnEdge = true;
   cfg.regimeLowQualityBoost = 0.06;
   cfg.regimeHighQualityBoost = 0.03;
   cfg.regimeLowRiskScale = 0.60;
   cfg.regimeHighRiskScale = 1.05;
   cfg.useDynamicRisk = true;
   cfg.maxNewTradesPerDay = 3;
   cfg.maxLosingTradesPerDay = 3;
   cfg.maxLosingTradesInARow = 3;
   cfg.riskScaleAfterLosingStreak = 0.50;
   cfg.partialTPFraction = 0.40;
   cfg.breakEvenR = 0.85;
   cfg.partialTP_R = 1.20;
   cfg.trailStart_R = 1.90;
   cfg.trailDistance_R = 0.80;
   cfg.timeStopProtectR = 0.55;
   cfg.finalTarget_R = 2.30;
   cfg.timeStopBars = 36;
   cfg.initialStopATR = 1.18;
   cfg.useHardFinalTP = true;
   cfg.useTimeStop = true;
   cfg.useAdaptiveSL = true;
   cfg.adaptiveAfterBars = 10;
   cfg.adaptiveMultiplier = 1.2;
   cfg.adaptiveMinProfitR = 0.5;
   cfg.lateEntryCutoffHour = 14;
   cfg.lateEntryCutoffMinute = 0;
   cfg.sessionEndMinute = SESSION_END_MINUTE_DEFAULT;
   cfg.sessionCutoffMinute = SESSION_CUTOFF_MINUTE;
   cfg.disallowNeutralEntries = false;
   cfg.bypassSlopeScoreCheck = false;
   cfg.bypassSlopeVoteCheck = false;
   cfg.requireDirectionalBias = false;
   return cfg;
}
void ApplyBiasModeAdjustments(StrategyConfig &cfg,const ENUM_BiasMode mode,const bool fallbackEnabled)
{
   double slopeMult = BalancedSlopeMultiplier;
   if(mode==BIAS_STRICT)
      slopeMult = StrictSlopeMultiplier;
   else if(mode==BIAS_AGGRESSIVE)
      slopeMult = AggressiveSlopeMultiplier;

   if(slopeMult<=0.0)
      slopeMult = 1.0;

   cfg.biasSlopeThH1 *= slopeMult;
   cfg.biasSlopeThH4 *= slopeMult;
   cfg.biasSlopeThD1 *= slopeMult;
   cfg.biasSlopeConfirmH1 *= slopeMult;
   cfg.biasSlopeConfirmH4 *= slopeMult;
   cfg.biasSlopeConfirmD1 *= slopeMult;

   switch(mode)
   {
      case BIAS_STRICT:
         cfg.biasScoreThresholdCore *= 1.20;
         cfg.biasScoreThresholdEdge *= 1.25;
         cfg.biasVotesRequired = 3;
         cfg.allowNeutralBiasOnEdge = false;
         cfg.allowFallbackWhenBiasNeutral = false;
         cfg.enableFallbackEntry = false;
         cfg.enableWeekdayFallback = false;
         cfg.requireTrendForFallback = true;
         cfg.allowAggressiveEntries = false;
         cfg.disallowNeutralEntries = true;
         cfg.requireDirectionalBias = true;
         cfg.neutralBiasRiskScale = 0.0;
         cfg.maxLosingTradesPerDay = 2;
         cfg.maxLosingTradesInARow = 2;
         cfg.useDynamicRisk = true;
         break;
      case BIAS_AGGRESSIVE:
         cfg.biasScoreThresholdCore *= 0.85;
         cfg.biasScoreThresholdEdge *= 0.80;
         cfg.allowAggressiveEntries = true;
         cfg.requireStrongFallback = false;
         cfg.allowFallbackWhenBiasNeutral = true;
         cfg.neutralBiasRiskScale = 0.70;
         cfg.useDynamicRisk = true;
         cfg.enableFallbackEntry = fallbackEnabled;
         cfg.enableWeekdayFallback = fallbackEnabled;
         break;
      default: // BIAS_BALANCED
         cfg.enableFallbackEntry = fallbackEnabled;
         cfg.enableWeekdayFallback = fallbackEnabled;
         cfg.allowAggressiveEntries = false;
         cfg.requireTrendForFallback = false;
         cfg.allowFallbackWhenBiasNeutral = true;
         cfg.disallowNeutralEntries = false;
         cfg.requireDirectionalBias = false;
         cfg.neutralBiasRiskScale = 0.50;
         cfg.useDynamicRisk = true;
         break;
   }

   if(mode!=BIAS_STRICT)
   {
      cfg.enableFallbackEntry = fallbackEnabled;
   }
}

void ApplyRRProfileAdjustments(StrategyConfig &cfg,const ENUM_RRProfile profile)
{
   switch(profile)
   {
      case RR_CONSERVATIVE:
         cfg.partialTPFraction = 0.0;
         cfg.breakEvenR = 0.80;
         cfg.partialTP_R = 1.50;
         cfg.trailStart_R = 0.0;
         cfg.trailDistance_R = 0.0;
         cfg.finalTarget_R = 1.50;
         cfg.timeStopBars = 60;
         cfg.useHardFinalTP = true;
         cfg.useTimeStop = true;
         cfg.timeStopProtectR = 0.40;
         cfg.useAdaptiveSL = false;
         break;
      case RR_RUNNER:
         cfg.partialTPFraction = 0.35;
         cfg.breakEvenR = 0.85;
         cfg.partialTP_R = 1.00;
         cfg.trailStart_R = 1.20;
         cfg.trailDistance_R = 1.20;
         cfg.finalTarget_R = 3.50;
         cfg.timeStopBars = 70;
         cfg.useHardFinalTP = false;
         cfg.useTimeStop = true;
         cfg.timeStopProtectR = 0.30;
         cfg.useAdaptiveSL = true;
         cfg.adaptiveAfterBars = 12;
         cfg.adaptiveMultiplier = 1.3;
         cfg.adaptiveMinProfitR = 0.6;
         break;
      default: // RR_BALANCED
         cfg.partialTPFraction = 0.40;
         cfg.breakEvenR = 0.85;
         cfg.partialTP_R = 1.20;
         cfg.trailStart_R = 1.90;
         cfg.trailDistance_R = 0.80;
         cfg.finalTarget_R = 2.30;
         cfg.timeStopBars = 36;
         cfg.useHardFinalTP = true;
         cfg.useTimeStop = true;
         cfg.timeStopProtectR = 0.55;
         cfg.useAdaptiveSL = true;
         cfg.adaptiveAfterBars = 10;
         cfg.adaptiveMultiplier = 1.25;
         cfg.adaptiveMinProfitR = 0.55;
         break;
   }
}

string BiasModeToString(const ENUM_BiasMode mode)
{
   switch(mode)
   {
      case BIAS_STRICT:     return "BIAS_STRICT";
      case BIAS_AGGRESSIVE: return "BIAS_AGGRESSIVE";
      default:              return "BIAS_BALANCED";
   }
}

string RRProfileToString(const ENUM_RRProfile profile)
{
   switch(profile)
   {
      case RR_CONSERVATIVE: return "RR_CONSERVATIVE";
      case RR_RUNNER:       return "RR_RUNNER";
      default:              return "RR_BALANCED";
   }
}

string ComposeTelemetryPrefix(const ENUM_BiasMode bias,const ENUM_RRProfile profile)
{
   return TELEMETRY_PREFIX_BASE + "_" + BiasModeToString(bias) + "_" + RRProfileToString(profile);
}

StrategyConfig gConfig;
string         gBiasLabel = "";
string         gRRLabel   = "";

//--- globals
BrokerUtils   gBroker;
RegimeFilter  gRegime;
SessionFilter gSession;
BiasEngine    gBias;
EntryEngine   gEntry;
PositionSizer gSizer;
RiskEngine    gRisk;
ExitEngine    gExit;

datetime      gLastBarTime = 0;
datetime      gEntryHistory[];
int           gFallbackWeekId = -1;
bool          gFallbackUsedThisWeek = false;
bool          gAllowedWeekday[7];
bool          gAllowedHour[24];
bool          gVerboseDecisionLog = false;
#define      RECENT_TRADE_WINDOW 10
double        gRecentTradePnL[RECENT_TRADE_WINDOW];
int           gRecentTradeCount = 0;

//--- helper declarations
bool IsNewBar();
void EvaluateNewBar();
void ManageOpenPositions();
bool HasDirectionalPosition(const int direction);
void AnnotateChart(const string message,const color col=clrDodgerBlue);
void AttemptEntry(const EntrySignal &signal);
string SessionWindowToString(const SessionWindow window,const bool fallback);
string DirectionToString(const int direction);
void CloseAllPositions();
int  CountStrategyPositions();
void ConfigureTimeFilters();
bool IsWeekdayAllowed(const datetime when);
bool IsHourAllowed(const datetime when);
void RecordEntryTime(const datetime entryTime,const bool fallbackTrade);
void CleanupEntryHistory(const datetime reference);
int  EntriesLastSevenDays(const datetime reference);
int  ComputeWeekId(const datetime time);
bool ShouldUseFallbackEntry(const datetime signalTime,const int recentEntries);
void ResetRecentPnL();
void RecordClosedTradePnL(const double profit);
bool RecentPnLPositive();


//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
void ConfigureTimeFilters()
{
   for(int i=0;i<7;i++)
      gAllowedWeekday[i] = false;

   gAllowedWeekday[1] = AllowMonday;
   gAllowedWeekday[2] = AllowTuesday;
   gAllowedWeekday[3] = AllowWednesday;
   gAllowedWeekday[4] = AllowThursday;
   gAllowedWeekday[5] = AllowFriday;

   for(int h=0;h<24;h++)
      gAllowedHour[h] = false;

   string normalized = AllowedEntryHours;
   StringReplace(normalized,";",",");
   StringReplace(normalized," ","");
   string tokens[];
   int total = StringSplit(normalized,',',tokens);
   bool any = false;
   for(int i=0;i<total;i++)
   {
      string token = tokens[i];
      token = StringTrimLeft(token);
      token = StringTrimRight(token);
      if(StringLen(token)==0)
         continue;
      int hour = (int)StringToInteger(token);
      if(hour<0 || hour>23)
         continue;
      gAllowedHour[hour] = true;
      any = true;
   }

   if(!any)
   {
      int startHour = MathMax(0,MathMin(23,SessionStartHour));
      int endHour   = MathMax(0,MathMin(23,SessionEndHour));
      if(endHour < startHour)
         endHour = startHour;
      for(int h=startHour; h<=endHour; ++h)
         gAllowedHour[h] = true;
      if(startHour==endHour && !gAllowedHour[startHour])
      {
         for(int h=0;h<24;h++)
            gAllowedHour[h] = true;
      }
   }
}

bool IsWeekdayAllowed(const datetime when)
{
   MqlDateTime dt;
   TimeToStruct(when,dt);
   if(dt.day_of_week<0 || dt.day_of_week>6)
      return false;
   if(dt.day_of_week==0 || dt.day_of_week==6)
      return false;
   return gAllowedWeekday[dt.day_of_week];
}

bool IsHourAllowed(const datetime when)
{
   MqlDateTime dt;
   TimeToStruct(when,dt);
   int hour = dt.hour;
   if(hour<0 || hour>23)
      return false;
   return gAllowedHour[hour];
}

int OnInit()
{
   gConfig = MakeBalancedConfig();
   ApplyBiasModeAdjustments(gConfig,BiasMode,EnableFallbackEntries);
   ApplyRRProfileAdjustments(gConfig,RRProfile);
   gConfig.allowLongs = AllowLongs;
   gConfig.allowShorts = AllowShorts;
   gConfig.fallbackRiskScale = MathMax(0.0,MathMin(1.0,FallbackRiskFactor));
   if(MaxTradesPerDay>0)
   {
      gConfig.maxNewTradesPerDay = MaxTradesPerDay;
      if(gConfig.maxLosingTradesPerDay>MaxTradesPerDay)
         gConfig.maxLosingTradesPerDay = MaxTradesPerDay;
   }
   if(!EnableFallbackEntries)
   {
      gConfig.enableFallbackEntry = false;
      gConfig.enableWeekdayFallback = false;
   }
   gBiasLabel = BiasModeToString(BiasMode);
   gRRLabel = RRProfileToString(RRProfile);

   gVerboseDecisionLog = (DEBUG_MODE || FORCE_VERBOSE_LOG);
   gBroker.Configure(MAGIC_NUMBER,TRADE_COMMENT,20);
   gSession.Configure(SessionStartHour,SESSION_START_MINUTE,SessionEndHour,gConfig.sessionEndMinute);
   gSession.SetDebugMode(DEBUG_MODE,false);
   ConfigureTimeFilters();

   gEntry.Configure(RANDOMIZE_ENTRY_EXIT);
   gEntry.ConfigureSensitivity(gConfig.pullbackBodyAtrMin,gConfig.breakoutImpulseAtrMin,gConfig.breakoutRangeBars);
   gEntry.SetStopMultiplier(gConfig.initialStopATR);
   gEntry.SetQualityThresholds(gConfig.coreQualityLong,gConfig.coreQualityShort,
                               gConfig.edgeQualityLong,gConfig.edgeQualityShort,
                               gConfig.allowAggressiveEntries,AGGRESSIVE_DISCOUNT,AGGRESSIVE_FLOOR);
   gEntry.SetDirectionalPermissions(gConfig.allowLongs,gConfig.allowShorts);
   gEntry.ConfigureNeutralPolicy(gConfig.allowNeutralBiasOnEdge,gConfig.neutralBiasRiskScale);
   gEntry.ConfigureRegimeAdjustments(gConfig.regimeLowQualityBoost,gConfig.regimeHighQualityBoost,
                                     gConfig.regimeLowRiskScale,gConfig.regimeHighRiskScale);
   gEntry.SetFallbackPolicy(gConfig.requireStrongFallback,gConfig.fallbackRiskScale);

   gExit.ConfigureRManagement(gConfig.partialTPFraction,gConfig.breakEvenR,gConfig.partialTP_R,gConfig.finalTarget_R,
                              gConfig.trailStart_R,gConfig.trailDistance_R,
                              gConfig.useHardFinalTP,gConfig.useTimeStop,gConfig.timeStopBars,gConfig.timeStopProtectR);
   gExit.ConfigureAdaptiveSL(gConfig.useAdaptiveSL,gConfig.adaptiveAfterBars,gConfig.adaptiveMultiplier,gConfig.adaptiveMinProfitR);
   gExit.SetEntryTimeframe(ENTRY_TIMEFRAME);
   gExit.SetVerbose(gVerboseDecisionLog);
   string telemetryPrefix = ComposeTelemetryPrefix(BiasMode,RRProfile);
   gExit.ConfigureTelemetry(EnableCsvLogging,TELEMETRY_FOLDER,telemetryPrefix);

   string headerNames[20];
   string headerValues[20];
   headerNames[0]  = "RiskPerTradePercent";      headerValues[0]  = DoubleToString(RiskPerTradePercent,2);
   headerNames[1]  = "MaxDailyLossPercent";     headerValues[1]  = DoubleToString(MaxDailyLossPercent,2);
   headerNames[2]  = "MaxStaticDrawdownPercent";headerValues[2]  = DoubleToString(MaxStaticDrawdownPercent,2);
   headerNames[3]  = "MaxOpenPositions";        headerValues[3]  = IntegerToString(MaxOpenPositions);
   headerNames[4]  = "MaxTradesPerDay";         headerValues[4]  = IntegerToString(MaxTradesPerDay);
   headerNames[5]  = "AllowLongs";              headerValues[5]  = (AllowLongs?"true":"false");
   headerNames[6]  = "AllowShorts";             headerValues[6]  = (AllowShorts?"true":"false");
   headerNames[7]  = "AllowMonday";             headerValues[7]  = (AllowMonday?"true":"false");
   headerNames[8]  = "AllowTuesday";            headerValues[8]  = (AllowTuesday?"true":"false");
   headerNames[9]  = "AllowWednesday";          headerValues[9]  = (AllowWednesday?"true":"false");
   headerNames[10] = "AllowThursday";           headerValues[10] = (AllowThursday?"true":"false");
   headerNames[11] = "AllowFriday";             headerValues[11] = (AllowFriday?"true":"false");
   headerNames[12] = "SessionStartHour";        headerValues[12] = IntegerToString(SessionStartHour);
   headerNames[13] = "SessionEndHour";          headerValues[13] = IntegerToString(SessionEndHour);
   headerNames[14] = "AllowedEntryHours";       headerValues[14] = AllowedEntryHours;
   headerNames[15] = "BiasMode";                headerValues[15] = gBiasLabel;
   headerNames[16] = "RRProfile";               headerValues[16] = gRRLabel;
   headerNames[17] = "EnableFallbackEntries";   headerValues[17] = (EnableFallbackEntries?"true":"false");
   headerNames[18] = "FallbackRiskFactor";      headerValues[18] = DoubleToString(FallbackRiskFactor,2);
   headerNames[19] = "EnableCsvLogging";        headerValues[19] = (EnableCsvLogging?"true":"false");
   gExit.SetTelemetryConfigSnapshot(gBiasLabel,gRRLabel,headerNames,headerValues,20);

   string persistKey = StringFormat("STEA:%s:%I64u",_Symbol,MAGIC_NUMBER);
   double ddPercent = (MaxStaticDrawdownPercent>0.0 ? MaxStaticDrawdownPercent : 0.0);
   bool useStaticDD = (MaxStaticDrawdownPercent>0.0 && USE_STATIC_OVERALL_DD);
   // RiskEngine uses the day-anchor equity for daily caps and the recorded initial equity for
   // the static drawdown guard so that all percent checks reference a consistent capital base.
   gRisk.Configure(RISK_PERCENT_PER_TRADE,RiskPerTradePercent,MaxDailyLossPercent,ddPercent,
                   PROP_DAY_START_HOUR,persistKey,useStaticDD,(double)SLIPPAGE_BUDGET_POINTS);
   gRisk.SetDebugMode(DEBUG_MODE);
   gRisk.SetVerboseMode(gVerboseDecisionLog);
   gRisk.SetDynamicRiskEnabled(gConfig.useDynamicRisk);
   gRisk.ConfigureTradeDiscipline(gConfig.maxNewTradesPerDay,gConfig.maxLosingTradesPerDay,
                                  gConfig.maxLosingTradesInARow,gConfig.riskScaleAfterLosingStreak);

   if(!gRegime.Init(_Symbol,14))
   {
      Print("Failed to initialise regime filter");
      return INIT_FAILED;
   }
   if(!gBias.Init(_Symbol))
   {
      Print("Failed to initialise bias engine");
      return INIT_FAILED;
   }
   gBias.ConfigureThresholds(gConfig.biasVotesRequired,gConfig.biasSlopeThH1,gConfig.biasSlopeThH4,gConfig.biasSlopeThD1);
   gBias.SetSlopeThreshold(1.0);
   gBias.SetDebug(gVerboseDecisionLog);
   if(!gSizer.Init(_Symbol))
   {
      Print("Failed to initialise position sizer");
      return INIT_FAILED;
   }
   gRegime.Update(true);
   ArrayResize(gEntryHistory,0);
   gFallbackWeekId = -1;
   gFallbackUsedThisWeek = false;
   ResetRecentPnL();
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialisation                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   gBias.Release();
   gRegime.Release();
}

bool IsNewBar()
{
   datetime currentBarTime = iTime(_Symbol,ENTRY_TIMEFRAME,0);
   if(currentBarTime<=0)
      return false;

   if(currentBarTime==gLastBarTime)
      return false;

   if(gLastBarTime>currentBarTime)
   {
      gLastBarTime = currentBarTime;
      return false;
   }

   gLastBarTime = currentBarTime;
   return true;
}

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
{
   gRisk.OnNewDay();
   gRegime.Update();
   gRisk.RefreshOpenRisk(gSizer,MAGIC_NUMBER);

   if(gRisk.DailyLimitBreached())
   {
      Print("Daily equity loss limit breached -> closing all positions");
      CloseAllPositions();
      return;
   }

   if(gRisk.KillSwitchLatched())
      return;

   // MaxStaticDrawdownPercent guard: flatten and latch until the EA is restarted.
   if(gRisk.EquityKillSwitchTriggered())
   {
      PrintFormat("Equity drawdown kill switch triggered (MaxStaticDrawdownPercent=%.2f%%)",MaxStaticDrawdownPercent);
      CloseAllPositions();
      return;
   }

   ManageOpenPositions();

   if(!IsNewBar())
      return;

   EvaluateNewBar();
}

void EvaluateNewBar()
{
   datetime signalTime = gLastBarTime;
   int recentEntries = EntriesLastSevenDays(signalTime);
   int currentWeek = ComputeWeekId(signalTime);
   if(currentWeek!=gFallbackWeekId)
   {
      gFallbackWeekId = currentWeek;
      gFallbackUsedThisWeek = false;
   }
   if(!IsWeekdayAllowed(signalTime))
   {
      AnnotateChart("Weekday filter active",clrSilver);
      return;
   }
   if(!IsHourAllowed(signalTime))
   {
      AnnotateChart("Hour filter active",clrSilver);
      return;
   }
   bool useFallback = ShouldUseFallbackEntry(signalTime,recentEntries);
   double slopeScale = (useFallback ? gConfig.fallbackSlopeScale : 1.0);
   gBias.SetSlopeThreshold(slopeScale);
   if(gVerboseDecisionLog)
   {
      PrintFormat("ENTRY TRACE: new bar %s fallback=%s slopeScale=%.2f entries7d=%d",TimeToString(signalTime,TIME_DATE|TIME_MINUTES),
                  useFallback?"true":"false",slopeScale,recentEntries);
   }
   if(!gBias.Update(gRegime))
   {
      if(gVerboseDecisionLog)
         PrintFormat("ENTRY TRACE: Bias update failed at %s",TimeToString(signalTime,TIME_DATE|TIME_MINUTES));
      return;
   }

   TrendBias bias;
   gBias.ComputeTrendBias(bias,useFallback,useFallback);
   RegimeBucket regimeBucket = gRegime.CurrentBucket();
   if(gVerboseDecisionLog)
   {
      PrintFormat("BIAS TRACE: dir=%d strength=%d score=%.3f votesStrong L%d/S%d votesNear L%d/S%d slopes=%.3f/%.3f/%.3f th=%.3f/%.3f/%.3f",
                  bias.direction,(int)bias.strength,bias.score,
                  bias.votesStrongLong,bias.votesStrongShort,
                  bias.votesNearLong,bias.votesNearShort,
                  bias.slopeH1,bias.slopeH4,bias.slopeD1,
                  bias.thresholdH1,bias.thresholdH4,bias.thresholdD1);
   }

   if(gConfig.requireDirectionalBias && bias.direction==0)
   {
      if(gVerboseDecisionLog)
         Print("ENTRY TRACE: bias direction unresolved -> blocked by trend filter");
      return;
   }
   if(gConfig.disallowNeutralEntries && bias.strength==BIAS_NEUTRAL)
   {
      if(gVerboseDecisionLog)
         Print("ENTRY TRACE: neutral bias blocked by mode configuration");
      return;
   }
   if(BiasMode==BIAS_STRICT)
   {
      if(bias.direction==0)
      {
         if(gVerboseDecisionLog)
            Print("ENTRY TRACE: strict bias mode requires resolved direction");
         return;
      }
      int strictDir = (bias.direction>0 ? 1 : -1);
      if(bias.signH1!=strictDir || bias.signH4!=strictDir || bias.signD1!=strictDir)
      {
         if(gVerboseDecisionLog)
            Print("ENTRY TRACE: strict bias mode requires all slopes aligned");
         return;
      }
   }
   if(useFallback && gConfig.requireTrendForFallback && (bias.strength==BIAS_NEUTRAL || bias.direction==0))
   {
      if(gVerboseDecisionLog)
         Print("ENTRY TRACE: fallback disabled because bias is not trending");
      useFallback = false;
   }
   if(useFallback && !gConfig.allowFallbackWhenBiasNeutral && bias.strength==BIAS_NEUTRAL)
   {
      if(gVerboseDecisionLog)
         Print("ENTRY TRACE: fallback blocked for neutral bias");
      return;
   }

   SessionWindow window;
   if(!gSession.AllowsEntry(signalTime,window))
   {
      AnnotateChart("Session filter blocked entry",clrSilver);
      if(DEBUG_MODE)
         PrintFormat("ENTRY DEBUG: Session filter blocked entry at %s",TimeToString(signalTime,TIME_DATE|TIME_MINUTES));
      else if(gVerboseDecisionLog)
         PrintFormat("ENTRY TRACE: Session filter blocked entry at %s",TimeToString(signalTime,TIME_DATE|TIME_MINUTES));
      return;
   }

   if(!gConfig.enableFallbackEntry && window!=SESSION_CORE)
   {
      if(gVerboseDecisionLog)
         Print("ENTRY TRACE: fallback disabled -> only core session trades allowed");
      return;
   }

   if(gConfig.lateEntryCutoffHour>=0)
   {
      int cutoff = MathMax(0,MathMin(23*60+59,gConfig.lateEntryCutoffHour*60 + gConfig.lateEntryCutoffMinute));
      MqlDateTime dt;
      TimeToStruct(signalTime,dt);
      int minutesNow = dt.hour*60 + dt.min;
      if(minutesNow>cutoff)
      {
         if(gVerboseDecisionLog)
         {
            PrintFormat("ENTRY TRACE: late cutoff %02d:%02d exceeded at %02d:%02d",cutoff/60,cutoff%60,dt.hour,dt.min);
         }
         return;
      }
   }

   double scoreThreshold = (window==SESSION_CORE ? gConfig.biasScoreThresholdCore : gConfig.biasScoreThresholdEdge);
   if(regimeBucket==REGIME_LOW)
      scoreThreshold += gConfig.biasScoreRegimeLowBoost;
   else if(regimeBucket==REGIME_HIGH)
      scoreThreshold += gConfig.biasScoreRegimeHighBoost;
   if(useFallback)
      scoreThreshold *= gConfig.fallbackScoreDiscount;

   if(!gConfig.bypassSlopeScoreCheck)
   {
      double biasScoreAbs = MathAbs(bias.score);
      if(biasScoreAbs < scoreThreshold)
      {
         if(gVerboseDecisionLog)
         {
            PrintFormat("ENTRY TRACE: bias score %.4f below threshold %.4f (regime=%d window=%d)",biasScoreAbs,scoreThreshold,(int)regimeBucket,(int)window);
         }
         return;
      }
   }

   bool directionResolved = (bias.direction!=0);
   if(!gConfig.bypassSlopeVoteCheck)
   {
      int slopeVotes = 0;
      if(MathAbs(bias.slopeH1)>=gConfig.biasSlopeConfirmH1) slopeVotes++;
      if(MathAbs(bias.slopeH4)>=gConfig.biasSlopeConfirmH4) slopeVotes++;
      if(MathAbs(bias.slopeD1)>=gConfig.biasSlopeConfirmD1) slopeVotes++;

      if(directionResolved && slopeVotes<2 && bias.strength!=BIAS_STRONG && !useFallback)
      {
         if(gVerboseDecisionLog)
         {
            PrintFormat("ENTRY TRACE: slope confirmations=%d below requirement for bias strength %d",slopeVotes,(int)bias.strength);
         }
         return;
      }

      if(directionResolved && !useFallback)
      {
         if(bias.direction>0 && bias.slopeD1 < gConfig.biasSlopeConfirmD1)
         {
            if(gVerboseDecisionLog)
               Print("ENTRY TRACE: D1 slope insufficient for long bias");
            return;
         }
         if(bias.direction<0 && (-bias.slopeD1) < gConfig.biasSlopeConfirmD1)
         {
            if(gVerboseDecisionLog)
               Print("ENTRY TRACE: D1 slope insufficient for short bias");
            return;
         }
      }
   }

   if(regimeBucket==REGIME_LOW && bias.strength==BIAS_NEUTRAL && !useFallback)
   {
      if(gVerboseDecisionLog)
         Print("ENTRY TRACE: neutral bias blocked in low-vol regime");
      return;
   }

   MqlRates rates[];
   ArraySetAsSeries(rates,true);
   int barsNeeded = MathMax(6,gConfig.breakoutRangeBars+2);
   int copied = CopyRates(_Symbol,ENTRY_TIMEFRAME,0,barsNeeded,rates);
   if(copied<3)
   {
      if(gVerboseDecisionLog)
         PrintFormat("ENTRY TRACE: insufficient rate data copied=%d",copied);
      return;
   }

   EntrySignal signal;
   bool allowAggressiveBoost = (gConfig.allowAggressiveEntries && RecentPnLPositive());
   if(!gEntry.Evaluate(bias,gRegime,window,rates,copied,useFallback,useFallback,gVerboseDecisionLog,allowAggressiveBoost,signal))
   {
      if(gVerboseDecisionLog)
         Print("ENTRY TRACE: EntryEngine returned no signal");
      return;
   }

   if(HasDirectionalPosition(signal.direction))
   {
      AnnotateChart("Position in same direction already open",clrSilver);
      return;
   }

   AttemptEntry(signal);
}

//+------------------------------------------------------------------+
//| Manage open positions                                            |
//+------------------------------------------------------------------+
// ManageOpenPositions delegates all R-based exit logic to the ExitEngine.
void ManageOpenPositions()
{
   gExit.Manage(gBroker,gSizer,gRegime);
}

//+------------------------------------------------------------------+
//| Check for open position in direction                             |
//+------------------------------------------------------------------+
bool HasDirectionalPosition(const int direction)
{
   if(direction==0)
      return false;

   ENUM_POSITION_TYPE need = (direction>0 ? POSITION_TYPE_BUY : POSITION_TYPE_SELL);
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol)
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=MAGIC_NUMBER)
         continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)!=need)
         continue;
      return true;
   }
   return false;
}

int CountStrategyPositions()
{
   int count = 0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol)
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=MAGIC_NUMBER)
         continue;
      count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| Attempt to open trade                                            |
//+------------------------------------------------------------------+
// AttemptEntry performs spread/risk checks, position sizing and order placement for validated signals.
void AttemptEntry(const EntrySignal &signal)
{
   if(DEBUG_MODE)
   {
      string dirStr = DirectionToString(signal.direction);
      string sessionStr = SessionWindowToString(signal.session,signal.fallbackRelaxed);
      PrintFormat("ENTRY DEBUG: signal dir=%s score=%.2f biasDir=%d biasScore=%.2f slopes=H1 %.3f H4 %.3f D1 %.3f session=%s fallback=%s",
                  dirStr,signal.quality,signal.biasDirection,signal.biasScore,
                  signal.biasSlopeH1,signal.biasSlopeH4,signal.biasSlopeD1,
                  sessionStr,signal.fallbackRelaxed?"true":"false");
      PrintFormat("ENTRY DEBUG: AttemptEntry dir=%d entry=%.2f stop=%.2f quality=%.2f biasStrength=%d riskScale=%.2f fallback=%s",
                  signal.direction,signal.entryPrice,signal.stopLoss,signal.quality,(int)signal.biasStrength,
                  signal.riskScale,signal.fallbackRelaxed?"true":"false");
   }

   if(MaxOpenPositions>0 && CountStrategyPositions() >= MaxOpenPositions)
   {
      AnnotateChart("Max open positions reached",clrSilver);
      if(gVerboseDecisionLog)
         PrintFormat("ENTRY TRACE: MaxOpenPositions=%d reached",MaxOpenPositions);
      return;
   }

   double stopPoints = gSizer.StopDistancePoints(signal.entryPrice,signal.stopLoss);
   if(stopPoints<=0.0)
   {
      if(DEBUG_MODE)
         Print("ENTRY DEBUG: stopPoints <= 0 -> abort entry");
      return;
   }

   if(DEBUG_MODE)
      PrintFormat("ENTRY DEBUG: computed stopPoints=%.1f",stopPoints);

   double bid = SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double point = SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   if(point<=0.0)
      point = _Point;
   if(point>0.0)
   {
      int spreadPts = (int)MathRound((ask-bid)/point);
      if(spreadPts>MAX_SPREAD_POINTS)
      {
         if(ENABLE_CHART_ANNOTATIONS)
            AnnotateChart("Spread zu hoch",clrTomato);
         if(DEBUG_MODE)
            PrintFormat("ENTRY DEBUG: spreadPts=%d > MAX_SPREAD_POINTS=%d -> skip entry",spreadPts,MAX_SPREAD_POINTS);
         else
            PrintFormat("Spread %dpt > MAX_SPREAD_POINTS %d -> Entry verworfen",spreadPts,MAX_SPREAD_POINTS);
         return;
      }
      else if(DEBUG_MODE)
      {
         PrintFormat("ENTRY DEBUG: spreadPts=%d within limit %d",spreadPts,MAX_SPREAD_POINTS);
      }
   }

   double volume=0.0;
   double riskPercent=0.0;
   if(!gRisk.AllowNewTrade(stopPoints,gSizer,gRegime,volume,riskPercent,signal.riskScale))
   {
      AnnotateChart("Risk guard prevented entry",clrTomato);
      if(DEBUG_MODE)
         Print("ENTRY DEBUG: RiskEngine.AllowNewTrade() returned false");
      return;
   }

   if(DEBUG_MODE)
      PrintFormat("ENTRY DEBUG: proposed volume=%.4f riskPercent=%.2f%%",volume,riskPercent);

   if(!gRisk.HasSufficientMargin(signal.direction,volume,signal.entryPrice))
   {
      if(ENABLE_CHART_ANNOTATIONS)
         AnnotateChart("Margin check failed",clrTomato);
      if(DEBUG_MODE)
         Print("ENTRY DEBUG: Margin check failed -> entry skipped");
      else
         Print("Margin check failed -> entry skipped");
      return;
   }

   double tp = 0.0;
   if(gConfig.useHardFinalTP)
   {
      tp = signal.entryPrice + signal.direction*gConfig.finalTarget_R*stopPoints*point;
   }
   if(!gBroker.OpenPosition(signal.direction,volume,signal.entryPrice,signal.stopLoss,tp))
   {
      if(DEBUG_MODE)
         PrintFormat("ENTRY DEBUG: gBroker.OpenPosition() failed dir=%d",signal.direction);
      else
         PrintFormat("Order open failed for direction %d",signal.direction);
      return;
   }

   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol)
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=MAGIC_NUMBER)
         continue;
      gExit.Register(ticket,signal,stopPoints,volume,riskPercent,gBiasLabel);
      gRisk.OnTradeOpened(riskPercent);
      AnnotateChart(StringFormat("Opened %s %.2flots",signal.direction>0?"BUY":"SELL",volume),clrGreen);
      if(DEBUG_MODE)
         PrintFormat("ENTRY DEBUG: Opened position volume=%.2f direction=%d",volume,signal.direction);
      RecordEntryTime(TimeCurrent(),signal.fallbackRelaxed);
      break;
   }
}

string SessionWindowToString(const SessionWindow window,const bool fallback)
{
   string label = "NONE";
   if(window==SESSION_CORE)
      label = "CORE";
   else if(window==SESSION_EDGE)
      label = "EDGE";
   if(fallback && window!=SESSION_NONE)
      label = label + " (FALLBACK)";
   return label;
}

string DirectionToString(const int direction)
{
   if(direction>0)
      return "LONG";
   if(direction<0)
      return "SHORT";
   return "FLAT";
}

//+------------------------------------------------------------------+
//| Chart annotation helper                                          |
//+------------------------------------------------------------------+
void AnnotateChart(const string message,const color col)
{
   if(!ENABLE_CHART_ANNOTATIONS)
      return;
   Comment(message);
}

//+------------------------------------------------------------------+
//| Close all positions                                              |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol)
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=MAGIC_NUMBER)
         continue;
      gBroker.ClosePosition(ticket);
   }
}

void RecordEntryTime(const datetime entryTime,const bool fallbackTrade)
{
   CleanupEntryHistory(entryTime);
   int size = ArraySize(gEntryHistory);
   ArrayResize(gEntryHistory,size+1);
   gEntryHistory[size] = entryTime;
   if(fallbackTrade)
      gFallbackUsedThisWeek = true;
}

void CleanupEntryHistory(const datetime reference)
{
   int size = ArraySize(gEntryHistory);
   if(size<=0)
      return;
   datetime cutoff = reference - 7*24*3600;
   int writeIndex = 0;
   for(int i=0;i<size;i++)
   {
      if(gEntryHistory[i]>=cutoff)
         gEntryHistory[writeIndex++] = gEntryHistory[i];
   }
   if(writeIndex!=size)
      ArrayResize(gEntryHistory,writeIndex);
}

int EntriesLastSevenDays(const datetime reference)
{
   CleanupEntryHistory(reference);
   return ArraySize(gEntryHistory);
}

int ComputeWeekId(const datetime time)
{
   if(time<=0)
      return -1;
   MqlDateTime dt;
   TimeToStruct(time,dt);
   int week = (int)MathFloor((double)dt.day_of_year/7.0);
   return dt.year*100 + week;
}

bool ShouldUseFallbackEntry(const datetime signalTime,const int recentEntries)
{
   if(!gConfig.enableFallbackEntry)
      return false;
   if(signalTime<=0)
      return false;
   if(gFallbackUsedThisWeek)
      return false;
   MqlDateTime dt;
   TimeToStruct(signalTime,dt);
   if(!gConfig.enableWeekdayFallback)
   {
      if(recentEntries>=2)
         return false;
      if(dt.day_of_week!=5)
         return false;
      if(dt.hour<gConfig.fallbackMinHour)
         return false;
   }
   else
   {
      if(dt.day_of_week==0 || dt.day_of_week==6)
         return false;
      if(dt.hour<gConfig.fallbackMinHour)
         return false;
      if(gConfig.fallbackMaxPer7D>0 && recentEntries>=gConfig.fallbackMaxPer7D)
         return false;
   }
   return true;
}

void ResetRecentPnL()
{
   for(int i=0;i<RECENT_TRADE_WINDOW;i++)
      gRecentTradePnL[i] = 0.0;
   gRecentTradeCount = 0;
}

void RecordClosedTradePnL(const double profit)
{
   if(RECENT_TRADE_WINDOW<=0)
      return;
   if(gRecentTradeCount<RECENT_TRADE_WINDOW)
   {
      gRecentTradePnL[gRecentTradeCount++] = profit;
   }
   else
   {
      for(int i=1;i<RECENT_TRADE_WINDOW;i++)
         gRecentTradePnL[i-1] = gRecentTradePnL[i];
      gRecentTradePnL[RECENT_TRADE_WINDOW-1] = profit;
   }
}

bool RecentPnLPositive()
{
   // Used to temporarily relax quality thresholds when the last trades netted profit.
   double sum = 0.0;
   for(int i=0;i<gRecentTradeCount;i++)
      sum += gRecentTradePnL[i];
   return (gRecentTradeCount>0 && sum>0.0);
}

//+------------------------------------------------------------------+
//| Trade transaction                                                |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result)
{
   if(trans.type==TRADE_TRANSACTION_DEAL_ADD && trans.deal>0)
   {
      ulong deal = trans.deal;
      ENUM_DEAL_ENTRY entryType = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal,DEAL_ENTRY);
      double profit = HistoryDealGetDouble(deal,DEAL_PROFIT);
      ulong positionId = (ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID);
      if(entryType==DEAL_ENTRY_OUT)
      {
         bool positionStillOpen = PositionSelectByTicket(positionId);
         double riskRemoved = 0.0;
         if(!positionStillOpen)
         {
            double exitPrice = HistoryDealGetDouble(deal,DEAL_PRICE);
            datetime exitTime = (datetime)HistoryDealGetInteger(deal,DEAL_TIME);
            double commission = HistoryDealGetDouble(deal,DEAL_COMMISSION);
            double swap = HistoryDealGetDouble(deal,DEAL_SWAP);
            riskRemoved = gExit.OnPositionClosed(positionId,exitPrice,exitTime,profit,commission,swap);
         }
         if(!positionStillOpen)
         {
            gRisk.OnTradeClosed(profit,riskRemoved);
            RecordClosedTradePnL(profit);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| OnTester acceptance checks                                       |
//+------------------------------------------------------------------+
double OnTester()
{
   double trades = TesterStatistics((ENUM_STATISTICS)STAT_TRADES);
   double winTrades = TesterStatistics((ENUM_STATISTICS)STAT_PROFIT_TRADES);
   double profitFactor = TesterStatistics((ENUM_STATISTICS)STAT_PROFIT_FACTOR);
   double maxDD = TesterStatistics((ENUM_STATISTICS)STAT_EQUITY_DDRELATIVE);
   double sharpe = TesterStatistics((ENUM_STATISTICS)STAT_SHARPE_RATIO);
   double avgHoldHours = TesterStatistics((ENUM_STATISTICS)STAT_AVG_HOLD_TIME)/3600.0;
   double equityCorr = TesterStatistics((ENUM_STATISTICS)STAT_LINEAR_CORRELATION_EQUITY);
   double winRate = (trades>0.0 ? winTrades/trades*100.0 : 0.0);

   bool pass=true;
   if(trades<2500 || trades>3400) pass=false;
   if(winRate<49.0 || winRate>53.0) pass=false;
   if(profitFactor<1.26 || profitFactor>1.36) pass=false;
   if(maxDD>12.0) pass=false;
   if(sharpe<1.6 || sharpe>2.4) pass=false;
   if(avgHoldHours<6.0 || avgHoldHours>10.0) pass=false;
   if(equityCorr<0.80) pass=false;

   PrintFormat("Tester summary: trades=%.0f winRate=%.2f%% PF=%.2f DD=%.2f%% sharpe=%.2f avgHold=%.2fh corr=%.2f",
               trades,winRate,profitFactor,maxDD,sharpe,avgHoldHours,equityCorr);
   return pass?1.0:0.0;
}
