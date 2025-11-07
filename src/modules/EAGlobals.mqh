#ifndef __EA_GLOBALS_MQH__
#define __EA_GLOBALS_MQH__

#include <Trade/Trade.mqh>

enum EntryMode
{
   ENTRY_BREAKOUT = 0,
   ENTRY_PULLBACK = 1,
   ENTRY_HYBRID   = 2
};

enum TrailingMode
{
   TRAIL_OFF     = 0,
   TRAIL_ATR     = 1,
   TRAIL_FRACTAL = 2
};

//+------------------------------------------------------------------+
//| Input parameters                                                 |
//+------------------------------------------------------------------+
input string            InpSymbol             = "XAUUSD";      // Trading symbol

//--- Timeframes
input ENUM_TIMEFRAMES   InpTF_Entry           = PERIOD_H1;     // Entry timeframe
input ENUM_TIMEFRAMES   InpTF_TrailATR        = PERIOD_H4;     // ATR timeframe for stops and trailing
input ENUM_TIMEFRAMES   InpTF_Trend1          = PERIOD_H4;     // Trend vote 1 timeframe
input ENUM_TIMEFRAMES   InpTF_Trend2          = PERIOD_D1;     // Trend vote 2 timeframe
input ENUM_TIMEFRAMES   InpTF_Trend3          = PERIOD_W1;     // Trend vote 3 timeframe

//--- Trend filters
input int               InpEMA_Entry_Period   = 20;            // Entry EMA period
input int               InpEMA_Trend1_Period  = 34;            // H4 trend EMA period
input int               InpEMA_Trend2_Period  = 34;            // D1 trend EMA period
input int               InpEMA_Trend3_Period  = 50;            // W1 trend EMA period
input int               InpTrendVotesRequired = 2;             // Votes required for bias
input bool              InpUseClosedBarTrend  = true;          // Use closed bars for trend votes
input bool              InpUseSlopeFilter     = false;         // Optional EMA slope filter

//--- Entry mode
input EntryMode         InpEntryMode          = ENTRY_HYBRID;  // Entry execution mode

//--- Donchian breakout
input int               InpDonchianBars_Base  = 12;            // Base Donchian channel length
input double            InpDonchianBars_MinMax= 8.0;           // Min/max deviation from base
input double            InpBreakoutBufferPts  = 6.0;           // Breakout buffer in points

//--- Regime controls
input int               InpATR_D1_Period      = 14;            // ATR period for D1 regime
input double            InpATR_D1_MinPts      = 4000.0;        // Minimum D1 ATR in points
input double            InpATR_D1_MaxPts      = 45000.0;       // Maximum D1 ATR in points
input double            InpATR_D1_Pivot       = 12000.0;       // Pivot D1 ATR for scaling
input double            InpRegimeMinFactor    = 0.80;          // Minimum scaling factor
input double            InpRegimeMaxFactor    = 1.40;          // Maximum scaling factor
input int               InpADX_Period         = 14;            // ADX period (H4)
input double            InpMinADX_H4          = 15.0;          // Minimum ADX threshold

//--- Stops and targets
input int               InpATR_Period         = 14;            // ATR period for SL/TP (H4)
input double            InpATR_SL_mult_Base   = 2.6;           // Base ATR multiple for SL
input double            InpATR_TP_mult_Base   = 3.6;           // Base ATR multiple for TP

//--- Position management
input int               InpMinHoldBars        = 6;             // Minimum bars before management
input double            InpBreakEven_ATR      = 1.0;           // ATR to reach before BE move
input double            InpPartialClose_R     = 2.0;           // R multiple to trigger partial close
input double            InpPartialClose_Pct   = 50.0;          // Percentage closed at partial target

//--- Trailing options
input TrailingMode      InpTrailingMode       = TRAIL_ATR;     // Trailing mode
input double            InpATR_Trail_mult     = 1.0;           // ATR multiple for trailing
input int               InpFractal_ShiftBars  = 2;             // Fractal shift bars

//--- Anti-noise controls
input int               InpCooldownBars       = 2;             // Bars between new entries
input double            InpMaxExtension_ATR   = 1.6;           // Maximum distance from EMA in ATR

//--- Session filters
input bool              InpUseSessionBias     = false;         // Restrict entries to sessions
input int               InpSess1_StartHour    = 7;             // Session 1 start (UTC)
input int               InpSess1_EndHour      = 12;            // Session 1 end (UTC)
input int               InpSess2_StartHour    = 13;            // Session 2 start (UTC)
input int               InpSess2_EndHour      = 22;            // Session 2 end (UTC)
input int               InpTZ_OffsetHours     = 0;             // Broker time offset vs UTC

//--- Pyramiding
input bool              InpUsePyramiding      = true;          // Enable add-on positions
input int               InpMaxAddonsPerBase   = 2;             // Maximum add-ons per base trade
input double            InpAddonStep_ATR      = 0.8;           // ATR distance per add-on
input double            InpAddonLotFactor     = 0.6;           // Lot multiplier for add-ons

//--- Equity filter
input bool              InpUseEquityFilter    = true;          // Enable equity curve filter
input double            InpEqEMA_Alpha        = 0.06;          // EMA alpha for equity filter
input double            InpEqUnderwaterPct    = 1.0;           // Allowed equity drawdown vs EMA

//--- Position sizing and limits
input bool              InpUseFixedLots       = false;         // Use fixed lot size
input double            InpFixedLots          = 0.50;          // Fixed lot size
input double            InpRiskPerTradePct    = 0.80;          // Risk per trade (% of balance)
input int               InpMaxOpenPositions   = 3;             // Maximum simultaneous positions

//--- Risk guards
input double            InpMaxDailyLossPct    = 5.0;           // Daily loss guard (% of equity)
input double            InpMaxDrawdownPct     = 10.0;          // Equity drawdown guard (%)
input int               InpMaxSpreadPoints    = 600;           // Maximum allowed spread (points)

//--- Magic number and debug
input int               InpMagic              = 11235813;      // Magic number for trades
input bool              InpDebug              = true;          // Enable debug logging

//+------------------------------------------------------------------+
//| State                                                            |
//+------------------------------------------------------------------+
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

CTrade              trade;

#endif // __EA_GLOBALS_MQH__
