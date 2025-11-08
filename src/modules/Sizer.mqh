#ifndef __SIZER_MQH__
#define __SIZER_MQH__

enum RiskMode
{
   RISK_FIXED_LOTS = 0,
   RISK_PERCENT_PER_TRADE = 1
};

struct SymbolContext
{
   double tickSize;
   double tickValue;
   double point;
   double contractSize;
   double lotStep;
   double minLot;
   double maxLot;
};

class PositionSizer
{
private:
   SymbolContext m_ctx;

public:
   bool Init(const string symbol)
   {
      ZeroMemory(m_ctx);
      if(!SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE,m_ctx.tickSize)) return false;
      if(!SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_VALUE,m_ctx.tickValue)) return false;
      if(!SymbolInfoDouble(symbol,SYMBOL_POINT,m_ctx.point)) return false;
      if(!SymbolInfoDouble(symbol,SYMBOL_TRADE_CONTRACT_SIZE,m_ctx.contractSize)) return false;
      if(!SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP,m_ctx.lotStep)) return false;
      if(!SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN,m_ctx.minLot)) return false;
      if(!SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX,m_ctx.maxLot)) return false;
      return true;
   }

   double NormalizeVolume(const double volume)
   {
      double lots = MathFloor(volume/m_ctx.lotStep+0.5)*m_ctx.lotStep;
      lots = MathMax(m_ctx.minLot,MathMin(m_ctx.maxLot,lots));
      return lots;
   }

   double StopDistancePoints(const double entry,const double stop)
   {
      return MathAbs(entry-stop)/m_ctx.point;
   }

   double PipValuePerLot()
   {
      if(m_ctx.point<=0.0)
         return 0.0;
      return (m_ctx.tickValue/m_ctx.tickSize)*m_ctx.point;
   }

   double CalculateVolume(const RiskMode mode,const double riskSetting,const double stopPoints,const double balance,const double riskAdjustment=1.0)
   {
      if(stopPoints<=0.0)
         return 0.0;
      double volume=0.0;
      if(mode==RISK_FIXED_LOTS)
      {
         volume = riskSetting*riskAdjustment;
      }
      else
      {
         double riskPercent = riskSetting*riskAdjustment;
         double riskAmount  = balance * (riskPercent/100.0);
         double perLotLoss  = stopPoints * PipValuePerLot();
         if(perLotLoss<=0.0)
            return 0.0;
         volume = riskAmount / perLotLoss;
      }
      return NormalizeVolume(volume);
   }

   SymbolContext Context() { return m_ctx; }
};

#endif // __SIZER_MQH__
