#ifndef __EA_TESTER_COMPAT_MQH__
#define __EA_TESTER_COMPAT_MQH__

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

#endif // __EA_TESTER_COMPAT_MQH__
