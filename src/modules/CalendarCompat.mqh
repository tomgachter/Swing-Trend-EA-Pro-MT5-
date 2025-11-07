#ifndef __EA_CALENDAR_COMPAT_MQH__
#define __EA_CALENDAR_COMPAT_MQH__

//+------------------------------------------------------------------+
//| Calendar compatibility layer                                      |
//|                                                                   |
//| Some reduced build environments used for linting or automated     |
//| testing do not provide the MetaTrader economic calendar header.   |
//| The Expert Advisor can operate without the feed, therefore the    |
//| compatibility layer simply provides the bits of type information  |
//| referenced by the inputs so compilation succeeds everywhere.      |
//|                                                                   |
//| Define EA_USE_NATIVE_CALENDAR before including this file if you   |
//| want to rely on the official <Calendar.mqh> header.                |
//+------------------------------------------------------------------+

#ifdef EA_USE_NATIVE_CALENDAR
   #include <Calendar.mqh>
#endif

// Minimal importance enumeration used by the inputs/configuration.
#ifndef ENUM_CALENDAR_EVENT_IMPORTANCE
enum ENUM_CALENDAR_EVENT_IMPORTANCE
{
   CALENDAR_IMPORTANCE_NONE   = 0,
   CALENDAR_IMPORTANCE_LOW    = 1,
   CALENDAR_IMPORTANCE_MEDIUM = 2,
   CALENDAR_IMPORTANCE_HIGH   = 3
};
#endif

// Flags consumed by the Expert Advisor when vetting events.  If the
// native header is available these macros are already defined.
#ifndef CALENDAR_FLAG_FORECAST
   #define CALENDAR_FLAG_FORECAST  (1<<0)
#endif
#ifndef CALENDAR_FLAG_REVISED
   #define CALENDAR_FLAG_REVISED   (1<<1)
#endif

#endif // __EA_CALENDAR_COMPAT_MQH__
