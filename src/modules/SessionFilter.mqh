#ifndef __SESSION_FILTER_MQH__
#define __SESSION_FILTER_MQH__

enum SessionWindow
{
   SESSION_NONE = 0,
   SESSION_EDGE = 1,
   SESSION_CORE = 2
};

class SessionFilter
{
private:
   int      m_startMinutes;
   int      m_endMinutes;
   int      m_coreStart;
   int      m_coreEnd;
   bool     m_debugMode;
   bool     m_allowDebugOverride;

   int ClampMinutes(const int minutes)
   {
      int clamped = minutes;
      clamped = MathMax(0,clamped);
      clamped = MathMin(23*60+59,clamped);
      return clamped;
   }

public:
   SessionFilter(): m_debugMode(false), m_allowDebugOverride(false)
   {
      Configure(7,0,14,45);
   }

   void Configure(const int startHour,const int startMinute,const int endHour,const int endMinute)
   {
      int start = ClampMinutes(startHour*60 + startMinute);
      int end   = ClampMinutes(endHour*60 + endMinute);
      if(end<start)
         end = start;
      m_startMinutes = start;
      m_endMinutes   = end;

      int coreStart = start + 60; // default one hour after session open
      int coreEnd   = end - 180;  // default three hours before session close
      if(coreEnd<coreStart)
      {
         int mid = (start + end)/2;
         coreStart = MathMax(start,mid-60);
         coreEnd   = MathMin(end,mid+60);
      }
      m_coreStart = ClampMinutes(coreStart);
      m_coreEnd   = ClampMinutes(coreEnd);
   }

   void SetDebugMode(const bool debug,const bool allowOverride=false)
   {
      m_debugMode = debug;
      m_allowDebugOverride = allowOverride;
   }

   bool AllowsEntry(const datetime time, SessionWindow &window)
   {
      MqlDateTime dt;
      TimeToStruct(time,dt);
      if(dt.day_of_week==0 || dt.day_of_week==6)
      {
         window = SESSION_NONE;
         if(m_debugMode && m_allowDebugOverride)
         {
            PrintFormat("SESSION DEBUG: %s outside trading days (weekend) -> override due to debug",
                        TimeToString(time,TIME_DATE|TIME_MINUTES));
            window = SESSION_EDGE;
            return true;
         }
         return false;
      }
      int minutes = dt.hour*60 + dt.min;
      if(minutes < m_startMinutes || minutes > m_endMinutes)
      {
         window = SESSION_NONE;
         if(m_debugMode && m_allowDebugOverride)
         {
            PrintFormat("SESSION DEBUG: %s outside window %02d:%02d-%02d:%02d (minutes=%d) -> override due to debug",
                        TimeToString(time,TIME_DATE|TIME_MINUTES),
                        m_startMinutes/60,m_startMinutes%60,m_endMinutes/60,m_endMinutes%60,minutes);
            window = SESSION_EDGE;
            return true;
         }
         return false;
      }
      if(minutes >= m_coreStart && minutes <= m_coreEnd)
         window = SESSION_CORE;
      else
         window = SESSION_EDGE;
      if(m_debugMode)
      {
         PrintFormat("SESSION DEBUG: %s allowed (window=%s override=%s)",
                     TimeToString(time,TIME_DATE|TIME_MINUTES),
                     window==SESSION_CORE?"CORE":"EDGE",
                     (m_debugMode && m_allowDebugOverride)?"true":"false");
      }
      return true;
   }

   bool IsLateSession(const datetime time)
   {
      SessionWindow window;
      if(!AllowsEntry(time,window))
      {
         MqlDateTime dt;
         TimeToStruct(time,dt);
         if(dt.day_of_week==0 || dt.day_of_week==6)
            return true;
         int minutes = dt.hour*60 + dt.min;
         return (minutes > m_endMinutes);
      }
      return false;
   }
};

#endif // __SESSION_FILTER_MQH__
