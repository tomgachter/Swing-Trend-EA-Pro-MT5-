#ifndef __EA_CALENDAR_COMPAT_MQH__
#define __EA_CALENDAR_COMPAT_MQH__

//+------------------------------------------------------------------+
//| Calendar compatibility layer                                      |
//|                                                                   |
//| Some reduced build environments used for linting or automated     |
//| testing do not provide the MetaTrader economic calendar header.   |
//| The Expert Advisor only relies on a very small subset of the API  |
//| to run its optional news filter.  The definitions below emulate   |
//| those pieces so the codebase can still be compiled.  Whenever the |
//| native header is available simply define EA_USE_NATIVE_CALENDAR   |
//| before including this file and the real implementation will be    |
//| pulled in instead.                                                |
//+------------------------------------------------------------------+
#ifdef EA_USE_NATIVE_CALENDAR
   #include <Calendar.mqh>
#else

// Minimal importance enumeration used by the inputs/configuration.
enum ENUM_CALENDAR_EVENT_IMPORTANCE
{
   CALENDAR_IMPORTANCE_NONE   = 0,
   CALENDAR_IMPORTANCE_LOW    = 1,
   CALENDAR_IMPORTANCE_MEDIUM = 2,
   CALENDAR_IMPORTANCE_HIGH   = 3
};

// Flags consumed by the Expert Advisor when vetting events.
#ifndef CALENDAR_FLAG_FORECAST
   #define CALENDAR_FLAG_FORECAST  (1<<0)
#endif
#ifndef CALENDAR_FLAG_REVISED
   #define CALENDAR_FLAG_REVISED   (1<<1)
#endif

// Simplified event descriptor mirroring the fields we read.
struct MqlCalendarValue
{
   datetime time;
   ENUM_CALENDAR_EVENT_IMPORTANCE impact;
   ulong flags;
};

// Calendar accessors gracefully degrade by reporting an unavailable
// calendar feed.  The Expert Advisor interprets this as "news filter
// cannot run" and therefore does not block trading sessions.
bool CalendarIsEnabled(void)
{
   return false;
}

int CalendarValueHistory(MqlCalendarValue &values[],const datetime from,const datetime to)
{
   ArrayResize(values,0);
   return 0;
}

#endif // !EA_USE_NATIVE_CALENDAR

#endif // __EA_CALENDAR_COMPAT_MQH__
