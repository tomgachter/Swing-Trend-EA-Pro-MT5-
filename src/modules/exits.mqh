#ifndef __EA_EXITS_MQH__
#define __EA_EXITS_MQH__

#include "EAGlobals.mqh"
#include "entries.mqh"
#include "presets.mqh"
#include "utils.mqh"

inline double RegimeWeight(const Regime regime)
{
   if(regime==REG_LOW)
      return 0.0;
   if(regime==REG_HIGH)
      return 1.0;
   return 0.5;
}

inline double RunnerTrailK(const bool isAddon)
{
   return PresetTrailK(gPreset,gRegime,isAddon);
}

inline bool ADXDeclining(const double current,const double previous)
{
   if(previous<=0.0)
      return true;
   return (current<previous);
}

inline bool ShouldTriggerPartial(const double rMultiple,const double adxCur,const double adxPrev,const bool isLong,const double emaEntry,const double close)
{
   if(!gPreset.usePartial)
      return false;
   if(rMultiple<gPreset.partialAtR)
      return false;
   bool conditionMomentum = ADXDeclining(adxCur,adxPrev);
   bool priceRevert = false;
   if(emaEntry>0.0 && close>0.0)
   {
      if(isLong)
         priceRevert = (close<emaEntry);
      else
         priceRevert = (close>emaEntry);
   }
   return (conditionMomentum || priceRevert);
}

inline double BreakEvenPlus(const double openPrice,const double initialRiskPts,const int direction)
{
   double point=SafePoint();
   double offset = 0.1*initialRiskPts*point;
   if(direction>0)
      return openPrice + offset;
   return openPrice - offset;
}

#endif // __EA_EXITS_MQH__
