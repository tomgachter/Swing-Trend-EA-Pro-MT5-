#ifndef __ENTRY_ENGINE_MQH__
#define __ENTRY_ENGINE_MQH__

#include "BiasEngine.mqh"
#include "SessionFilter.mqh"

enum EntryFamily
{
   ENTRY_FAMILY_NONE = -1,
   ENTRY_FAMILY_PULLBACK = 0,
   ENTRY_FAMILY_BREAKOUT = 1
};

struct EntrySignal
{
   bool         valid;
   int          direction;
   double       entryPrice;
   double       stopLoss;
   double       partialLevel;
   double       atr;
   EntryFamily  family;
   SessionWindow session;
   RegimeBucket regime;
   bool         fallbackRelaxed;
};

class EntryEngine
{
private:
   double m_slAtrMult;
   double m_tpAtrMult;
   double m_trailAtrMult;
   bool   m_randomize;

   bool PullbackSignal(const int direction,const MqlRates &barPrev,const MqlRates &barPrev2,const double ema,const double atr,
                       const bool relaxedMomentum,const RegimeBucket bucket)
   {
      double bandMult = 0.6;
      if(bucket==REGIME_LOW)
         bandMult = 0.75;
      else if(bucket==REGIME_HIGH)
         bandMult = 0.5;
      double band = bandMult*atr;
      double momentumThreshold = 0.55;
      if(bucket==REGIME_LOW)
         momentumThreshold = 0.4;
      else if(bucket==REGIME_HIGH)
         momentumThreshold = 0.5;
      if(relaxedMomentum)
         momentumThreshold *= 0.6;
      double body = MathAbs(barPrev.close-barPrev.open);
      bool momentumOk = (body >= momentumThreshold*atr) || relaxedMomentum;
      if(direction>0)
      {
         bool touched = (barPrev.low <= ema - band);
         if(!touched && relaxedMomentum)
            touched = (barPrev.low <= ema);
         bool closeAbove = (barPrev.close > ema);
         bool priorDown = (barPrev2.close < barPrev2.open);
         return touched && closeAbove && momentumOk && (priorDown || relaxedMomentum);
      }
      else if(direction<0)
      {
         bool touched = (barPrev.high >= ema + band);
         if(!touched && relaxedMomentum)
            touched = (barPrev.high >= ema);
         bool closeBelow = (barPrev.close < ema);
         bool priorUp = (barPrev2.close > barPrev2.open);
         return touched && closeBelow && momentumOk && (priorUp || relaxedMomentum);
      }
      return false;
   }

   bool BreakoutSignal(const int direction,MqlRates &bars[],const int count,const double atr,const SessionWindow window,
                       const bool relaxedMomentum,const RegimeBucket bucket)
   {
      if(count<4)
         return false;
      if(window==SESSION_NONE)
         return false;
      MqlRates barPrev = bars[1];
      double rangeHigh = -DBL_MAX;
      double rangeLow  = DBL_MAX;
      for(int i=2;i<=5 && i<count;i++)
      {
         rangeHigh = MathMax(rangeHigh,bars[i].high);
         rangeLow  = MathMin(rangeLow,bars[i].low);
      }
      double box = rangeHigh-rangeLow;
      double maxBoxMult = 0.8;
      if(bucket==REGIME_LOW)
         maxBoxMult = 1.05;
      else if(bucket==REGIME_HIGH)
         maxBoxMult = 0.65;
      if(box<=0.0 || box>atr*maxBoxMult)
         return false;
      double impulseMult = 0.5;
      if(bucket==REGIME_LOW)
         impulseMult = 0.35;
      else if(bucket==REGIME_HIGH)
         impulseMult = 0.45;
      bool impulse = (MathAbs(barPrev.close-barPrev.open) >= impulseMult*atr);
      if(relaxedMomentum)
         impulse = true;
      if(direction>0)
      {
         if(barPrev.close>rangeHigh && impulse)
            return true;
      }
      else if(direction<0)
      {
         if(barPrev.close<rangeLow && impulse)
            return true;
      }
      return false;
   }

public:
   EntryEngine(): m_slAtrMult(1.4), m_tpAtrMult(0.8), m_trailAtrMult(2.5), m_randomize(false)
   {
   }

   void Configure(const bool randomize)
   {
      m_randomize = randomize;
   }

   void SetMultipliers(const double slMult,const double tpMult,const double trailMult)
   {
      if(slMult>0.0)
         m_slAtrMult = slMult;
      if(tpMult>0.0)
         m_tpAtrMult = tpMult;
      if(trailMult>0.0)
         m_trailAtrMult = trailMult;
   }

   bool Evaluate(BiasEngine &bias,RegimeFilter &regime,const SessionWindow session,MqlRates &bars[],const int count,const bool relaxedMomentum,EntrySignal &signal)
   {
      signal.valid = false;
      signal.direction = 0;
      signal.family = ENTRY_FAMILY_NONE;
      signal.session = session;
      signal.regime = regime.CurrentBucket();
      signal.fallbackRelaxed = relaxedMomentum;

      if(count<3)
         return false;

      int direction = bias.Direction();
      if(direction==0)
         return false;

      double atr = regime.AtrH1();
      if(atr<=0.0)
         return false;

      MqlRates barPrev = bars[1];
      MqlRates barPrev2 = bars[2];

      if(PullbackSignal(direction,barPrev,barPrev2,bias.EmaH1(),atr,relaxedMomentum,signal.regime))
      {
         signal.valid = true;
         signal.direction = direction;
         signal.family = ENTRY_FAMILY_PULLBACK;
      }
      else if(BreakoutSignal(direction,bars,count,atr,session,relaxedMomentum,signal.regime))
      {
         signal.valid = true;
         signal.direction = direction;
         signal.family = ENTRY_FAMILY_BREAKOUT;
      }

      if(!signal.valid)
         return false;

      signal.atr = atr;
      double entryPrice = (direction>0 ? SymbolInfoDouble(_Symbol,SYMBOL_ASK) : SymbolInfoDouble(_Symbol,SYMBOL_BID));
      if(m_randomize)
      {
         int seed = (int)(TimeCurrent()%100000);
         MathSrand(seed);
         double jitter = 0.1*atr*((double)MathRand()/32767.0-0.5);
         entryPrice += (direction>0 ? jitter : -jitter);
      }
      double sl = entryPrice - direction*m_slAtrMult*atr;
      signal.entryPrice = entryPrice;
      signal.stopLoss = sl;
      signal.partialLevel = entryPrice + direction*m_tpAtrMult*atr;
      return true;
   }

   double TrailMultiplier() { return m_trailAtrMult; }
   double StopMultiplier() { return m_slAtrMult; }
   double PartialMultiplier() { return m_tpAtrMult; }
};

#endif // __ENTRY_ENGINE_MQH__
