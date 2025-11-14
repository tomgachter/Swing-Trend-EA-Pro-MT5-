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
   double m_pullbackBodyAtrMin;
   double m_breakoutImpulseAtrMin;
   int    m_breakoutRangeBars;

   struct PullbackDiagnostics
   {
      double bodyAtrRatio;
      double momentumThreshold;
      bool   momentumOk;
   };

   struct BreakoutDiagnostics
   {
      double bodyAtrRatio;
      double impulseThreshold;
      bool   impulseOk;
   };

   bool PullbackSignal(const int direction,const MqlRates &barPrev,const MqlRates &barPrev2,const double ema,const double atr,
                       const bool relaxedMomentum,const RegimeBucket bucket,const bool verbose,PullbackDiagnostics &diag)
   {
      double momentumThreshold = m_pullbackBodyAtrMin;
      if(bucket==REGIME_LOW)
         momentumThreshold *= 0.85;
      else if(bucket==REGIME_HIGH)
         momentumThreshold *= 1.10;
      if(relaxedMomentum)
         momentumThreshold *= 0.75;
      double band = 0.45*atr;

      double body = MathAbs(barPrev.close-barPrev.open);
      double bodyAtrRatio = (atr>0.0 ? body/atr : 0.0);
      bool momentumOk = (body >= momentumThreshold*atr) || relaxedMomentum;

      diag.bodyAtrRatio = bodyAtrRatio;
      diag.momentumThreshold = momentumThreshold;
      diag.momentumOk = momentumOk;

      bool touched=false;
      bool closeOk=false;
      bool structureOk=false;

      if(direction>0)
      {
         touched = (barPrev.low <= ema - band);
         if(!touched && relaxedMomentum)
            touched = (barPrev.low <= ema + 0.10*atr);
         double tolerance = (relaxedMomentum ? 0.15 : 0.05)*atr;
         closeOk = (barPrev.close >= ema - tolerance);
         bool priorDown = (barPrev2.close < barPrev2.open);
         bool deepWick = (barPrev.low <= ema - 0.25*atr);
         structureOk = (priorDown || deepWick || relaxedMomentum);
      }
      else if(direction<0)
      {
         touched = (barPrev.high >= ema + band);
         if(!touched && relaxedMomentum)
            touched = (barPrev.high >= ema - 0.10*atr);
         double tolerance = (relaxedMomentum ? 0.15 : 0.05)*atr;
         closeOk = (barPrev.close <= ema + tolerance);
         bool priorUp = (barPrev2.close > barPrev2.open);
         bool deepWick = (barPrev.high >= ema + 0.25*atr);
         structureOk = (priorUp || deepWick || relaxedMomentum);
      }

      bool signal = touched && closeOk && momentumOk && structureOk;
      if(verbose)
      {
         PrintFormat("ENTRY TRACE: pullback dir=%d touched=%s closeOk=%s momentumOk=%s bodyATR=%.2f threshold=%.2f structureOk=%s relaxed=%s",
                     direction,
                     touched?"true":"false",
                     closeOk?"true":"false",
                     momentumOk?"true":"false",
                     bodyAtrRatio,
                     momentumThreshold,
                     structureOk?"true":"false",
                     relaxedMomentum?"true":"false");
      }
      return signal;
   }

   bool BreakoutSignal(const int direction,MqlRates &bars[],const int count,const double atr,const SessionWindow window,
                       const bool relaxedMomentum,const RegimeBucket bucket,const bool verbose,BreakoutDiagnostics &diag)
   {
      int lookback = MathMax(4,m_breakoutRangeBars);
      if(count<lookback+2)
      {
         if(verbose)
            Print("ENTRY TRACE: breakout rejected -> not enough bars");
         return false;
      }
      if(window==SESSION_NONE)
      {
         if(verbose)
            Print("ENTRY TRACE: breakout rejected -> session disallows entry");
         return false;
      }
      MqlRates barPrev = bars[1];
      double rangeHigh = -DBL_MAX;
      double rangeLow  = DBL_MAX;
      int maxIndex = MathMin(count-1,1+lookback);
      for(int i=2;i<=maxIndex;i++)
      {
         rangeHigh = MathMax(rangeHigh,bars[i].high);
         rangeLow  = MathMin(rangeLow,bars[i].low);
      }
      double box = rangeHigh-rangeLow;
      const double MAX_BOX_BASE = 1.0;
      double maxBoxMult = MAX_BOX_BASE;
      if(bucket==REGIME_LOW)
         maxBoxMult = MAX_BOX_BASE*1.25;
      else if(bucket==REGIME_HIGH)
         maxBoxMult = MAX_BOX_BASE*0.85;
      if(relaxedMomentum)
         maxBoxMult *= 1.15;
      double minBoxMult = 0.15;
      bool boxOk = (box>atr*minBoxMult && box<=atr*maxBoxMult);

      const double LOW_IMPULSE_SCALE = 0.33/0.35;
      const double HIGH_IMPULSE_SCALE = 0.40/0.35;
      double impulseMult = m_breakoutImpulseAtrMin;
      if(bucket==REGIME_LOW)
         impulseMult *= LOW_IMPULSE_SCALE;
      else if(bucket==REGIME_HIGH)
         impulseMult *= HIGH_IMPULSE_SCALE;
      double body = MathAbs(barPrev.close-barPrev.open);
      bool impulse = (body >= impulseMult*atr);
      if(relaxedMomentum)
         impulse = (body >= 0.20*atr);

      diag.bodyAtrRatio = (atr>0.0 ? body/atr : 0.0);
      diag.impulseThreshold = impulseMult;
      diag.impulseOk = impulse;

      double breakoutBuffer = (relaxedMomentum ? 0.10 : 0.02)*atr;
      bool signal=false;
      if(direction>0 && boxOk)
      {
         bool clearedHigh = (barPrev.close >= rangeHigh - breakoutBuffer);
         bool madeNewHigh = (barPrev.high >= rangeHigh);
         signal = clearedHigh && madeNewHigh && impulse;
      }
      else if(direction<0 && boxOk)
      {
         bool clearedLow = (barPrev.close <= rangeLow + breakoutBuffer);
         bool madeNewLow = (barPrev.low <= rangeLow);
         signal = clearedLow && madeNewLow && impulse;
      }

      if(verbose)
      {
         PrintFormat("ENTRY TRACE: breakout dir=%d box=%.2f atr=%.2f boxOk=%s impulseOk=%s bodyATR=%.2f buffer=%.2f signal=%s",
                     direction,
                     box,
                     atr,
                     boxOk?"true":"false",
                     impulse?"true":"false",
                     (atr>0.0 ? body/atr : 0.0),
                     breakoutBuffer,
                     signal?"true":"false");
      }
      return signal;
   }

public:
   EntryEngine(): m_slAtrMult(1.4), m_tpAtrMult(0.8), m_trailAtrMult(2.5), m_randomize(false),
                  m_pullbackBodyAtrMin(0.35), m_breakoutImpulseAtrMin(0.35),
                  m_breakoutRangeBars(5)
   {
   }

   void Configure(const bool randomize)
   {
      m_randomize = randomize;
   }

   void ConfigureSensitivity(const double pullbackBodyAtrMin,const double breakoutImpulseAtrMin,
                             const int breakoutRangeBars)
   {
      if(pullbackBodyAtrMin>0.0)
         m_pullbackBodyAtrMin = pullbackBodyAtrMin;
      if(breakoutImpulseAtrMin>0.0)
         m_breakoutImpulseAtrMin = breakoutImpulseAtrMin;
      if(breakoutRangeBars>=4)
         m_breakoutRangeBars = breakoutRangeBars;
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

   bool IsStrongSetup(const EntryFamily fam,const double atr,
                      const MqlRates &barPrev,const double ema)
   {
      if(fam==ENTRY_FAMILY_PULLBACK)
      {
         return (MathAbs(barPrev.close-barPrev.open) >= 0.6*atr) &&
                ((barPrev.close>ema+0.5*atr) || (barPrev.close<ema-0.5*atr));
      }
      if(fam==ENTRY_FAMILY_BREAKOUT)
      {
         return (MathAbs(barPrev.close-barPrev.open) >= 0.5*atr);
      }
      return false;
   }

   bool Evaluate(BiasEngine &bias,RegimeFilter &regime,const SessionWindow session,MqlRates &bars[],const int count,
                 const bool relaxedMomentum,const bool allowNeutralBiasEdge,const bool verbose,EntrySignal &signal)
   {
      signal.valid = false;
      signal.direction = 0;
      signal.family = ENTRY_FAMILY_NONE;
      signal.session = session;
      signal.regime = regime.CurrentBucket();
      signal.fallbackRelaxed = relaxedMomentum;

      if(verbose)
      {
         PrintFormat("ENTRY TRACE: evaluate start count=%d session=%d relaxed=%s",count,(int)session,
                     relaxedMomentum?"true":"false");
      }

      if(count<3)
      {
         if(verbose)
            PrintFormat("ENTRY TRACE: abort -> insufficient bars (count=%d)",count);
         return false;
      }

      int direction = bias.Direction();
      bool neutralEdgeMode = (direction==0 && allowNeutralBiasEdge && session==SESSION_EDGE);
      if(direction==0 && !neutralEdgeMode)
      {
         if(verbose)
         {
            PrintFormat("NO_TRADE_REASON: bias votes=up:%d dn:%d neutral:%d slope(H1/H4/D1)=%.3f/%.3f/%.3f thresholds=%.3f/%.3f/%.3f",
                        bias.VotesUp(),bias.VotesDown(),bias.VotesNeutral(),
                        bias.SlopeH1(),bias.SlopeH4(),bias.SlopeD1(),
                        bias.ThresholdH1(),bias.ThresholdH4(),bias.ThresholdD1());
         }
         return false;
      }

      double atr = regime.AtrH1();
      if(atr<=0.0)
      {
         if(verbose)
            PrintFormat("ENTRY TRACE: abort -> ATR invalid (atr=%.5f)",atr);
         return false;
      }

      MqlRates barPrev = bars[1];
      MqlRates barPrev2 = bars[2];

      PullbackDiagnostics pullDiagPos = {0.0,0.0,false};
      PullbackDiagnostics pullDiagNeg = {0.0,0.0,false};
      BreakoutDiagnostics breakoutDiagPos = {0.0,0.0,false};
      BreakoutDiagnostics breakoutDiagNeg = {0.0,0.0,false};

      if(neutralEdgeMode)
      {
         int chosenDir = 0;
         EntryFamily chosenFamily = ENTRY_FAMILY_NONE;

         if(PullbackSignal(+1,barPrev,barPrev2,bias.EmaH1(),atr,relaxedMomentum,signal.regime,verbose,pullDiagPos) &&
            IsStrongSetup(ENTRY_FAMILY_PULLBACK,atr,barPrev,bias.EmaH1()))
         {
            chosenDir = +1;
            chosenFamily = ENTRY_FAMILY_PULLBACK;
         }
         else if(PullbackSignal(-1,barPrev,barPrev2,bias.EmaH1(),atr,relaxedMomentum,signal.regime,verbose,pullDiagNeg) &&
                 IsStrongSetup(ENTRY_FAMILY_PULLBACK,atr,barPrev,bias.EmaH1()))
         {
            chosenDir = -1;
            chosenFamily = ENTRY_FAMILY_PULLBACK;
         }
         else if(BreakoutSignal(+1,bars,count,atr,session,relaxedMomentum,signal.regime,verbose,breakoutDiagPos) &&
                 IsStrongSetup(ENTRY_FAMILY_BREAKOUT,atr,barPrev,bias.EmaH1()))
         {
            chosenDir = +1;
            chosenFamily = ENTRY_FAMILY_BREAKOUT;
         }
         else if(BreakoutSignal(-1,bars,count,atr,session,relaxedMomentum,signal.regime,verbose,breakoutDiagNeg) &&
                 IsStrongSetup(ENTRY_FAMILY_BREAKOUT,atr,barPrev,bias.EmaH1()))
         {
            chosenDir = -1;
            chosenFamily = ENTRY_FAMILY_BREAKOUT;
         }

         if(chosenDir==0)
         {
            if(verbose)
            {
               Print("NO_TRADE_REASON: neutral bias edge -> no strong setup detected");
            }
            return false;
         }

         signal.valid = true;
         signal.direction = chosenDir;
         signal.family = chosenFamily;
         direction = chosenDir;
      }
      else
      {
         if(PullbackSignal(direction,barPrev,barPrev2,bias.EmaH1(),atr,relaxedMomentum,signal.regime,verbose,pullDiagPos))
         {
            signal.valid = true;
            signal.direction = direction;
            signal.family = ENTRY_FAMILY_PULLBACK;
         }
         else if(BreakoutSignal(direction,bars,count,atr,session,relaxedMomentum,signal.regime,verbose,breakoutDiagPos))
         {
            signal.valid = true;
            signal.direction = direction;
            signal.family = ENTRY_FAMILY_BREAKOUT;
         }
         else if(relaxedMomentum)
         {
            double ema = bias.EmaH1();
            double distance = MathAbs(barPrev.close-ema);
            double tolerance = 0.85*atr;
            bool bodyAligned = (direction>0 ? (barPrev.close >= barPrev.open) : (barPrev.close <= barPrev.open));
            bool wickSupport = (direction>0 ? (barPrev.low <= ema - 0.20*atr) : (barPrev.high >= ema + 0.20*atr));
            if(distance<=tolerance && (bodyAligned || wickSupport))
            {
               signal.valid = true;
               signal.direction = direction;
               signal.family = ENTRY_FAMILY_PULLBACK;
               if(verbose)
               {
                  PrintFormat("ENTRY TRACE: fallback entry triggered distance=%.2f tolerance=%.2f bodyAligned=%s wickSupport=%s",
                              distance,tolerance,bodyAligned?"true":"false",wickSupport?"true":"false");
               }
            }
            else if(verbose)
            {
               PrintFormat("ENTRY TRACE: fallback entry rejected distance=%.2f tolerance=%.2f bodyAligned=%s wickSupport=%s",
                           distance,tolerance,bodyAligned?"true":"false",wickSupport?"true":"false");
            }
         }

         if(!signal.valid)
         {
            if(verbose)
               Print("ENTRY TRACE: no entry pattern triggered");
            if(verbose && !pullDiagPos.momentumOk)
            {
               PrintFormat("NO_TRADE_REASON: momentum bodyATR=%.2f threshold=%.2f",
                           pullDiagPos.bodyAtrRatio,pullDiagPos.momentumThreshold);
            }
            if(verbose && !breakoutDiagPos.impulseOk)
            {
               PrintFormat("NO_TRADE_REASON: breakout impulseATR=%.2f threshold=%.2f",
                           breakoutDiagPos.bodyAtrRatio,breakoutDiagPos.impulseThreshold);
            }
            return false;
         }
      }

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
      if(verbose)
      {
         PrintFormat("ENTRY TRACE: signal family=%d dir=%d entry=%.2f stop=%.2f atr=%.2f",(int)signal.family,
                     signal.direction,signal.entryPrice,signal.stopLoss,signal.atr);
      }
      return true;
   }

   double TrailMultiplier() { return m_trailAtrMult; }
   double StopMultiplier() { return m_slAtrMult; }
   double PartialMultiplier() { return m_tpAtrMult; }
};

#endif // __ENTRY_ENGINE_MQH__
