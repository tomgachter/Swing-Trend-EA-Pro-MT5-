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
//| native header is available this file simply includes it.  If the  |
//| header is missing define EA_FORCE_STUB_CALENDAR before including  |
//| this file to activate the lightweight compatibility layer.        |
//+------------------------------------------------------------------+
#ifdef EA_FORCE_STUB_CALENDAR

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

#else
   // Use the built-in calendar support.  Include the native header so the
   // flag constants are available when building under the official MetaTrader
   // toolchain.  Some stripped-down build environments do not ship the header
   // but they can opt into the stub above by defining EA_FORCE_STUB_CALENDAR
   // before including this file.
   #include <Calendar.mqh>

   // A few brokers ship terminals that omit the optional flag constants even
   // when the calendar API itself is present.  The Expert Advisor only relies
   // on the two bits defined below, therefore we provide lightweight fallbacks
   // if the native header left them undefined.
   #ifndef CALENDAR_FLAG_FORECAST
      #define CALENDAR_FLAG_FORECAST (1<<0)
   #endif
   #ifndef CALENDAR_FLAG_REVISED
      #define CALENDAR_FLAG_REVISED  (1<<1)
   #endif
#endif // !EA_FORCE_STUB_CALENDAR

#endif // __EA_CALENDAR_COMPAT_MQH__
