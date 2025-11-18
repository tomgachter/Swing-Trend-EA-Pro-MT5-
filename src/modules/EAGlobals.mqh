#ifndef __EA_GLOBALS_MQH__
#define __EA_GLOBALS_MQH__

#include "CalendarCompat.mqh"
#include "TradeCompat.mqh"
#include "presets.mqh"

enum EntryMode
{
   ENTRY_BREAKOUT = 0,
   ENTRY_PULLBACK = 1,
   ENTRY_HYBRID   = 2
};

enum BreakEvenMode
{
   BREAK_EVEN_OFF     = 0,
   BREAK_EVEN_ATR     = 1,
   BREAK_EVEN_R_BASED = 2
};

enum TrailingMode
{
   TRAIL_OFF        = 0,
   TRAIL_ATR        = 1,
   TRAIL_FRACTAL    = 2,
   TRAIL_CHANDELIER = 3
};

enum InpPreset
{
   PRESET_XAUUSD_H1_DEFAULT = 0,
   PRESET_XAUUSD_M30_CONSERVATIVE = 1,
   PRESET_CUSTOM = 2
};

//+------------------------------------------------------------------+
//| Input parameters                                                 |
//+------------------------------------------------------------------+
input double            RiskPct              = 0.70;                   // % risk per base trade
input int               Aggressiveness       = 1;                      // 0=Defensive,1=Neutral,2=Aggressive
input bool              Pyramiding           = true;                   // Allow add-on positions
input int               MaxOpenPositions     = 2;                      // Simultaneous trade cap
input ENUM_RiskGuardsPreset RiskGuardsPreset = RISK_BALANCED;          // Risk guard preset

input InpPreset         InpPresetSelection    = PRESET_XAUUSD_H1_DEFAULT; // Active configuration preset
input string            InpSymbol             = "XAUUSD";                // Nur als Preset-Hinweis, EA handelt immer _Symbol

//--- Timeframes
input ENUM_TIMEFRAMES   InpTF_Entry           = PERIOD_H1;               // Default (XAUUSD, H1): entry timeframe
input ENUM_TIMEFRAMES   InpTF_TrailATR        = PERIOD_H4;               // Default (XAUUSD, H1): ATR timeframe for stops
input ENUM_TIMEFRAMES   InpTF_Trend1          = PERIOD_H4;               // Default (XAUUSD, H1): trend vote 1 timeframe
input ENUM_TIMEFRAMES   InpTF_Trend2          = PERIOD_D1;               // Default (XAUUSD, H1): trend vote 2 timeframe
input ENUM_TIMEFRAMES   InpTF_Trend3          = PERIOD_W1;               // Default (XAUUSD, H1): trend vote 3 timeframe

//--- Trend filters
input int               InpEMA_Entry_Period   = 34;                      // Default (XAUUSD, H1): entry EMA period
input int               InpEMA_Trend1_Period  = 55;                      // Default (XAUUSD, H1): H4 trend EMA period
input int               InpEMA_Trend2_Period  = 89;                      // Default (XAUUSD, H1): D1 trend EMA period
input int               InpEMA_Trend3_Period  = 144;                     // Default (XAUUSD, H1): W1 trend EMA period
input int               InpTrendVotesRequired = 2;                       // Default (XAUUSD, H1): votes required for bias
input bool              InpUseClosedBarTrend  = true;                    // Default (XAUUSD, H1): use closed bars for trend votes
input bool              InpUseSlopeFilter     = true;                    // Default (XAUUSD, H1): enable EMA slope filter
input double            InpSlopeMin           = 0.15;                    // Default (XAUUSD, H1): minimum normalized slope
input bool              InpHTFConfirm         = true;                    // Default (XAUUSD, H1): require H4 EMA confirmation

//--- Entry mode
input EntryMode         InpEntryMode          = ENTRY_HYBRID;            // Default (XAUUSD, H1): entry execution mode

//--- Donchian breakout
input int               InpDonchianBars_Base  = 16;                      // Default (XAUUSD, H1): base Donchian channel length
input double            InpDonchianBars_MinMax= 10.0;                    // Default (XAUUSD, H1): min/max deviation from base
input double            InpBreakoutBufferPts  = 6.0;                     // Default (XAUUSD, H1): breakout buffer in points
input double            InpBreakoutBufferATR  = 0.12;                    // Breakout buffer as ATR fraction

//--- Regime controls
input int               InpATR_D1_Period      = 14;                      // Default (XAUUSD, H1): ATR period for D1 regime
input double            InpATR_D1_MinPts      = 8000.0;                  // Default (XAUUSD, H1): minimum D1 ATR in points
input double            InpATR_D1_MaxPts      = 42000.0;                 // Default (XAUUSD, H1): maximum D1 ATR in points
input double            InpATR_D1_Pivot       = 22000.0;                 // Default (XAUUSD, H1): pivot D1 ATR for scaling
input double            InpRegimeMinFactor    = 0.70;                    // Default (XAUUSD, H1): minimum scaling factor
input double            InpRegimeMaxFactor    = 1.45;                    // Default (XAUUSD, H1): maximum scaling factor
input int               InpADX_Period         = 14;                      // Default (XAUUSD, H1): ADX period (H4)
input double            InpMinADX_H4          = 20.0;                    // Minimum ADX threshold

//--- Stops and targets
input int               InpATR_Period         = 14;                      // Default (XAUUSD, H1): ATR period for SL/TP (H4)
input double            InpATR_SL_mult_Base   = 2.40;                    // Default (XAUUSD, H1): base ATR multiple for SL
input double            InpATR_TP_mult_Base   = 3.60;                    // Default (XAUUSD, H1): base ATR multiple for TP

//--- Position management
input int               InpMinHoldBars        = 6;                       // Default (XAUUSD, H1): minimum bars before management
input BreakEvenMode     InpBreakEven_Mode     = BREAK_EVEN_R_BASED;      // Default (XAUUSD, H1): break-even management mode
input double            InpBreakEven_ATR      = 1.0;                     // Default (XAUUSD, H1): ATR multiple for BE (if ATR mode)
input double            InpBreakEven_R        = 1.0;                     // Default (XAUUSD, H1): R multiple for BE (if R-based)
input bool              InpPartialClose_Enable= true;                    // Default (XAUUSD, H1): enable partial close
input double            InpPartialClose_R     = 1.7;                     // Default (XAUUSD, H1): R multiple to trigger partial close
input double            InpPartialClose_Pct   = 35.0;                    // Default (XAUUSD, H1): percentage closed at partial target
input int               InpMaxHoldBars        = 48;                      // Default (XAUUSD, H1): maximum holding bars

//--- Trailing options
input TrailingMode      InpTrailingMode       = TRAIL_CHANDELIER;        // Default (XAUUSD, H1): trailing mode
input double            InpATR_Trail_mult     = 1.8;                     // Default (XAUUSD, H1): ATR multiple for trailing
input int               InpFractal_ShiftBars  = 2;                       // Default (XAUUSD, H1): fractal shift bars

//--- Anti-noise controls
input int               InpCooldownBars       = 1;                       // Default (XAUUSD, H1): bars between new entries
input double            InpMaxExtension_ATR   = 2.0;                     // Default (XAUUSD, H1): maximum distance from EMA in ATR

//--- Session filters
input bool              InpUseSessionBias     = true;                    // Default (XAUUSD, H1): restrict entries to core sessions
input int               InpSess1_StartHour    = 8;                       // Default (XAUUSD, H1): Session 1 start (UTC)
input int               InpSess1_EndHour      = 12;                      // Default (XAUUSD, H1): Session 1 end (UTC)
input int               InpSess2_StartHour    = 13;                      // Default (XAUUSD, H1): Session 2 start (UTC)
input int               InpSess2_EndHour      = 22;                      // Default (XAUUSD, H1): Session 2 end (UTC)
input bool              InpNoMondayMorning    = true;                    // Default (XAUUSD, H1): skip Monday morning entries
input int               InpTZ_OffsetHours     = 0;                       // Default (XAUUSD, H1): broker time offset vs UTC
input bool              InpFlatOnFriday       = true;                    // Default (XAUUSD, H1): flat positions on Friday evening
input string            InpFridayFlatTime     = "20:30";                 // Default (XAUUSD, H1): Friday flat time (HH:MM)

//--- News filter
input bool              InpUseNewsFilter      = false;                   // Default (XAUUSD, H1): disable economic news filter for swing trading
input EACalendarEventImportance InpNewsImpact = EA_CALENDAR_IMPORTANCE_HIGH; // Default (XAUUSD, H1): filtered news impact
input int               InpNewsBlockMinutesBefore = 30;                  // Default (XAUUSD, H1): minutes before news to block
input int               InpNewsBlockMinutesAfter  = 30;                  // Default (XAUUSD, H1): minutes after news to block

//--- Pyramiding
input bool              InpAllowPyramiding    = true;                    // Default (XAUUSD, H1): enable add-on positions
input int               InpMaxAddonsPerBase   = 1;                       // Default (XAUUSD, H1): maximum add-ons per base trade
input double            InpAddonStep_ATR      = 1.0;                     // Default (XAUUSD, H1): ATR distance per add-on

//--- Equity filter
input bool              InpUseEquityFilter    = true;                    // Default (XAUUSD, H1): enable equity curve filter
input double            InpEqEMA_Alpha        = 0.06;                    // Default (XAUUSD, H1): EMA alpha for equity filter
input double            InpEqUnderwaterPct    = 5.0;                     // Allowed equity drawdown vs EMA
input double            InpEqBoostAdxDelta    = 3.0;                     // ADX delta for equity re-entry boost

//--- Position sizing and limits
input bool              InpUseFixedLots       = false;                   // Default (XAUUSD, H1): use fixed lot size
input double            InpFixedLots          = 0.50;                    // Default (XAUUSD, H1): fixed lot size
input double            InpRiskPerTradePct    = 0.50;                    // Default (XAUUSD, H1): risk per trade (% of balance)
input int               InpMaxOpenPositions   = 2;                       // Default (XAUUSD, H1): maximum simultaneous positions

//--- Monthly / weekly risk guards
input bool              InpUseMonthlyGuards      = true;                 // Default (XAUUSD, H1): enable monthly guard rails
input double            InpMTD_LossStopPct       = 1.5;                  // Default (XAUUSD, H1): stop trading after X% monthly loss
input double            InpMTD_LossStop_R        = 6.0;                  // Default (XAUUSD, H1): stop trading after -R monthly
input double            InpMTD_ProfitLockPct     = 3.0;                  // Default (XAUUSD, H1): lock profits after Y% monthly gain
input double            InpMTD_ProfitLock_R      = 10.0;                 // Default (XAUUSD, H1): lock profits after +R monthly

input int               InpMTD_MinTradesBeforeStop   = 5;                // Trades required before monthly stop engages
input bool              InpUseWeeklyCooling      = true;                 // Enable weekly cooling periods
input double            InpWTD_LossStopPct       = 1.0;                  // Pause after X% weekly loss
input int               InpWTD_MinTradesBeforeStop   = 3;                // Trades required before weekly stop engages
input int               InpMaxLosingDaysStreak   = 3;                    // Losing day streak trigger
input bool              InpUseSoftThrottleWhenMTDNeg = true;             // Use soft throttle when MTD < 0
input double            InpThrottle_RiskScale        = 0.5;              // Risk multiplier when month negative
input int               InpThrottle_ADX_Bonus        = 2;                // ADX bonus when month negative
input double            InpThrottle_BufferATR_Bonus  = 0.02;             // Buffer ATR bonus when month negative

input int               InpStartup_GraceDays         = 10;               // Days after start without MTD/WTD stops
input int               InpMonth_GraceDays           = 7;                // Days after month start with softer guards
input int               InpEq_MinTradesForFilter     = 5;                // Trades needed before equity filter is strict
input int               InpMonth_MinTrades           = 4;                // Minimum trades by month mid-point
input int               InpMonth_MidDay              = 15;               // Day of month to check activity floor
input int               InpActivity_ADX_Reduction    = 2;                // ADX reduction when activity low
input double            InpActivity_BufferATR_Red    = 0.02;             // Buffer ATR reduction when activity low

//--- Soft stop and time stop controls
input bool              InpUseSoftStop           = true;                 // Default (XAUUSD, H1): enable MAE-based soft stop
input double            InpSoftStop_MAE_ATR      = 0.8;                  // Default (XAUUSD, H1): MAE threshold in ATR multiples
input int               InpSoftStop_Bars         = 8;                    // Default (XAUUSD, H1): bars window for soft stop
input bool              InpUseTimeStop           = true;                 // Default (XAUUSD, H1): enable time stop
input int               InpTimeStop_Hours        = 24;                   // Default (XAUUSD, H1): hours without BE before closing

//--- Partial / runner controls
input double            InpRunner_ATR_mult       = 1.3;                  // Default (XAUUSD, H1): ATR multiple for runner trail
input bool              InpUseRunnerTrail        = true;                 // Default (XAUUSD, H1): enable runner trailing after partial

//--- Risk guards
input double            InpDailyLossStopPct   = 3.0;                     // Default (XAUUSD, H1): daily loss guard (% of equity)
input double            InpMaxDrawdownPct     = 10.0;                    // Default (XAUUSD, H1): equity drawdown guard (%)
input int               InpMaxSpreadPoints    = 300;                     // Default (XAUUSD, H1): maximum allowed spread (points)
input double            InpMinStopBufferAtr   = 0.10;                    // Default (XAUUSD, H1): minimum ATR buffer vs stop level (ratio)

//--- Magic number and debug
input int               InpMagic              = 11235813;                // Default (XAUUSD, H1): magic number for trades
input bool              InpDebug              = false;                   // Default (XAUUSD, H1): enable debug logging

//+------------------------------------------------------------------+
//| State                                                            |
//+------------------------------------------------------------------+
struct EAConfig
{
   string            symbol;
   ENUM_TIMEFRAMES   tfEntry;
   ENUM_TIMEFRAMES   tfTrailAtr;
   ENUM_TIMEFRAMES   tfTrend1;
   ENUM_TIMEFRAMES   tfTrend2;
   ENUM_TIMEFRAMES   tfTrend3;
   int               emaEntryPeriod;
   int               emaTrend1Period;
   int               emaTrend2Period;
   int               emaTrend3Period;
   int               trendVotesRequired;
   bool              useClosedBarTrend;
   bool              useSlopeFilter;
   double            slopeMin;
   bool              useHTFConfirm;
   EntryMode         entryMode;
   int               donchianBarsBase;
   double            donchianBarsMinMax;
   double            breakoutBufferPts;
   int               atrD1Period;
   double            atrD1MinPts;
   double            atrD1MaxPts;
   double            atrD1Pivot;
   double            regimeMinFactor;
   double            regimeMaxFactor;
   int               adxPeriod;
   double            minAdxH4;
   int               atrPeriod;
   double            atrSlMultBase;
   double            atrTpMultBase;
   int               minHoldBars;
   BreakEvenMode     breakEvenMode;
   double            breakEvenAtr;
   double            breakEvenR;
   bool              partialCloseEnable;
   double            partialCloseR;
   double            partialClosePct;
   bool              useTimeStop;
   int               timeStopHours;
   int               maxHoldBars;
   TrailingMode      trailingMode;
   double            atrTrailMult;
   int               fractalShiftBars;
   int               cooldownBars;
   double            maxExtensionAtr;
   bool              useSessionBias;
   int               sess1StartHour;
   int               sess1EndHour;
   int               sess2StartHour;
   int               sess2EndHour;
   int               tzOffsetHours;
   bool              flatOnFriday;
   int               fridayFlatMinutes;
   bool              useNewsFilter;
   EACalendarEventImportance newsImpact;
   int               newsBlockBefore;
   int               newsBlockAfter;
   bool              allowPyramiding;
   int               maxAddonsPerBase;
   double            addonStepAtr;
   bool              useEquityFilter;
   double            eqEmaAlpha;
   double            eqUnderwaterPct;
   double            eqBoostAdxDelta;
   bool              useFixedLots;
   double            fixedLots;
   double            riskPerTradePct;
   int               maxOpenPositions;
   double            dailyLossStopPct;
   double            maxDrawdownPct;
   int               maxSpreadPoints;
   double            minStopBufferAtr;
   int               magic;
   bool              debug;
};

EAConfig             gConfig;

Regime              gRegime            = REG_MID;
Preset              gPreset;
RiskGuardProfile    gRiskProfile;

datetime            lastBarTime           = 0;
datetime            lastEntryBarTime      = 0;
bool                didPartialClose       = false;
double              dayStartEquity        = 0.0;
double              equityPeak            = 0.0;
int                 daySerialAnchor       = -1;
double              eqEMA                 = 0.0;
double              lastBaseOpenPrice     = 0.0;
double              lastBaseLots          = 0.0;
int                 addonsOpened          = 0;
double              lastValidAtrD1Pts     = InpATR_D1_Pivot;   // Latest valid D1 ATR reading
datetime            gCoolingOffUntil      = 0;
datetime            gPauseUntil           = 0;                 // Global trading pause (UTC based)
double              gDailyPnL             = 0.0;
double              gWeeklyPnL            = 0.0;
double              gMonthlyPnL           = 0.0;
double              gMonthlyR             = 0.0;
double              gRiskScale            = 1.0;
int                 gTradesThisWeek       = 0;
int                 gTradesThisMonth      = 0;
int                 gLosingDaysStreak     = 0;
int                 gCurrentDay           = -1;
int                 gCurrentWeek          = -1;
int                 gCurrentMonth         = -1;
datetime            gStartupTime          = 0;

struct PositionMemo
{
   ulong             ticket;
   double            initialRiskPoints;
   double            entryAtrPoints;
   datetime          openTime;
   bool              isAddon;
   double            openPrice;
   int               direction;
   double            bestFavourablePts;
   double            worstAdversePts;
   double            initialVolume;
   double            riskPerLot;
   bool              runnerMode;
   double            lastKnownVolume;
};

PositionMemo        positionMemos[];

double              lastKnownAtrEntryPoints = 0.0;
datetime            fridayFlatAnchor    = 0;

struct TradeSnapshot
{
   double profitPts;
   double mfePts;
   double maePts;
   double initialRiskPts;
};

TradeSnapshot       completedTrades[];

//+------------------------------------------------------------------+
//| Indicator handles                                                |
//+------------------------------------------------------------------+
int                 hATR_H4               = INVALID_HANDLE;
int                 hATR_D1               = INVALID_HANDLE;
int                 hATR_Entry            = INVALID_HANDLE;
int                 hEMA_E                = INVALID_HANDLE;
int                 hEMA_T1               = INVALID_HANDLE;
int                 hEMA_T2               = INVALID_HANDLE;
int                 hEMA_T3               = INVALID_HANDLE;
int                 hADX_H4               = INVALID_HANDLE;
int                 hFractals             = INVALID_HANDLE;

EA_Trade            trade;

//+------------------------------------------------------------------+
//| Preset helpers implementation                                    |
//+------------------------------------------------------------------+
int ParseTimeToMinutes(const string hhmm)
{
   string parts[];
   int cnt=StringSplit(hhmm,':',parts);
   if(cnt<2)
      return 20*60+30; // default 20:30
   int h=(int)StringToInteger(parts[0]);
   int m=(int)StringToInteger(parts[1]);
   h= MathMax(0,MathMin(23,h));
   m= MathMax(0,MathMin(59,m));
   return h*60+m;
}


double ResolvePointScale(const string symbol,const double baselinePoint)
{
   if(baselinePoint<=0.0)
      return 1.0;

   double point=0.0;
   if(!SymbolInfoDouble(symbol,SYMBOL_POINT,point) || point<=0.0)
      return 1.0;

   double scale = baselinePoint/point;
   if(scale<=0.0)
      return 1.0;

   return scale;
}

void NormalizePointSensitiveSettings(EAConfig &settings,const double baselinePoint)
{
   double scale = ResolvePointScale(settings.symbol,baselinePoint);
   if(scale==1.0)
      return;

   settings.breakoutBufferPts *= scale;
   settings.atrD1MinPts       *= scale;
   settings.atrD1MaxPts       *= scale;
   settings.atrD1Pivot        *= scale;
   settings.maxSpreadPoints   = (int)MathRound(settings.maxSpreadPoints*scale);
}

void ApplyPresetDefaults(EAConfig &settings,const InpPreset preset)
{
   // Shared defaults that may still leverage user supplied symbol/magic/debug values.
   settings.symbol          = _Symbol; // Always trade the current chart symbol.
   settings.magic           = InpMagic;
   settings.debug           = InpDebug;
   settings.tzOffsetHours   = InpTZ_OffsetHours;

   const double baselinePoint = 0.001; // Preset tuning assumes 0.1 pip (1e-3) point size for gold.

   switch(preset)
   {
      case PRESET_XAUUSD_M30_CONSERVATIVE:
         settings.tfEntry             = PERIOD_M30;
         settings.tfTrailAtr          = PERIOD_H4;
         settings.tfTrend1            = PERIOD_H4;
         settings.tfTrend2            = PERIOD_D1;
         settings.tfTrend3            = PERIOD_W1;
         settings.emaEntryPeriod      = 34;
         settings.emaTrend1Period     = 55;
         settings.emaTrend2Period     = 89;
         settings.emaTrend3Period     = 144;
         settings.trendVotesRequired  = 2;
         settings.useClosedBarTrend   = true;
         settings.useSlopeFilter      = true;
         settings.slopeMin            = 0.16;
         settings.useHTFConfirm       = true;
         settings.entryMode           = ENTRY_HYBRID;
         settings.donchianBarsBase    = 16;
         settings.donchianBarsMinMax  = 10.0;
         settings.breakoutBufferPts   = 5.0;
         settings.atrD1Period         = 14;
         settings.atrD1MinPts         = 7500.0;
         settings.atrD1MaxPts         = 38000.0;
         settings.atrD1Pivot          = 19000.0;
         settings.regimeMinFactor     = 0.70;
         settings.regimeMaxFactor     = 1.40;
         settings.adxPeriod           = 14;
         settings.minAdxH4            = 19.0;
         settings.atrPeriod           = 14;
         settings.atrSlMultBase       = 2.30;
         settings.atrTpMultBase       = 3.40;
         settings.minHoldBars         = 6;
         settings.breakEvenMode       = BREAK_EVEN_R_BASED;
         settings.breakEvenAtr        = 1.0;
         settings.breakEvenR          = 1.0;
         settings.partialCloseEnable  = true;
         settings.partialCloseR       = 1.40;
         settings.partialClosePct     = 33.0;
         settings.useTimeStop         = InpUseTimeStop;
         settings.timeStopHours       = InpTimeStop_Hours;
         settings.maxHoldBars         = 60;
         settings.trailingMode        = TRAIL_CHANDELIER;
         settings.atrTrailMult        = 1.9;
         settings.fractalShiftBars    = 2;
         settings.cooldownBars        = 1;
         settings.maxExtensionAtr     = 1.9;
         settings.useSessionBias      = false;
         settings.sess1StartHour      = 6;
         settings.sess1EndHour        = 11;
         settings.sess2StartHour      = 12;
         settings.sess2EndHour        = 20;
         settings.flatOnFriday        = true;
         settings.fridayFlatMinutes   = ParseTimeToMinutes(InpFridayFlatTime);
         settings.useNewsFilter       = InpUseNewsFilter;
         settings.newsImpact          = InpNewsImpact;
         settings.newsBlockBefore     = InpNewsBlockMinutesBefore;
         settings.newsBlockAfter      = InpNewsBlockMinutesAfter;
         settings.allowPyramiding     = true;
         settings.maxAddonsPerBase    = 1;
         settings.addonStepAtr        = 1.0;
         settings.useEquityFilter     = true;
         settings.eqEmaAlpha          = InpEqEMA_Alpha;
         settings.eqUnderwaterPct     = 5.0;
         settings.eqBoostAdxDelta     = 3.0;
         settings.useFixedLots        = InpUseFixedLots;
         settings.fixedLots           = InpFixedLots;
         settings.riskPerTradePct     = 0.45;
         settings.maxOpenPositions    = 2;
         settings.dailyLossStopPct    = 2.5;
         settings.maxDrawdownPct      = InpMaxDrawdownPct;
         settings.maxSpreadPoints     = InpMaxSpreadPoints;
         settings.minStopBufferAtr    = InpMinStopBufferAtr;
         break;

      case PRESET_XAUUSD_H1_DEFAULT:
      default:
         settings.tfEntry             = PERIOD_H1;
         settings.tfTrailAtr          = PERIOD_H4;
         settings.tfTrend1            = PERIOD_H4;
         settings.tfTrend2            = PERIOD_D1;
         settings.tfTrend3            = PERIOD_W1;
         settings.emaEntryPeriod      = 34;
         settings.emaTrend1Period     = 55;
         settings.emaTrend2Period     = 89;
         settings.emaTrend3Period     = 144;
         settings.trendVotesRequired  = 2;
         settings.useClosedBarTrend   = true;
         settings.useSlopeFilter      = true;
         settings.slopeMin            = 0.15;
         settings.useHTFConfirm       = true;
         settings.entryMode           = ENTRY_HYBRID;
         settings.donchianBarsBase    = 16;
         settings.donchianBarsMinMax  = 10.0;
         settings.breakoutBufferPts   = 5.0;
         settings.atrD1Period         = 14;
         settings.atrD1MinPts         = 8000.0;
         settings.atrD1MaxPts         = 42000.0;
         settings.atrD1Pivot          = 22000.0;
         settings.regimeMinFactor     = 0.70;
         settings.regimeMaxFactor     = 1.45;
         settings.adxPeriod           = 14;
         settings.minAdxH4            = 20.0;
         settings.atrPeriod           = 14;
         settings.atrSlMultBase       = 2.40;
         settings.atrTpMultBase       = 3.60;
         settings.minHoldBars         = 6;
         settings.breakEvenMode       = BREAK_EVEN_R_BASED;
         settings.breakEvenAtr        = 1.0;
         settings.breakEvenR          = 1.0;
         settings.partialCloseEnable  = true;
         settings.partialCloseR       = 1.7;
         settings.partialClosePct     = 35.0;
         settings.useTimeStop         = InpUseTimeStop;
         settings.timeStopHours       = InpTimeStop_Hours;
         settings.maxHoldBars         = 48;
         settings.trailingMode        = TRAIL_CHANDELIER;
         settings.atrTrailMult        = 1.8;
         settings.fractalShiftBars    = 2;
         settings.cooldownBars        = 1;
         settings.maxExtensionAtr     = 2.0;
         settings.useSessionBias      = true;
         settings.sess1StartHour      = 8;
         settings.sess1EndHour        = 12;
         settings.sess2StartHour      = 13;
         settings.sess2EndHour        = 22;
         settings.flatOnFriday        = InpFlatOnFriday;
         settings.fridayFlatMinutes   = ParseTimeToMinutes(InpFridayFlatTime);
         settings.useNewsFilter       = InpUseNewsFilter;
         settings.newsImpact          = InpNewsImpact;
         settings.newsBlockBefore     = InpNewsBlockMinutesBefore;
         settings.newsBlockAfter      = InpNewsBlockMinutesAfter;
         settings.allowPyramiding     = InpAllowPyramiding;
         settings.maxAddonsPerBase    = InpMaxAddonsPerBase;
         settings.addonStepAtr        = InpAddonStep_ATR;
         settings.useEquityFilter     = InpUseEquityFilter;
         settings.eqEmaAlpha          = InpEqEMA_Alpha;
         settings.eqUnderwaterPct     = InpEqUnderwaterPct;
         settings.eqBoostAdxDelta     = InpEqBoostAdxDelta;
         settings.useFixedLots        = InpUseFixedLots;
         settings.fixedLots           = InpFixedLots;
         settings.riskPerTradePct     = InpRiskPerTradePct;
         settings.maxOpenPositions    = InpMaxOpenPositions;
         settings.dailyLossStopPct    = InpDailyLossStopPct;
         settings.maxDrawdownPct      = InpMaxDrawdownPct;
         settings.maxSpreadPoints     = InpMaxSpreadPoints;
         settings.minStopBufferAtr    = InpMinStopBufferAtr;
         break;
   }

   NormalizePointSensitiveSettings(settings,baselinePoint);
}

void LoadInputsIntoConfig(EAConfig &settings)
{
   settings.symbol             = _Symbol; // Preset hint only; trading uses _Symbol.
   settings.tfEntry            = InpTF_Entry;
   settings.tfTrailAtr         = InpTF_TrailATR;
   settings.tfTrend1           = InpTF_Trend1;
   settings.tfTrend2           = InpTF_Trend2;
   settings.tfTrend3           = InpTF_Trend3;
   settings.emaEntryPeriod     = InpEMA_Entry_Period;
   settings.emaTrend1Period    = InpEMA_Trend1_Period;
   settings.emaTrend2Period    = InpEMA_Trend2_Period;
   settings.emaTrend3Period    = InpEMA_Trend3_Period;
   settings.trendVotesRequired = InpTrendVotesRequired;
   settings.useClosedBarTrend  = InpUseClosedBarTrend;
   settings.useSlopeFilter     = InpUseSlopeFilter;
   settings.slopeMin           = InpSlopeMin;
   settings.useHTFConfirm      = InpHTFConfirm;
   settings.entryMode          = InpEntryMode;
   settings.donchianBarsBase   = InpDonchianBars_Base;
   settings.donchianBarsMinMax = InpDonchianBars_MinMax;
   settings.breakoutBufferPts  = InpBreakoutBufferPts;
   settings.atrD1Period        = InpATR_D1_Period;
   settings.atrD1MinPts        = InpATR_D1_MinPts;
   settings.atrD1MaxPts        = InpATR_D1_MaxPts;
   settings.atrD1Pivot         = InpATR_D1_Pivot;
   settings.regimeMinFactor    = InpRegimeMinFactor;
   settings.regimeMaxFactor    = InpRegimeMaxFactor;
   settings.adxPeriod          = InpADX_Period;
   settings.minAdxH4           = InpMinADX_H4;
   settings.atrPeriod          = InpATR_Period;
   settings.atrSlMultBase      = InpATR_SL_mult_Base;
   settings.atrTpMultBase      = InpATR_TP_mult_Base;
   settings.minHoldBars        = InpMinHoldBars;
   settings.breakEvenMode      = InpBreakEven_Mode;
   settings.breakEvenAtr       = InpBreakEven_ATR;
   settings.breakEvenR         = InpBreakEven_R;
   settings.partialCloseEnable = InpPartialClose_Enable;
   settings.partialCloseR      = InpPartialClose_R;
   settings.partialClosePct    = InpPartialClose_Pct;
   settings.useTimeStop        = InpUseTimeStop;
   settings.timeStopHours      = InpTimeStop_Hours;
   settings.maxHoldBars        = InpMaxHoldBars;
   settings.trailingMode       = InpTrailingMode;
   settings.atrTrailMult       = InpATR_Trail_mult;
   settings.fractalShiftBars   = InpFractal_ShiftBars;
   settings.cooldownBars       = InpCooldownBars;
   settings.maxExtensionAtr    = InpMaxExtension_ATR;
   settings.useSessionBias     = InpUseSessionBias;
   settings.sess1StartHour     = InpSess1_StartHour;
   settings.sess1EndHour       = InpSess1_EndHour;
   settings.sess2StartHour     = InpSess2_StartHour;
   settings.sess2EndHour       = InpSess2_EndHour;
   settings.tzOffsetHours      = InpTZ_OffsetHours;
   settings.flatOnFriday       = InpFlatOnFriday;
   settings.fridayFlatMinutes  = ParseTimeToMinutes(InpFridayFlatTime);
   settings.useNewsFilter      = InpUseNewsFilter;
   settings.newsImpact         = InpNewsImpact;
   settings.newsBlockBefore    = InpNewsBlockMinutesBefore;
   settings.newsBlockAfter     = InpNewsBlockMinutesAfter;
   settings.allowPyramiding    = InpAllowPyramiding;
   settings.maxAddonsPerBase   = InpMaxAddonsPerBase;
   settings.addonStepAtr       = InpAddonStep_ATR;
   settings.useEquityFilter    = InpUseEquityFilter;
   settings.eqEmaAlpha         = InpEqEMA_Alpha;
   settings.eqUnderwaterPct    = InpEqUnderwaterPct;
   settings.eqBoostAdxDelta    = InpEqBoostAdxDelta;
   settings.useFixedLots       = InpUseFixedLots;
   settings.fixedLots          = InpFixedLots;
   settings.riskPerTradePct    = InpRiskPerTradePct;
   settings.maxOpenPositions   = InpMaxOpenPositions;
   settings.dailyLossStopPct   = InpDailyLossStopPct;
   settings.maxDrawdownPct     = InpMaxDrawdownPct;
   settings.maxSpreadPoints    = InpMaxSpreadPoints;
   settings.minStopBufferAtr   = InpMinStopBufferAtr;
   settings.magic              = InpMagic;
   settings.debug              = InpDebug;
}

void ApplyPreset(const InpPreset preset)
{
   ApplyPresetDefaults(gConfig,preset);
   if(preset==PRESET_CUSTOM)
      LoadInputsIntoConfig(gConfig);
}

int FindMemoIndex(const ulong ticket)
{
   for(int i=0;i<ArraySize(positionMemos);++i)
   {
      if(positionMemos[i].ticket==ticket)
         return i;
   }
   return -1;
}

void UpsertMemo(const ulong ticket,const double riskPts,const double atrPts,const datetime openTime,const bool isAddon,
                const double openPrice,const int direction,const double volume,const double riskPerLot)
{
   int idx=FindMemoIndex(ticket);
   if(idx<0)
   {
      int newSize=ArraySize(positionMemos)+1;
      ArrayResize(positionMemos,newSize);
      idx=newSize-1;
   }
   positionMemos[idx].ticket            = ticket;
   positionMemos[idx].initialRiskPoints = riskPts;
   positionMemos[idx].entryAtrPoints    = atrPts;
   positionMemos[idx].openTime          = openTime;
   positionMemos[idx].isAddon           = isAddon;
   positionMemos[idx].openPrice         = openPrice;
   positionMemos[idx].direction         = direction;
   positionMemos[idx].bestFavourablePts = 0.0;
   positionMemos[idx].worstAdversePts   = 0.0;
    positionMemos[idx].initialVolume     = volume;
    positionMemos[idx].riskPerLot        = riskPerLot;
    positionMemos[idx].runnerMode        = false;
    positionMemos[idx].lastKnownVolume   = volume;
}

void RemoveMemo(const ulong ticket)
{
   int idx=FindMemoIndex(ticket);
   if(idx<0)
      return;
   int lastIndex=ArraySize(positionMemos)-1;
   if(idx!=lastIndex && lastIndex>=0)
      positionMemos[idx]=positionMemos[lastIndex];
   ArrayResize(positionMemos,MathMax(0,lastIndex));
}

void RecordCompletedTrade(const PositionMemo &memo,const double profitPts)
{
   int newSize=ArraySize(completedTrades)+1;
   ArrayResize(completedTrades,newSize);
   int idx=newSize-1;
   completedTrades[idx].profitPts      = profitPts;
   completedTrades[idx].mfePts         = memo.bestFavourablePts;
   completedTrades[idx].maePts         = memo.worstAdversePts;
   completedTrades[idx].initialRiskPts = memo.initialRiskPoints;
}

void UpdateMemoExcursions(const int memoIndex,const double progressPts)
{
   if(memoIndex<0 || memoIndex>=ArraySize(positionMemos))
      return;
   if(progressPts>positionMemos[memoIndex].bestFavourablePts)
      positionMemos[memoIndex].bestFavourablePts=progressPts;
   double adverse = (progressPts<0.0 ? -progressPts : 0.0);
   if(adverse>positionMemos[memoIndex].worstAdversePts)
      positionMemos[memoIndex].worstAdversePts=adverse;
}

#endif // __EA_GLOBALS_MQH__
