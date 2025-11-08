#ifndef __EA_UTILS_MQH__
#define __EA_UTILS_MQH__

#include "EAGlobals.mqh"

#ifndef EA_DEBUG
#define EA_DEBUG 0
#endif

inline double Clamp(const double value,const double lo,const double hi)
{
   return MathMin(hi,MathMax(lo,value));
}

inline double Lerp(const double a,const double b,const double t)
{
   return a + (b-a)*t;
}

inline double SafePoint()
{
   double point=0.0;
   if(!SymbolInfoDouble(gConfig.symbol,SYMBOL_POINT,point) || point<=0.0)
      point=_Point;
   return MathMax(point,0.00001);
}

inline void PrintDebug(const string text)
{
   if(EA_DEBUG>0 || gConfig.debug)
      Print(text);
}

inline string EnumToString(const Regime regime)
{
   switch(regime)
   {
      case REG_LOW:  return "LOW";
      case REG_MID:  return "MID";
      case REG_HIGH: return "HIGH";
   }
   return "?";
}

inline double ToPoints(const double priceDistance)
{
   double point=SafePoint();
   return priceDistance/point;
}

inline double ToPrice(const double points)
{
   double point=SafePoint();
   return points*point;
}

#endif // __EA_UTILS_MQH__
