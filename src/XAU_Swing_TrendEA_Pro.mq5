//+------------------------------------------------------------------+
//| XAU_Swing_TrendEA_Pro.mq5                                        |
//| Refactored swing/breakout Expert Advisor for XAUUSD (MT5)        |
//| Session: 07:00-14:45, Bias votes: EMA20(H1)/EMA34(H4)/EMA50(D1)  |
//| Risk: ATR stop sizing, R-multiple partials/trailing/time-stop    |
//+------------------------------------------------------------------+
// v1.3 – 2024-05-08 – Directional score thresholds, adaptive ATR stop tightening,
//                     extended R-management defaults and richer entry logging.
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
 * 1. RiskPerTradePercent   – percent of equity risked per trade.
 * 2. DailyLossCapPercent   – realised + open loss cap per day in percent.
 * 3. EquityDDKillPercent   – static equity drawdown kill switch in percent.
 * 4. SessionStartHour      – broker hour for session start (minutes fixed to 00).
 * 5. SessionEndHour        – broker hour for session end (minutes fixed to 45).
 * 6. QualityMode           – adjusts entry quality gates and fallback strictness.
 * 7. TrendFilterMode       – tunes slope thresholds and bias discipline.
 * 8. InitialSL_ATR_Multiple – ATR multiple for the initial protective stop.
 * 9. FinalTargetR          – R-multiple for the final profit target.
 *10. TimeStopBars          – bars before the time-stop pulls SL to +0.5 R.
 *
 * Drawdown kill switch: once EquityDDKillPercent is reached the RiskEngine closes all
 * open trades and latches the guard so no new orders are placed until the EA is
 * reloaded. This keeps the prop-firm style equity guard fully deterministic.
 *
 * QualityMode:
 *  - QUALITY_AGGRESSIVE lowers quality requirements and keeps win-streak risk boosts.
 *  - QUALITY_BALANCED mirrors the legacy xau_balanced_v2 behaviour.
 *  - QUALITY_CONSERVATIVE tightens quality gates and only allows fallback trades with
 *    a clear trend bias.
 *
 * TrendFilterMode:
 *  - TREND_OFF relaxes slope filters but still requires a resolved bias direction.
 *  - TREND_NORMAL keeps the original multi-timeframe slope thresholds.
 *  - TREND_STRICT raises slope requirements and blocks neutral/contradictory biases.
 */

enum ENUM_QualityMode
{
   QUALITY_AGGRESSIVE = 0,
   QUALITY_BALANCED   = 1,
   QUALITY_CONSERVATIVE = 2
};

enum ENUM_TrendFilterMode
{
   TREND_OFF = 0,
   TREND_NORMAL = 1,
   TREND_STRICT = 2
};

// --- Public inputs --------------------------------------------------
input double RiskPerTradePercent   = 0.5;   // % of equity per trade
input double DailyLossCapPercent   = 5.0;   // realised + open loss cap per day in %
input double EquityDDKillPercent   = 12.0;  // hard max equity DD in %
input int    SessionStartHour      = 7;     // broker time, minutes fixed to 0
input int    SessionEndHour        = 14;    // broker time, minutes fixed internally to 45
input ENUM_QualityMode QualityMode = QUALITY_BALANCED;
input ENUM_TrendFilterMode TrendFilterMode = TREND_NORMAL;
input double InitialSL_ATR_Multiple = 1.2;
input double FinalTargetR            = 2.5;
input int    TimeStopBars            = 40;   // bars on the entry timeframe

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
const string  TELEMETRY_PREFIX_BASE = "xau_balanced_v2";

// TODO: Backtest XAUUSD H1 2021-2025 (spread 20) with QUALITY_BALANCED and QUALITY_CONSERVATIVE.

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
   cfg.biasSlopeThH1 = 0.020;
   cfg.biasSlopeThH4 = 0.018;
   cfg.biasSlopeThD1 = 0.015;
   cfg.biasSlopeConfirmH1 = 0.018;
   cfg.biasSlopeConfirmH4 = 0.014;
   cfg.biasSlopeConfirmD1 = 0.010;
   cfg.biasScoreThresholdCore = 0.060;
   cfg.biasScoreThresholdEdge = 0.085;
   cfg.biasScoreRegimeLowBoost = 0.015;
   cfg.biasScoreRegimeHighBoost = 0.005;
   cfg.coreQualityLong = 0.76;
   cfg.coreQualityShort = 0.76;
   cfg.edgeQualityLong = 0.85;
   cfg.edgeQualityShort = 0.85;
   cfg.pullbackBodyAtrMin = 0.45;
   cfg.breakoutImpulseAtrMin = 0.42;
   cfg.breakoutRangeBars = 6;
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
   cfg.neutralBiasRiskScale = 0.40;
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
   cfg.breakEvenR = 0.90;
   cfg.partialTP_R = 1.10;
   cfg.trailStart_R = 1.80;
   cfg.trailDistance_R = 0.90;
   cfg.timeStopProtectR = TIME_STOP_PROTECT_R_DEFAULT;
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

void ApplyQualityModeAdjustments(StrategyConfig &cfg,const ENUM_QualityMode mode)
{
   switch(mode)
   {
      case QUALITY_CONSERVATIVE:
         cfg.coreQualityLong = MathMin(0.95,cfg.coreQualityLong + 0.05);
         cfg.coreQualityShort = MathMin(0.95,cfg.coreQualityShort + 0.05);
         cfg.edgeQualityLong = MathMin(0.95,cfg.edgeQualityLong + 0.05);
         cfg.edgeQualityShort = MathMin(0.95,cfg.edgeQualityShort + 0.05);
         cfg.requireTrendForFallback = true;
         cfg.allowFallbackWhenBiasNeutral = false;
         cfg.allowNeutralBiasOnEdge = false;
         cfg.allowAggressiveEntries = false;
         break;
      case QUALITY_AGGRESSIVE:
         // QUALITY_AGGRESSIVE keeps the win-streak risk boost and slightly lower quality gates.
         cfg.coreQualityLong = MathMax(0.60,cfg.coreQualityLong - 0.02);
         cfg.coreQualityShort = MathMax(0.60,cfg.coreQualityShort - 0.02);
         cfg.edgeQualityLong = MathMax(0.60,cfg.edgeQualityLong - 0.02);
         cfg.edgeQualityShort = MathMax(0.60,cfg.edgeQualityShort - 0.02);
         cfg.allowAggressiveEntries = true;
         cfg.requireStrongFallback = false;
         cfg.allowFallbackWhenBiasNeutral = true;
         break;
      default:
         cfg.allowAggressiveEntries = false;
         cfg.allowFallbackWhenBiasNeutral = true;
         break;
   }
}

void ApplyTrendFilterAdjustments(StrategyConfig &cfg,const ENUM_TrendFilterMode mode)
{
   switch(mode)
   {
      case TREND_STRICT:
         cfg.biasSlopeThH1 *= 1.35;
         cfg.biasSlopeThH4 *= 1.35;
         cfg.biasSlopeThD1 *= 1.35;
         cfg.biasSlopeConfirmH1 *= 1.35;
         cfg.biasSlopeConfirmH4 *= 1.35;
         cfg.biasSlopeConfirmD1 *= 1.35;
         cfg.biasScoreThresholdCore *= 1.35;
         cfg.biasScoreThresholdEdge *= 1.35;
         cfg.allowNeutralBiasOnEdge = false;
         cfg.allowFallbackWhenBiasNeutral = false;
         cfg.requireTrendForFallback = true;
         cfg.disallowNeutralEntries = true;
         cfg.requireDirectionalBias = true;
         break;
      case TREND_OFF:
         cfg.biasSlopeThH1 *= 0.40;
         cfg.biasSlopeThH4 *= 0.40;
         cfg.biasSlopeThD1 *= 0.40;
         cfg.biasSlopeConfirmH1 *= 0.40;
         cfg.biasSlopeConfirmH4 *= 0.40;
         cfg.biasSlopeConfirmD1 *= 0.40;
         cfg.biasScoreThresholdCore = 0.0;
         cfg.biasScoreThresholdEdge = 0.0;
         cfg.bypassSlopeScoreCheck = true;
         cfg.bypassSlopeVoteCheck = true;
         cfg.requireDirectionalBias = true;
         cfg.disallowNeutralEntries = false;
         break;
      default:
         break;
   }
}

string QualityModeToString(const ENUM_QualityMode mode)
{
   switch(mode)
   {
      case QUALITY_AGGRESSIVE:   return "QUALITY_AGGRESSIVE";
      case QUALITY_CONSERVATIVE: return "QUALITY_CONSERVATIVE";
      default:                   return "QUALITY_BALANCED";
   }
}

string TrendFilterModeToString(const ENUM_TrendFilterMode mode)
{
   switch(mode)
   {
      case TREND_OFF:    return "TREND_OFF";
      case TREND_STRICT: return "TREND_STRICT";
      default:           return "TREND_NORMAL";
   }
}

string ComposeTelemetryPrefix(const ENUM_QualityMode quality,const ENUM_TrendFilterMode trend)
{
   return TELEMETRY_PREFIX_BASE + "_" + QualityModeToString(quality) + "_" + TrendFilterModeToString(trend);
}

StrategyConfig gConfig;
string         gQualityLabel = "";
string         gTrendLabel = "";

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
int OnInit()
{
   gConfig = MakeBalancedConfig();
   ApplyQualityModeAdjustments(gConfig,QualityMode);
   ApplyTrendFilterAdjustments(gConfig,TrendFilterMode);
   gQualityLabel = QualityModeToString(QualityMode);
   gTrendLabel = TrendFilterModeToString(TrendFilterMode);

   gVerboseDecisionLog = (DEBUG_MODE || FORCE_VERBOSE_LOG);
   gBroker.Configure(MAGIC_NUMBER,TRADE_COMMENT,20);
   gSession.Configure(SessionStartHour,SESSION_START_MINUTE,SessionEndHour,gConfig.sessionEndMinute);
   gSession.SetDebugMode(DEBUG_MODE,false);

   gEntry.Configure(RANDOMIZE_ENTRY_EXIT);
   gEntry.ConfigureSensitivity(gConfig.pullbackBodyAtrMin,gConfig.breakoutImpulseAtrMin,gConfig.breakoutRangeBars);
   gEntry.SetStopMultiplier(InitialSL_ATR_Multiple);
   gEntry.SetQualityThresholds(gConfig.coreQualityLong,gConfig.coreQualityShort,
                               gConfig.edgeQualityLong,gConfig.edgeQualityShort,
                               gConfig.allowAggressiveEntries,AGGRESSIVE_DISCOUNT,AGGRESSIVE_FLOOR);
   gEntry.SetDirectionalPermissions(gConfig.allowLongs,gConfig.allowShorts);
   gEntry.ConfigureNeutralPolicy(gConfig.allowNeutralBiasOnEdge,gConfig.neutralBiasRiskScale);
   gEntry.ConfigureRegimeAdjustments(gConfig.regimeLowQualityBoost,gConfig.regimeHighQualityBoost,
                                     gConfig.regimeLowRiskScale,gConfig.regimeHighRiskScale);
   gEntry.SetFallbackPolicy(gConfig.requireStrongFallback);

   gExit.ConfigureRManagement(gConfig.partialTPFraction,gConfig.breakEvenR,gConfig.partialTP_R,FinalTargetR,
                              gConfig.trailStart_R,gConfig.trailDistance_R,
                              gConfig.useHardFinalTP,gConfig.useTimeStop,TimeStopBars,gConfig.timeStopProtectR);
   gExit.ConfigureAdaptiveSL(gConfig.useAdaptiveSL,gConfig.adaptiveAfterBars,gConfig.adaptiveMultiplier,gConfig.adaptiveMinProfitR);
   gExit.SetEntryTimeframe(ENTRY_TIMEFRAME);
   gExit.SetVerbose(gVerboseDecisionLog);
   string telemetryPrefix = ComposeTelemetryPrefix(QualityMode,TrendFilterMode);
   gExit.ConfigureTelemetry(ENABLE_TRADE_TELEMETRY,TELEMETRY_FOLDER,telemetryPrefix);

   string headerNames[10];
   string headerValues[10];
   headerNames[0] = "RiskPerTradePercent";   headerValues[0] = DoubleToString(RiskPerTradePercent,2);
   headerNames[1] = "DailyLossCapPercent";   headerValues[1] = DoubleToString(DailyLossCapPercent,2);
   headerNames[2] = "EquityDDKillPercent";   headerValues[2] = DoubleToString(EquityDDKillPercent,2);
   headerNames[3] = "SessionStartHour";      headerValues[3] = IntegerToString(SessionStartHour);
   headerNames[4] = "SessionEndHour";        headerValues[4] = IntegerToString(SessionEndHour);
   headerNames[5] = "QualityMode";           headerValues[5] = gQualityLabel;
   headerNames[6] = "TrendFilterMode";       headerValues[6] = gTrendLabel;
   headerNames[7] = "InitialSL_ATR_Multiple";headerValues[7] = DoubleToString(InitialSL_ATR_Multiple,2);
   headerNames[8] = "FinalTargetR";          headerValues[8] = DoubleToString(FinalTargetR,2);
   headerNames[9] = "TimeStopBars";          headerValues[9] = IntegerToString(TimeStopBars);
   gExit.SetTelemetryConfigSnapshot(gQualityLabel,gTrendLabel,headerNames,headerValues,10);

   string persistKey = StringFormat("STEA:%s:%I64u",_Symbol,MAGIC_NUMBER);
   gRisk.Configure(RISK_PERCENT_PER_TRADE,RiskPerTradePercent,DailyLossCapPercent,EquityDDKillPercent,
                   PROP_DAY_START_HOUR,persistKey,USE_STATIC_OVERALL_DD,(double)SLIPPAGE_BUDGET_POINTS);
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

   // EquityDDKillPercent guard: flatten and latch until the EA is restarted.
   if(gRisk.EquityKillSwitchTriggered())
   {
      PrintFormat("Equity drawdown kill switch triggered (EquityDDKillPercent=%.2f%%)",EquityDDKillPercent);
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
      tp = signal.entryPrice + signal.direction*FinalTargetR*stopPoints*point;
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
      gExit.Register(ticket,signal,stopPoints,volume,riskPercent);
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
