#ifndef __RISK_ENGINE_MQH__
#define __RISK_ENGINE_MQH__

#include "DailyGuard.mqh"
#include "Sizer.mqh"
#include "RegimeFilter.mqh"

class RiskEngine
{
private:
   DailyGuard  m_dailyGuard;
   double      m_maxEquityDDPercent;
   double      m_equityPeak;
   double      m_initialEquity;
   RiskMode    m_riskMode;
   double      m_riskSetting;
   bool        m_useDynamicRisk;
   double      m_lowFactor;
   double      m_normalFactor;
   double      m_highFactor;
   int         m_dayStartHour;
   string      m_persistKey;
   bool        m_useStaticOverallDD;
   double      m_slippageBudgetPts;
   bool        m_debugMode;
   bool        m_verboseMode;

public:
   RiskEngine(): m_maxEquityDDPercent(12.0), m_equityPeak(0.0), m_initialEquity(0.0),
                 m_riskMode(RISK_PERCENT_PER_TRADE), m_riskSetting(0.5),
                 m_useDynamicRisk(false), m_lowFactor(0.8), m_normalFactor(1.0), m_highFactor(1.2),
                 m_dayStartHour(0), m_persistKey(""), m_useStaticOverallDD(false), m_slippageBudgetPts(0.0),
                 m_debugMode(false), m_verboseMode(false)
   {
   }

   void Configure(const RiskMode mode,const double riskSetting,const double maxDailyRisk,const double maxEquityDD,
                  const int dayStartHour,const string persistKey,const bool staticOverallDD,const double slippageBudgetPts)
   {
      m_riskMode = mode;
      m_riskSetting = riskSetting;
      m_maxEquityDDPercent = maxEquityDD;
      m_dayStartHour = dayStartHour;
      m_persistKey = persistKey;
      m_useStaticOverallDD = staticOverallDD;
      m_slippageBudgetPts = MathMax(0.0,slippageBudgetPts);
      m_dailyGuard.Configure(maxDailyRisk,dayStartHour,persistKey);
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      m_equityPeak = equity;
      if(m_persistKey!="")
      {
         string initKey = m_persistKey+"_INIT";
         if(GlobalVariableCheck(initKey))
            m_initialEquity = GlobalVariableGet(initKey);
         if(m_initialEquity<=0.0)
            m_initialEquity = equity;
         GlobalVariableSet(initKey,m_initialEquity);
      }
      else
      {
         m_initialEquity = equity;
      }
      m_dailyGuard.Heartbeat(TimeCurrent(),equity);
   }

   void OnNewDay()
   {
      m_dailyGuard.Heartbeat(TimeCurrent(),AccountInfoDouble(ACCOUNT_EQUITY));
   }

   double RecomputeOpenRiskPercent(PositionSizer &sizer,const ulong magic)
   {
      double capital = m_dailyGuard.DayAnchorEquity();
      if(capital<=0.0)
         capital = AccountInfoDouble(ACCOUNT_EQUITY);
      if(capital<=0.0)
         capital = AccountInfoDouble(ACCOUNT_BALANCE);
      if(capital<=0.0)
         return 0.0;

      double point = SymbolInfoDouble(_Symbol,SYMBOL_POINT);
      if(point<=0.0)
         point = _Point;
      double perPoint = sizer.PipValuePerLot();

      double totalRiskAmt = 0.0;
      for(int i=PositionsTotal()-1; i>=0; --i)
      {
         ulong ticket = PositionGetTicket(i);
         if(!PositionSelectByTicket(ticket))
            continue;
         if(PositionGetString(POSITION_SYMBOL)!=_Symbol)
            continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC)!=magic)
            continue;

         double vol = PositionGetDouble(POSITION_VOLUME);
         double sl  = PositionGetDouble(POSITION_SL);
         if(vol<=0.0 || sl<=0.0)
            continue;

         double price = PositionGetDouble(POSITION_PRICE_CURRENT);
         double ptsToSL = MathAbs(price-sl)/MathMax(point,1e-9);
         totalRiskAmt += ptsToSL*perPoint*vol;
      }
      return (capital>0.0 ? 100.0*(totalRiskAmt/capital) : 0.0);
   }

   bool HasSufficientMargin(const int direction,const double volume,const double price) const
   {
      if(volume<=0.0)
         return false;

      ENUM_ORDER_TYPE type = (direction>0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
      double margin = 0.0;
      if(!OrderCalcMargin(type,_Symbol,volume,price,margin) || margin<=0.0)
      {
         if(m_debugMode || m_verboseMode)
            Print("MARGIN DEBUG: OrderCalcMargin failed or margin<=0");
         return (m_debugMode ? true : false);
      }

      double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      double minRatio = 1.1;
      bool ok = (freeMargin > margin * minRatio);
      if(m_debugMode || m_verboseMode)
      {
         double ratio = (margin>0.0 ? freeMargin/margin : 0.0);
         PrintFormat("MARGIN DEBUG: freeMargin=%.2f required=%.2f ratio=%.2f minRatio=%.2f ok=%s",
                     freeMargin,margin,ratio,minRatio,ok?"true":"false");
         if(!ok)
         {
            if(m_debugMode)
               Print("MARGIN DEBUG: insufficient margin but proceeding due to debug mode");
            else
               Print("MARGIN DEBUG: insufficient margin -> entry blocked");
         }
      }
      if(!ok)
         return m_debugMode;
      return true;
   }

   void RefreshOpenRisk(PositionSizer &sizer,const ulong magic)
   {
      double pct = RecomputeOpenRiskPercent(sizer,magic);
      m_dailyGuard.SetOpenRiskPercent(pct);
   }

   bool EquityKillSwitchTriggered()
   {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(m_useStaticOverallDD)
      {
         if(m_initialEquity<=0.0)
            return false;
         double ddStatic = 100.0*(m_initialEquity-equity)/MathMax(1.0,m_initialEquity);
         return (ddStatic >= m_maxEquityDDPercent);
      }
      if(equity>m_equityPeak)
         m_equityPeak = equity;
      if(m_equityPeak<=0.0)
         return false;
      double ddPercent = (m_equityPeak-equity)/MathMax(1.0,m_equityPeak)*100.0;
      return (ddPercent >= m_maxEquityDDPercent);
   }

   void SetDynamicRiskEnabled(const bool enabled)
   {
      m_useDynamicRisk = enabled;
   }

   void SetDebugMode(const bool debug)
   {
      m_debugMode = debug;
      m_dailyGuard.SetDebugMode(debug);
   }

   void SetVerboseMode(const bool verbose)
   {
      // Ergänzt reine Diagnose-Logs, ohne die Risk-Guards (anders als Debug) zu überstimmen.
      m_verboseMode = verbose;
      m_dailyGuard.SetVerboseMode(verbose);
   }

   bool AllowNewTrade(const double stopPoints,PositionSizer &sizer,RegimeFilter &regime,double &volume,double &riskPercent)
   {
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double riskAdjust = m_dailyGuard.RiskReductionFactor();
      double effectiveSetting = m_riskSetting;
      if(m_debugMode || m_verboseMode)
      {
         PrintFormat("RISK DEBUG: stopPoints=%.1f balance=%.2f riskSetting=%.2f riskAdjust=%.2f mode=%d",
                     stopPoints,balance,m_riskSetting,riskAdjust,(int)m_riskMode);
      }
      if(m_useDynamicRisk)
      {
         RegimeBucket bucket = regime.CurrentBucket();
         double factor = m_normalFactor;
         if(bucket==REGIME_HIGH)
            factor = m_highFactor;
         else if(bucket==REGIME_LOW)
            factor = m_lowFactor;
         effectiveSetting *= factor;
      }
      double lot = sizer.CalculateVolume(m_riskMode,effectiveSetting,stopPoints,balance,riskAdjust);
      SymbolContext ctx = sizer.Context();
      if(m_debugMode || m_verboseMode)
      {
         PrintFormat("RISK DEBUG: rawLot=%.4f minLot=%.4f maxLot=%.4f",
                     lot,ctx.minLot,ctx.maxLot);
      }
      if(lot<ctx.minLot)
      {
         if(m_debugMode)
         {
            PrintFormat("RISK DEBUG: lot %.4f < minLot %.4f -> clamping to minLot due to debug",lot,ctx.minLot);
            lot = ctx.minLot;
         }
         else
         {
            if(m_verboseMode)
               PrintFormat("RISK DEBUG: lot %.4f < minLot %.4f -> reject",lot,ctx.minLot);
            return false;
         }
      }
      if(lot>ctx.maxLot)
      {
         if(m_debugMode)
         {
            PrintFormat("RISK DEBUG: lot %.4f > maxLot %.4f -> clamping to maxLot due to debug",lot,ctx.maxLot);
            lot = ctx.maxLot;
         }
         else
         {
            if(m_verboseMode)
               PrintFormat("RISK DEBUG: lot %.4f > maxLot %.4f -> clamped",lot,ctx.maxLot);
            lot = ctx.maxLot;
         }
      }

      if(m_riskMode==RISK_FIXED_LOTS)
      {
         double perLotLoss = stopPoints * sizer.PipValuePerLot();
         riskPercent = (lot * perLotLoss)/balance*100.0;
      }
      else
      {
         riskPercent = effectiveSetting*riskAdjust;
      }

      if(m_debugMode || m_verboseMode)
      {
         PrintFormat("RISK DEBUG: riskPercent=%.2f%%",riskPercent);
      }

      double riskWcPercent = riskPercent;
      if(stopPoints>0.0 && m_slippageBudgetPts>0.0)
         riskWcPercent = riskPercent*(1.0 + (m_slippageBudgetPts/stopPoints));
      double equityNow = AccountInfoDouble(ACCOUNT_EQUITY);
      if(m_debugMode || m_verboseMode)
      {
         PrintFormat("RISK DEBUG: riskWcPercent=%.2f%% equity=%.2f dayLoss=%.2f%% realized=%.2f%% open=%.2f%% limit=%.2f%%",
                     riskWcPercent,
                     equityNow,
                     m_dailyGuard.EquityLossPercent(equityNow),
                     m_dailyGuard.RealizedLossPercent(),
                     m_dailyGuard.OpenRiskPercent(),
                     m_dailyGuard.MaxDailyRiskPercent());
      }
      bool allowed = m_dailyGuard.AllowNewTrade(riskWcPercent,equityNow);
      if(!allowed)
      {
         if(m_debugMode)
         {
            Print("RISK DEBUG: DailyGuard rejected trade -> overriding due to debug mode");
         }
         else
         {
            if(m_verboseMode)
               Print("RISK DEBUG: DailyGuard rejected trade -> entry blocked");
            return false;
         }
      }

      volume = lot;
      if(m_debugMode || m_verboseMode)
      {
         PrintFormat("RISK DEBUG: finalVolume=%.4f",volume);
      }
      return true;
   }

   bool DailyLimitBreached()
   {
      return m_dailyGuard.ShouldFlatten(AccountInfoDouble(ACCOUNT_EQUITY));
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
