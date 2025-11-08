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

public:
   SessionFilter(): m_startMinutes(7*60), m_endMinutes(14*60+45), m_coreStart(8*60), m_coreEnd(11*60+30)
   {
   }

   bool AllowsEntry(const datetime time, SessionWindow &window)
   {
      MqlDateTime dt;
      TimeToStruct(time,dt);
      if(dt.day_of_week==0 || dt.day_of_week==6)
      {
         window = SESSION_NONE;
         return false;
      }
      int minutes = dt.hour*60 + dt.min;
      if(minutes < m_startMinutes || minutes > m_endMinutes)
      {
         window = SESSION_NONE;
         return false;
      }
      if(minutes >= m_coreStart && minutes <= m_coreEnd)
         window = SESSION_CORE;
      else
         window = SESSION_EDGE;
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
