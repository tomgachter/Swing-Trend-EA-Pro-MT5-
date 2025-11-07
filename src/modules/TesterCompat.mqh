#pragma once

#ifdef __MQL5__
// On MetaTrader 5 the ENUM_STATISTICS type and associated constants are
// provided by the platform. Import the official definitions so the EA relies
// on the same source of truth and avoids conflicting redeclarations.
#include <Testing/Tester.mqh>
#endif

// Some build environments (for example when running static analysis tools or
// when using lightweight MetaTrader installations) might not ship the tester
// header.  Guard the fallback enumeration so that we only provide it when the
// platform has not already defined the constants.
#ifndef STAT_PROFIT_FACTOR

// Fallback definitions for ENUM_STATISTICS constants normally provided by
// <Testing/Tester.mqh>. These values mirror the order documented in the
// MQL5 reference so that TesterStatistics() continues to return the same
// metrics even when the platform header is unavailable.
enum ENUM_STATISTICS
{
   STAT_INITIAL_DEPOSIT        = 0,
   STAT_WITHDRAWAL             = 1,
   STAT_PROFIT                 = 2,
   STAT_GROSS_PROFIT           = 3,
   STAT_GROSS_LOSS             = 4,
   STAT_MAX_PROFITTRADE        = 5,
   STAT_MAX_LOSSTRADE          = 6,
   STAT_CONPROFITMAX           = 7,
   STAT_CONPROFITMAX_TRADES    = 8,
   STAT_MAX_CONWINS            = 9,
   STAT_MAX_CONPROFIT_TRADES   = 10,
   STAT_CONLOSSMAX             = 11,
   STAT_CONLOSSMAX_TRADES      = 12,
   STAT_MAX_CONLOSSES          = 13,
   STAT_MAX_CONLOSS_TRADES     = 14,
   STAT_BALANCEMIN             = 15,
   STAT_BALANCE_DD             = 16,
   STAT_BALANCEDD_PERCENT      = 17,
   STAT_BALANCE_DDREL_PERCENT  = 18,
   STAT_BALANCE_DD_RELATIVE    = 19,
   STAT_EQUITYMIN              = 20,
   STAT_EQUITY_DD              = 21,
   STAT_EQUITYDD_PERCENT       = 22,
   STAT_EQUITY_DDREL_PERCENT   = 23,
   STAT_EQUITY_DD_RELATIVE     = 24,
   STAT_EXPECTED_PAYOFF        = 25,
   STAT_PROFIT_FACTOR          = 26,
   STAT_RECOVERY_FACTOR        = 27,
   STAT_SHARPE_RATIO           = 28,
   STAT_MIN_MARGINLEVEL        = 29,
   STAT_CUSTOM_ONTESTER        = 30,
   STAT_DEALS                  = 31,
   STAT_TRADES                 = 32,
   STAT_PROFIT_TRADES          = 33,
   STAT_LOSS_TRADES            = 34,
   STAT_SHORT_TRADES           = 35,
   STAT_LONG_TRADES            = 36,
   STAT_PROFIT_SHORTTRADES     = 37,
   STAT_PROFIT_LONGTRADES      = 38,
   STAT_PROFITTRADES_AVGCON    = 39,
   STAT_LOSSTRADES_AVGCON      = 40,
   STAT_COMPLEX_CRITERION      = 41,
   STAT_MODELLING_QUALITY      = 42
};

#endif  // STAT_PROFIT_FACTOR
