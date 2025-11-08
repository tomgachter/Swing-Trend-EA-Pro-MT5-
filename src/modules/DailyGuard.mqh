#pragma once

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

public:
   DailyGuard(): m_maxDailyRiskPercent(6.0), m_realizedLossPercent(0.0), m_openRiskPercent(0.0),
                 m_riskReductionFactor(1.0), m_consecutiveLosses(0), m_currentDay(0), m_dayBalanceAnchor(0.0)
   {
   }

   void Configure(const double maxDailyRisk)
   {
      m_maxDailyRiskPercent = maxDailyRisk;
   }

   void Reset(const datetime day,const double balance)
   {
      m_currentDay = day;
      m_dayBalanceAnchor = balance;
      m_realizedLossPercent = 0.0;
      m_openRiskPercent = 0.0;
      m_riskReductionFactor = 1.0;
      m_consecutiveLosses = 0;
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

   bool AllowNewTrade(const double upcomingRiskPercent) const
   {
      double totalRisk = m_realizedLossPercent + m_openRiskPercent + upcomingRiskPercent;
      return (totalRisk <= m_maxDailyRiskPercent);
   }

   double RiskReductionFactor() const { return m_riskReductionFactor; }
   datetime CurrentDay() const { return m_currentDay; }
};
