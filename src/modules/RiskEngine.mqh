#ifndef __RISK_ENGINE_MQH__
#define __RISK_ENGINE_MQH__

#include "DailyGuard.mqh"
#include "Sizer.mqh"

class RiskEngine
{
private:
   DailyGuard  m_dailyGuard;
   double      m_maxEquityDDPercent;
   double      m_equityPeak;
   RiskMode    m_riskMode;
   double      m_riskSetting;

public:
   RiskEngine(): m_maxEquityDDPercent(12.0), m_equityPeak(0.0), m_riskMode(RISK_PERCENT_PER_TRADE), m_riskSetting(0.5)
   {
   }

   void Configure(const RiskMode mode,const double riskSetting,const double maxDailyRisk,const double maxEquityDD)
   {
      m_riskMode = mode;
      m_riskSetting = riskSetting;
      m_dailyGuard.Configure(maxDailyRisk);
      m_maxEquityDDPercent = maxEquityDD;
      m_equityPeak = AccountInfoDouble(ACCOUNT_EQUITY);
      datetime today = iTime(_Symbol,PERIOD_D1,0);
      m_dailyGuard.Reset(today,AccountInfoDouble(ACCOUNT_BALANCE));
   }

   void OnNewDay()
   {
      datetime today = iTime(_Symbol,PERIOD_D1,0);
      if(today!=m_dailyGuard.CurrentDay())
      {
         m_dailyGuard.Reset(today,AccountInfoDouble(ACCOUNT_BALANCE));
      }
   }

   bool EquityKillSwitchTriggered()
   {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(equity>m_equityPeak)
         m_equityPeak = equity;
      if(m_equityPeak<=0.0)
         return false;
      double ddPercent = (m_equityPeak-equity)/m_equityPeak*100.0;
      return (ddPercent >= m_maxEquityDDPercent);
   }

   bool AllowNewTrade(const double stopPoints,PositionSizer &sizer,double &volume,double &riskPercent)
   {
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double riskAdjust = m_dailyGuard.RiskReductionFactor();
      double lot = sizer.CalculateVolume(m_riskMode,m_riskSetting,stopPoints,balance,riskAdjust);
      SymbolContext ctx = sizer.Context();
      if(lot<ctx.minLot)
         return false;

      if(m_riskMode==RISK_FIXED_LOTS)
      {
         double perLotLoss = stopPoints * sizer.PipValuePerLot();
         riskPercent = (lot * perLotLoss)/balance*100.0;
      }
      else
      {
         riskPercent = m_riskSetting*riskAdjust;
      }

      if(!m_dailyGuard.AllowNewTrade(riskPercent))
         return false;

      volume = lot;
      return true;
   }

   void OnTradeOpened(const double riskPercent)
   {
      if(riskPercent>0.0)
         m_dailyGuard.RegisterOpenRisk(riskPercent);
   }

   void OnTradeClosed(const double profit,const double riskPercent)
   {
      if(riskPercent>0.0)
         m_dailyGuard.RemoveOpenRisk(riskPercent);
      m_dailyGuard.RegisterResult(profit,AccountInfoDouble(ACCOUNT_BALANCE));
   }

   RiskMode Mode() { return m_riskMode; }
   double RiskSetting() { return m_riskSetting; }
};

#endif // __RISK_ENGINE_MQH__
