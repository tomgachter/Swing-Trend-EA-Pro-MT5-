//+------------------------------------------------------------------+
//| TesterCompat.mqh                                                 |
//| Compatibility helpers for tester statistics in constrained       |
//| environments.                                                    |
//+------------------------------------------------------------------+
#ifndef TESTERCOMPAT_MQH
#define TESTERCOMPAT_MQH

// Some build environments (for example static analysis harnesses) do not ship
// the MetaTrader tester headers.  Provide lightweight fallback definitions for
// the tester statistics identifiers so that the Expert Advisor can be parsed
// and tested without the official include files.

#ifndef STAT_INITIAL_DEPOSIT
   #define STAT_INITIAL_DEPOSIT        0
#endif
#ifndef STAT_WITHDRAWAL
   #define STAT_WITHDRAWAL             1
#endif
#ifndef STAT_PROFIT
   #define STAT_PROFIT                 2
#endif
#ifndef STAT_GROSS_PROFIT
   #define STAT_GROSS_PROFIT           3
#endif
#ifndef STAT_GROSS_LOSS
   #define STAT_GROSS_LOSS             4
#endif
#ifndef STAT_MAX_PROFITTRADE
   #define STAT_MAX_PROFITTRADE        5
#endif
#ifndef STAT_MAX_LOSSTRADE
   #define STAT_MAX_LOSSTRADE          6
#endif
#ifndef STAT_CONPROFITMAX
   #define STAT_CONPROFITMAX           7
#endif
#ifndef STAT_CONPROFITMAX_TRADES
   #define STAT_CONPROFITMAX_TRADES    8
#endif
#ifndef STAT_MAX_CONWINS
   #define STAT_MAX_CONWINS            9
#endif
#ifndef STAT_MAX_CONPROFIT_TRADES
   #define STAT_MAX_CONPROFIT_TRADES   10
#endif
#ifndef STAT_CONLOSSMAX
   #define STAT_CONLOSSMAX             11
#endif
#ifndef STAT_CONLOSSMAX_TRADES
   #define STAT_CONLOSSMAX_TRADES      12
#endif
#ifndef STAT_MAX_CONLOSSES
   #define STAT_MAX_CONLOSSES          13
#endif
#ifndef STAT_MAX_CONLOSS_TRADES
   #define STAT_MAX_CONLOSS_TRADES     14
#endif
#ifndef STAT_BALANCEMIN
   #define STAT_BALANCEMIN             15
#endif
#ifndef STAT_BALANCE_DD
   #define STAT_BALANCE_DD             16
#endif
#ifndef STAT_BALANCEDD_PERCENT
   #define STAT_BALANCEDD_PERCENT      17
#endif
#ifndef STAT_BALANCE_DDREL_PERCENT
   #define STAT_BALANCE_DDREL_PERCENT  18
#endif
#ifndef STAT_BALANCE_DD_RELATIVE
   #define STAT_BALANCE_DD_RELATIVE    19
#endif
#ifndef STAT_EQUITYMIN
   #define STAT_EQUITYMIN              20
#endif
#ifndef STAT_EQUITY_DD
   #define STAT_EQUITY_DD              21
#endif
#ifndef STAT_EQUITYDD_PERCENT
   #define STAT_EQUITYDD_PERCENT       22
#endif
#ifndef STAT_EQUITY_DDREL_PERCENT
   #define STAT_EQUITY_DDREL_PERCENT   23
#endif
#ifndef STAT_EQUITY_DD_RELATIVE
   #define STAT_EQUITY_DD_RELATIVE     24
#endif
#ifndef STAT_EQUITY_DDRELATIVE
   #define STAT_EQUITY_DDRELATIVE      STAT_EQUITY_DD_RELATIVE
#endif
#ifndef STAT_EXPECTED_PAYOFF
   #define STAT_EXPECTED_PAYOFF        25
#endif
#ifndef STAT_PROFIT_FACTOR
   #define STAT_PROFIT_FACTOR          26
#endif
#ifndef STAT_RECOVERY_FACTOR
   #define STAT_RECOVERY_FACTOR        27
#endif
#ifndef STAT_SHARPE_RATIO
   #define STAT_SHARPE_RATIO           28
#endif
#ifndef STAT_MIN_MARGINLEVEL
   #define STAT_MIN_MARGINLEVEL        29
#endif
#ifndef STAT_CUSTOM_ONTESTER
   #define STAT_CUSTOM_ONTESTER        30
#endif
#ifndef STAT_DEALS
   #define STAT_DEALS                  31
#endif
#ifndef STAT_TRADES
   #define STAT_TRADES                 32
#endif
#ifndef STAT_PROFIT_TRADES
   #define STAT_PROFIT_TRADES          33
#endif
#ifndef STAT_LOSS_TRADES
   #define STAT_LOSS_TRADES            34
#endif
#ifndef STAT_SHORT_TRADES
   #define STAT_SHORT_TRADES           35
#endif
#ifndef STAT_LONG_TRADES
   #define STAT_LONG_TRADES            36
#endif
#ifndef STAT_PROFIT_SHORTTRADES
   #define STAT_PROFIT_SHORTTRADES     37
#endif
#ifndef STAT_PROFIT_LONGTRADES
   #define STAT_PROFIT_LONGTRADES      38
#endif
#ifndef STAT_PROFITTRADES_AVGCON
   #define STAT_PROFITTRADES_AVGCON    39
#endif
#ifndef STAT_LOSSTRADES_AVGCON
   #define STAT_LOSSTRADES_AVGCON      40
#endif
#ifndef STAT_COMPLEX_CRITERION
   #define STAT_COMPLEX_CRITERION      41
#endif
#ifndef STAT_MODELLING_QUALITY
   #define STAT_MODELLING_QUALITY      42
#endif
#ifndef STAT_START_TRADE_TIME
   #define STAT_START_TRADE_TIME       43
#endif
#ifndef STAT_LAST_TRADE_TIME
   #define STAT_LAST_TRADE_TIME        44
#endif
#ifndef STAT_AVG_HOLD_TIME
   #define STAT_AVG_HOLD_TIME          45
#endif
#ifndef STAT_LINEAR_CORRELATION_EQUITY
   #define STAT_LINEAR_CORRELATION_EQUITY 46
#endif

#endif  // TESTERCOMPAT_MQH
