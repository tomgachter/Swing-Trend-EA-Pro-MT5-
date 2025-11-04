#pragma once

#include <Trade/Trade.mqh>

#ifdef EA_GLOBALS_IMPLEMENTATION
   #define EA_INPUT(type,name,value) input type name = value;
   #define EA_VAR(type,name,value)   type name = value;
#else
   #define EA_INPUT(type,name,value) extern type name;
   #define EA_VAR(type,name,value)   extern type name;
#endif

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
EA_INPUT(string,            InpSymbol,             "XAUUSD")      // Trading symbol

//--- Timeframes
EA_INPUT(ENUM_TIMEFRAMES,   InpTF_Entry,           PERIOD_H1)      // Entry timeframe
EA_INPUT(ENUM_TIMEFRAMES,   InpTF_TrailATR,        PERIOD_H4)      // ATR timeframe for stops and trailing
EA_INPUT(ENUM_TIMEFRAMES,   InpTF_Trend1,          PERIOD_H4)      // Trend vote 1 timeframe
EA_INPUT(ENUM_TIMEFRAMES,   InpTF_Trend2,          PERIOD_D1)      // Trend vote 2 timeframe
EA_INPUT(ENUM_TIMEFRAMES,   InpTF_Trend3,          PERIOD_W1)      // Trend vote 3 timeframe

//--- Trend filters
EA_INPUT(int,               InpEMA_Entry_Period,   20)             // Entry EMA period
EA_INPUT(int,               InpEMA_Trend1_Period,  34)             // H4 trend EMA period
EA_INPUT(int,               InpEMA_Trend2_Period,  34)             // D1 trend EMA period
EA_INPUT(int,               InpEMA_Trend3_Period,  50)             // W1 trend EMA period
EA_INPUT(int,               InpTrendVotesRequired, 2)              // Votes required for bias
EA_INPUT(bool,              InpUseClosedBarTrend,  true)           // Use closed bars for trend votes
EA_INPUT(bool,              InpUseSlopeFilter,     false)          // Optional EMA slope filter

//--- Entry mode
EA_INPUT(EntryMode,         InpEntryMode,          ENTRY_HYBRID)   // Entry execution mode

//--- Donchian breakout
EA_INPUT(int,               InpDonchianBars_Base,  12)             // Base Donchian channel length
EA_INPUT(double,            InpDonchianBars_MinMax,8.0)            // Min/max deviation from base
EA_INPUT(double,            InpBreakoutBufferPts,  6.0)            // Breakout buffer in points

//--- Regime controls
EA_INPUT(int,               InpATR_D1_Period,      14)             // ATR period for D1 regime
EA_INPUT(double,            InpATR_D1_MinPts,      4000.0)         // Minimum D1 ATR in points
EA_INPUT(double,            InpATR_D1_MaxPts,      45000.0)        // Maximum D1 ATR in points
EA_INPUT(double,            InpATR_D1_Pivot,       12000.0)        // Pivot D1 ATR for scaling
EA_INPUT(double,            InpRegimeMinFactor,    0.80)           // Minimum scaling factor
EA_INPUT(double,            InpRegimeMaxFactor,    1.40)           // Maximum scaling factor
EA_INPUT(int,               InpADX_Period,         14)             // ADX period (H4)
EA_INPUT(double,            InpMinADX_H4,          15.0)           // Minimum ADX threshold

//--- Stops and targets
EA_INPUT(int,               InpATR_Period,         14)             // ATR period for SL/TP (H4)
EA_INPUT(double,            InpATR_SL_mult_Base,   2.6)            // Base ATR multiple for SL
EA_INPUT(double,            InpATR_TP_mult_Base,   3.6)            // Base ATR multiple for TP

//--- Position management
EA_INPUT(int,               InpMinHoldBars,        6)              // Minimum bars before management
EA_INPUT(double,            InpBreakEven_ATR,      1.0)            // ATR to reach before BE move
EA_INPUT(double,            InpPartialClose_R,     2.0)            // R multiple to trigger partial close
EA_INPUT(double,            InpPartialClose_Pct,   50.0)           // Percentage closed at partial target

//--- Trailing options
EA_INPUT(TrailingMode,      InpTrailingMode,       TRAIL_ATR)      // Trailing mode
EA_INPUT(double,            InpATR_Trail_mult,     1.0)            // ATR multiple for trailing
EA_INPUT(int,               InpFractal_ShiftBars,  2)              // Fractal shift bars

//--- Anti-noise controls
EA_INPUT(int,               InpCooldownBars,       2)              // Bars between new entries
EA_INPUT(double,            InpMaxExtension_ATR,   1.6)            // Maximum distance from EMA in ATR

//--- Session filters
EA_INPUT(bool,              InpUseSessionBias,     false)          // Restrict entries to sessions
EA_INPUT(int,               InpSess1_StartHour,    7)              // Session 1 start (UTC)
EA_INPUT(int,               InpSess1_EndHour,      12)             // Session 1 end (UTC)
EA_INPUT(int,               InpSess2_StartHour,    13)             // Session 2 start (UTC)
EA_INPUT(int,               InpSess2_EndHour,      22)             // Session 2 end (UTC)
EA_INPUT(int,               InpTZ_OffsetHours,     0)              // Broker time offset vs UTC

//--- Pyramiding
EA_INPUT(bool,              InpUsePyramiding,      true)           // Enable add-on positions
EA_INPUT(int,               InpMaxAddonsPerBase,   2)              // Maximum add-ons per base trade
EA_INPUT(double,            InpAddonStep_ATR,      0.8)            // ATR distance per add-on
EA_INPUT(double,            InpAddonLotFactor,     0.6)            // Lot multiplier for add-ons

//--- Equity filter
EA_INPUT(bool,              InpUseEquityFilter,    true)           // Enable equity curve filter
EA_INPUT(double,            InpEqEMA_Alpha,        0.06)           // EMA alpha for equity filter
EA_INPUT(double,            InpEqUnderwaterPct,    1.0)            // Allowed equity drawdown vs EMA

//--- Position sizing and limits
EA_INPUT(bool,              InpUseFixedLots,       false)          // Use fixed lot size
EA_INPUT(double,            InpFixedLots,          0.50)           // Fixed lot size
EA_INPUT(double,            InpRiskPerTradePct,    0.80)           // Risk per trade (% of balance)
EA_INPUT(int,               InpMaxOpenPositions,   3)              // Maximum simultaneous positions

//--- Risk guards
EA_INPUT(double,            InpMaxDailyLossPct,    5.0)            // Daily loss guard (% of equity)
EA_INPUT(double,            InpMaxDrawdownPct,     10.0)           // Equity drawdown guard (%)
EA_INPUT(int,               InpMaxSpreadPoints,    600)            // Maximum allowed spread (points)

//--- Magic number and debug
EA_INPUT(int,               InpMagic,              11235813)       // Magic number for trades
EA_INPUT(bool,              InpDebug,              true)           // Enable debug logging

//+------------------------------------------------------------------+
//| State                                                            |
//+------------------------------------------------------------------+
EA_VAR(datetime,            lastBarTime,           0);
EA_VAR(datetime,            lastEntryBarTime,      0);
EA_VAR(bool,                didPartialClose,       false);
EA_VAR(double,              dayStartEquity,        0.0);
EA_VAR(double,              equityPeak,            0.0);
EA_VAR(int,                 daySerialAnchor,       -1);
EA_VAR(double,              eqEMA,                 0.0);
EA_VAR(double,              lastBaseOpenPrice,     0.0);
EA_VAR(double,              lastBaseLots,          0.0);
EA_VAR(int,                 addonsOpened,          0);
// Stores the most recent valid D1 ATR regime measurement for management fallbacks.
EA_VAR(double,              lastValidAtrD1Pts,     InpATR_D1_Pivot);

//+------------------------------------------------------------------+
//| Indicator handles                                                |
//+------------------------------------------------------------------+
EA_VAR(int,                 hATR_H4,               INVALID_HANDLE);
EA_VAR(int,                 hATR_D1,               INVALID_HANDLE);
EA_VAR(int,                 hATR_Entry,            INVALID_HANDLE);
EA_VAR(int,                 hEMA_E,                INVALID_HANDLE);
EA_VAR(int,                 hEMA_T1,               INVALID_HANDLE);
EA_VAR(int,                 hEMA_T2,               INVALID_HANDLE);
EA_VAR(int,                 hEMA_T3,               INVALID_HANDLE);
EA_VAR(int,                 hADX_H4,               INVALID_HANDLE);
EA_VAR(int,                 hFractals,             INVALID_HANDLE);

#ifdef EA_GLOBALS_IMPLEMENTATION
CTrade trade;
#else
extern CTrade trade;
#endif

#undef EA_INPUT
#undef EA_VAR
