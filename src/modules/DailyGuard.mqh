#ifndef __DAILY_GUARD_MQH__
#define __DAILY_GUARD_MQH__

class DailyGuard
{
private:
   double   m_maxDailyRiskPercent;
   double   m_realizedLossPercent;
   double   m_openRiskPercent;
   double   m_riskReductionFactor;
   int      m_consecutiveLosses;
   datetime m_currentDay;
   double   m_dayBalanceAnchor;
   int      m_dayStartHour;
   int      m_daySerial;
   string   m_gvKey;
   double   m_dayEquityAnchor;
   double   m_dayWorstEquity;
   datetime m_lastHeartbeat;

public:
   DailyGuard(): m_maxDailyRiskPercent(6.0), m_realizedLossPercent(0.0), m_openRiskPercent(0.0),
                 m_riskReductionFactor(1.0), m_consecutiveLosses(0), m_currentDay(0),
                 m_dayBalanceAnchor(0.0), m_dayStartHour(0), m_daySerial(0), m_gvKey(""),
                 m_dayEquityAnchor(0.0), m_dayWorstEquity(0.0), m_lastHeartbeat(0)
   {
   }

   void Configure(const double maxDailyRisk,const int dayStartHour,const string persistKey)
   {
      m_maxDailyRiskPercent = maxDailyRisk;
      m_dayStartHour = dayStartHour;
      if(m_dayStartHour<-23)
         m_dayStartHour = -23;
      else if(m_dayStartHour>23)
         m_dayStartHour = 23;
      m_gvKey = persistKey;
      if(m_gvKey!="")
      {
         string serialKey = m_gvKey+"_SERIAL";
         string anchorKey = m_gvKey+"_ANCHOR";
         if(GlobalVariableCheck(serialKey))
            m_daySerial = (int)GlobalVariableGet(serialKey);
         if(GlobalVariableCheck(anchorKey))
         {
            m_dayEquityAnchor = GlobalVariableGet(anchorKey);
            m_dayBalanceAnchor = MathMax(m_dayEquityAnchor,1.0);
            m_dayWorstEquity = m_dayEquityAnchor;
         }
      }
   }

   int DaySerial(const datetime now) const
   {
      int offsetSeconds = m_dayStartHour*60*60;
      datetime adjusted = now - (datetime)offsetSeconds;
      MqlDateTime t;
      TimeToStruct(adjusted,t);
      return t.year*10000 + t.mon*100 + t.day;
   }

   void Reset(const datetime now,const double equity)
   {
      m_currentDay = now;
      m_daySerial = DaySerial(now);
      double safeAnchor = MathMax(equity,1.0);
      m_dayEquityAnchor = safeAnchor;
      m_dayWorstEquity = equity;
      m_dayBalanceAnchor = safeAnchor;
      m_realizedLossPercent = 0.0;
      m_openRiskPercent = 0.0;
      m_riskReductionFactor = 1.0;
      m_consecutiveLosses = 0;
      m_lastHeartbeat = now;
      if(m_gvKey!="")
      {
         GlobalVariableSet(m_gvKey+"_SERIAL",(double)m_daySerial);
         GlobalVariableSet(m_gvKey+"_ANCHOR",m_dayEquityAnchor);
      }
   }

   void Heartbeat(const datetime now,const double equity)
   {
      int serial = DaySerial(now);
      if(serial!=m_daySerial || m_dayEquityAnchor<=0.0)
      {
         Reset(now,equity);
         return;
      }
      m_currentDay = now;
      m_lastHeartbeat = now;
      if(equity>0.0)
      {
         if(m_dayWorstEquity<=0.0)
            m_dayWorstEquity = equity;
         else
            m_dayWorstEquity = MathMin(m_dayWorstEquity,equity);
      }
   }

   void RegisterOpenRisk(const double riskPercent)
   {
      m_openRiskPercent += riskPercent;
   }

   void RemoveOpenRisk(const double riskPercent)
   {
      m_openRiskPercent = MathMax(0.0,m_openRiskPercent-riskPercent);
   }

   void RegisterResult(const double profit,const double balance)
   {
      if(m_dayBalanceAnchor<=0.0)
         m_dayBalanceAnchor = balance;
      double deltaPercent = 0.0;
      if(m_dayBalanceAnchor>0.0)
         deltaPercent = (profit/m_dayBalanceAnchor)*100.0;
      if(profit<0.0)
      {
         m_realizedLossPercent += MathAbs(deltaPercent);
         m_consecutiveLosses++;
         if(m_consecutiveLosses>=2)
            m_riskReductionFactor = 0.75;
      }
      else if(profit>0.0)
      {
         m_consecutiveLosses = 0;
         m_riskReductionFactor = 1.0;
      }
   }

   double EquityLossPercent(const double equity) const
   {
      if(m_dayEquityAnchor<=0.0 || equity<=0.0)
         return 0.0;
      return 100.0*(m_dayEquityAnchor-equity)/MathMax(1.0,m_dayEquityAnchor);
   }

   bool ShouldFlatten(const double equity) const
   {
      double dayLoss = EquityLossPercent(equity);
      if(dayLoss>=m_maxDailyRiskPercent)
         return true;
      return (m_realizedLossPercent + m_openRiskPercent) >= m_maxDailyRiskPercent;
   }

   bool AllowNewTrade(const double upcomingRiskPercent,const double equityNow)
   {
      double dayLoss = EquityLossPercent(equityNow);
      if(dayLoss + upcomingRiskPercent > m_maxDailyRiskPercent)
         return false;
      double totalRisk = m_realizedLossPercent + m_openRiskPercent + upcomingRiskPercent;
      return (totalRisk <= m_maxDailyRiskPercent);
   }

   double RiskReductionFactor() { return m_riskReductionFactor; }
   datetime CurrentDay() { return m_currentDay; }
};

#endif // __DAILY_GUARD_MQH__
