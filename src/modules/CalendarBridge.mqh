#ifndef __CALENDAR_BRIDGE_MQH__
#define __CALENDAR_BRIDGE_MQH__

//+------------------------------------------------------------------+
//| Calendar bridge                                                  |
//|                                                                  |
//| Some stripped down MetaTrader environments that are used for     |
//| offline linting/CI builds ship without the built-in              |
//| <Calendar/Calendar.mqh> header.  The Expert Advisor only needs   |
//| the header for type declarations, so compilation can proceed     |
//| without it.                                                      |
//|                                                                  |
//| Define EA_USE_NATIVE_CALENDAR before including this header when  |
//| building on a full MetaTrader terminal to enable the native      |
//| economic calendar filter.                                        |
//+------------------------------------------------------------------+

#ifdef EA_USE_NATIVE_CALENDAR
   #include <Calendar/Calendar.mqh>
   #define EA_CALENDAR_SUPPORTED 1
#else
   #define EA_CALENDAR_SUPPORTED 0
#endif

#endif // __CALENDAR_BRIDGE_MQH__
