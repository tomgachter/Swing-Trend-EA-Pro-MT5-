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
   bool          valid;
   int           direction;
   double        entryPrice;
   double        stopLoss;
   double        atr;
   EntryFamily   family;
   SessionWindow session;
   RegimeBucket  regime;
   bool          fallbackRelaxed;
   double        quality;
   BiasStrength  biasStrength;
   bool          strongSetup;
   double        riskScale;

   EntrySignal()
   {
      valid = false;
      direction = 0;
      entryPrice = 0.0;
      stopLoss = 0.0;
      atr = 0.0;
      family = ENTRY_FAMILY_NONE;
      session = SESSION_NONE;
      regime = REGIME_NORMAL;
      fallbackRelaxed = false;
      quality = 0.0;
      biasStrength = BIAS_NEUTRAL;
      strongSetup = false;
      riskScale = 1.0;
   }
};

struct PullbackEvaluation
{
   bool   touched;
   bool   closeOk;
   bool   structureOk;
   bool   wickSupport;
   bool   momentumOk;
   double bodyAtrRatio;
   double momentumThreshold;
   double touchScore;
   double closeScore;
   double momentumScore;
   double structureScore;
   double wickScore;
   double quality;
   bool   strong;

   PullbackEvaluation()
   {
      touched = closeOk = structureOk = wickSupport = momentumOk = false;
      bodyAtrRatio = momentumThreshold = 0.0;
      touchScore = closeScore = momentumScore = structureScore = wickScore = 0.0;
      quality = 0.0;
      strong = false;
   }
};

struct BreakoutEvaluation
{
   bool   boxOk;
   bool   impulseOk;
   bool   clearedLevel;
   bool   madeExtreme;
   double boxSize;
   double minBoxMult;
   double maxBoxMult;
   double impulseThreshold;
   double bodyAtrRatio;
   double boxScore;
   double impulseScore;
   double breakoutScore;
   double quality;
   bool   strong;

   BreakoutEvaluation()
   {
      boxOk = impulseOk = clearedLevel = madeExtreme = false;
      boxSize = minBoxMult = maxBoxMult = impulseThreshold = bodyAtrRatio = 0.0;
      boxScore = impulseScore = breakoutScore = 0.0;
      quality = 0.0;
      strong = false;
   }
};

class EntryEngine
{
private:
   double m_slAtrMult;
   bool   m_randomize;
   double m_pullbackBodyAtrMin;
   double m_breakoutImpulseAtrMin;
   int    m_breakoutRangeBars;
   double m_minQualityCore;
   double m_minQualityEdge;
   bool   m_allowAggressiveEntries;
   double m_aggressiveDiscount;
   double m_aggressiveFloor;
   bool   m_allowNeutralBiasEdge;
   double m_neutralBiasRiskScale;

   double ScoreFromProximity(const double distance,const double scale) const
   {
      if(scale<=0.0)
         return 0.0;
      double ratio = MathMax(0.0,1.0 - MathAbs(distance)/(scale+1e-9));
      return MathMax(0.0,MathMin(1.0,ratio));
   }

   double EvaluatePullbackQuality(const int direction,const MqlRates &barPrev,const MqlRates &barPrev2,
                                  const double ema,const double atr,const bool relaxedMomentum,
                                  const RegimeBucket bucket,const bool verbose,PullbackEvaluation &out) const
   {
      out = PullbackEvaluation();
      if(atr<=0.0)
         return 0.0;

      double momentumThreshold = m_pullbackBodyAtrMin;
      if(bucket==REGIME_LOW)
         momentumThreshold *= 0.85;
      else if(bucket==REGIME_HIGH)
         momentumThreshold *= 1.10;
      if(relaxedMomentum)
         momentumThreshold *= 0.75;
      out.momentumThreshold = momentumThreshold;

      double body = MathAbs(barPrev.close-barPrev.open);
      out.bodyAtrRatio = (atr>0.0 ? body/atr : 0.0);
      out.momentumOk = (out.bodyAtrRatio >= momentumThreshold) || relaxedMomentum;
      out.momentumScore = MathMin(1.0,(momentumThreshold>0.0 ? out.bodyAtrRatio/(momentumThreshold+1e-9) : 0.0));
      out.momentumScore = MathMax(0.0,MathMin(1.0,out.momentumScore));

      double band = 0.45*atr;
      double tolerance = (relaxedMomentum ? 0.18 : 0.08)*atr;
      double distance = 0.0;

      if(direction>0)
      {
         distance = (ema-band) - barPrev.low;
         out.touched = (barPrev.low <= ema-band);
         if(!out.touched && relaxedMomentum)
            out.touched = (barPrev.low <= ema-0.10*atr);
         out.closeOk = (barPrev.close >= ema - tolerance);
         bool priorDown = (barPrev2.close < barPrev2.open);
         out.wickSupport = (barPrev.low <= ema - 0.25*atr);
         out.structureOk = (priorDown || out.wickSupport || relaxedMomentum);
      }
      else if(direction<0)
      {
         distance = barPrev.high - (ema+band);
         out.touched = (barPrev.high >= ema+band);
         if(!out.touched && relaxedMomentum)
            out.touched = (barPrev.high >= ema+0.10*atr);
         out.closeOk = (barPrev.close <= ema + tolerance);
         bool priorUp = (barPrev2.close > barPrev2.open);
         out.wickSupport = (barPrev.high >= ema + 0.25*atr);
         out.structureOk = (priorUp || out.wickSupport || relaxedMomentum);
      }

      out.touchScore = (out.touched ? 1.0 : ScoreFromProximity(distance,0.6*atr));
      double closeDistance = MathAbs(barPrev.close-ema);
      out.closeScore = (out.closeOk ? 1.0 : ScoreFromProximity(closeDistance,tolerance+0.25*atr));
      out.structureScore = (out.structureOk ? 1.0 : 0.0);
      out.wickScore = (out.wickSupport ? 1.0 : 0.0);

      double quality = 0.30*out.touchScore + 0.20*out.closeScore + 0.25*out.momentumScore + 0.15*out.structureScore + 0.10*out.wickScore;
      out.quality = MathMax(0.0,MathMin(1.0,quality));
      out.strong = (out.touched && out.closeOk && out.structureOk && out.momentumOk && out.bodyAtrRatio >= momentumThreshold*1.15);
      if(!out.strong && out.quality>=0.90)
         out.strong = true;

      if(verbose)
      {
         PrintFormat("ENTRY TRACE: pullback dir=%d touched=%s closeOk=%s structureOk=%s momentumOk=%s bodyATR=%.2f th=%.2f quality=%.2f strong=%s",
                     direction,
                     out.touched?"true":"false",
                     out.closeOk?"true":"false",
                     out.structureOk?"true":"false",
                     out.momentumOk?"true":"false",
                     out.bodyAtrRatio,
                     out.momentumThreshold,
                     out.quality,
                     out.strong?"true":"false");
      }
      return out.quality;
   }

   double EvaluateBreakoutQuality(const int direction,MqlRates &bars[],const int count,const double atr,
                                  const SessionWindow window,const bool relaxedMomentum,const RegimeBucket bucket,
                                  const bool verbose,BreakoutEvaluation &out) const
   {
      out = BreakoutEvaluation();
      if(atr<=0.0)
         return 0.0;

      int lookback = MathMax(4,m_breakoutRangeBars);
      if(count<lookback+2 || window==SESSION_NONE)
         return 0.0;

      MqlRates barPrev = bars[1];
      double rangeHigh = -DBL_MAX;
      double rangeLow  = DBL_MAX;
      int maxIndex = MathMin(count-1,1+lookback);
      for(int i=2;i<=maxIndex;i++)
      {
         rangeHigh = MathMax(rangeHigh,bars[i].high);
         rangeLow  = MathMin(rangeLow,bars[i].low);
      }
      double box = rangeHigh - rangeLow;
      out.boxSize = box;

      double minBoxMult = 0.15;
      double maxBoxMult = 1.0;
      if(bucket==REGIME_LOW)
         maxBoxMult *= 1.25;
      else if(bucket==REGIME_HIGH)
         maxBoxMult *= 0.85;
      if(relaxedMomentum)
         maxBoxMult *= 1.15;
      out.minBoxMult = minBoxMult;
      out.maxBoxMult = maxBoxMult;

      out.boxOk = (box>atr*minBoxMult && box<=atr*maxBoxMult);
      if(atr>0.0)
      {
         double norm = box/atr;
         double target = (minBoxMult+maxBoxMult)/2.0;
         double span = MathMax(0.05,(maxBoxMult-minBoxMult)/2.0);
         out.boxScore = MathMax(0.0,1.0 - MathAbs(norm-target)/(span+1e-9));
      }

      double impulseMult = m_breakoutImpulseAtrMin;
      if(bucket==REGIME_LOW)
         impulseMult *= (0.33/0.35);
      else if(bucket==REGIME_HIGH)
         impulseMult *= (0.40/0.35);
      out.impulseThreshold = impulseMult;

      double body = MathAbs(barPrev.close-barPrev.open);
      out.bodyAtrRatio = (atr>0.0 ? body/atr : 0.0);
      out.impulseOk = (body >= impulseMult*atr);
      if(relaxedMomentum)
         out.impulseOk = (body >= 0.25*atr);
      out.impulseScore = MathMin(1.0,(impulseMult>0.0 ? out.bodyAtrRatio/(impulseMult+1e-9) : 0.0));
      out.impulseScore = MathMax(0.0,MathMin(1.0,out.impulseScore));

      double breakoutBuffer = (relaxedMomentum ? 0.10 : 0.02)*atr;
      if(direction>0)
      {
         out.clearedLevel = (barPrev.close >= rangeHigh - breakoutBuffer);
         out.madeExtreme = (barPrev.high >= rangeHigh);
      }
      else if(direction<0)
      {
         out.clearedLevel = (barPrev.close <= rangeLow + breakoutBuffer);
         out.madeExtreme = (barPrev.low <= rangeLow);
      }

      out.breakoutScore = (out.clearedLevel && out.madeExtreme ? 1.0 : (out.clearedLevel || out.madeExtreme ? 0.6 : 0.0));
      double quality = 0.35*out.boxScore + 0.35*out.impulseScore + 0.30*out.breakoutScore;
      out.quality = MathMax(0.0,MathMin(1.0,quality));
      out.strong = (out.boxOk && out.impulseOk && out.clearedLevel && out.madeExtreme && out.bodyAtrRatio >= impulseMult*1.10);
      if(!out.strong && out.quality>=0.90)
         out.strong = true;

      if(verbose)
      {
         PrintFormat("ENTRY TRACE: breakout dir=%d box=%.2f atr=%.2f boxOk=%s impulseOk=%s cleared=%s newExtreme=%s quality=%.2f strong=%s",
                     direction,
                     box,
                     atr,
                     out.boxOk?"true":"false",
                     out.impulseOk?"true":"false",
                     out.clearedLevel?"true":"false",
                     out.madeExtreme?"true":"false",
                     out.quality,
                     out.strong?"true":"false");
      }
      return out.quality;
   }

   bool SelectBestSignal(const int direction,const double atr,const TrendBias &bias,const SessionWindow session,
                         const bool relaxedMomentum,const bool verbose,const double minQuality,
                         MqlRates &bars[],const int count,EntrySignal &signal) const
   {
      MqlRates barPrev = bars[1];
      MqlRates barPrev2 = bars[2];
      PullbackEvaluation pullEval;
      BreakoutEvaluation breakEval;
      double pullQuality = EvaluatePullbackQuality(direction,barPrev,barPrev2,bias.emaH1,atr,relaxedMomentum,signal.regime,verbose,pullEval);
      double breakQuality = EvaluateBreakoutQuality(direction,bars,count,atr,session,relaxedMomentum,signal.regime,verbose,breakEval);

      double bestQuality = 0.0;
      EntryFamily bestFamily = ENTRY_FAMILY_NONE;
      bool strongSetup = false;

      if(pullQuality>=breakQuality)
      {
         bestQuality = pullQuality;
         bestFamily = (pullQuality>0.0 ? ENTRY_FAMILY_PULLBACK : ENTRY_FAMILY_NONE);
         strongSetup = pullEval.strong;
      }
      else
      {
         bestQuality = breakQuality;
         bestFamily = (breakQuality>0.0 ? ENTRY_FAMILY_BREAKOUT : ENTRY_FAMILY_NONE);
         strongSetup = breakEval.strong;
      }

      if(bestFamily==ENTRY_FAMILY_NONE || bestQuality<minQuality)
      {
         if(verbose)
         {
            PrintFormat("ENTRY TRACE: bestQuality=%.2f below threshold %.2f (family=%d)",bestQuality,minQuality,(int)bestFamily);
         }
         return false;
      }

      signal.family = bestFamily;
      signal.direction = direction;
      signal.quality = bestQuality;
      signal.strongSetup = strongSetup;

      double entryPrice = (direction>0 ? SymbolInfoDouble(_Symbol,SYMBOL_ASK) : SymbolInfoDouble(_Symbol,SYMBOL_BID));
      if(m_randomize)
      {
         int seed = (int)(TimeCurrent()%100000);
         MathSrand(seed);
         double jitter = 0.1*atr*((double)MathRand()/32767.0-0.5);
         entryPrice += (direction>0 ? jitter : -jitter);
      }
      signal.entryPrice = entryPrice;
      signal.stopLoss = entryPrice - direction*m_slAtrMult*atr;
      signal.atr = atr;
      signal.valid = true;
      return true;
   }

public:
   EntryEngine(): m_slAtrMult(1.2), m_randomize(false),
                  m_pullbackBodyAtrMin(0.35), m_breakoutImpulseAtrMin(0.35), m_breakoutRangeBars(5),
                  m_minQualityCore(0.70), m_minQualityEdge(0.80),
                  m_allowAggressiveEntries(true), m_aggressiveDiscount(0.05), m_aggressiveFloor(0.60),
                  m_allowNeutralBiasEdge(true), m_neutralBiasRiskScale(0.5)
   {
   }

   void Configure(const bool randomize)
   {
      m_randomize = randomize;
   }

   void SetStopMultiplier(const double slMult)
   {
      if(slMult>0.0)
         m_slAtrMult = slMult;
   }

   void ConfigureSensitivity(const double pullbackBodyAtrMin,const double breakoutImpulseAtrMin,const int breakoutRangeBars)
   {
      if(pullbackBodyAtrMin>0.0)
         m_pullbackBodyAtrMin = pullbackBodyAtrMin;
      if(breakoutImpulseAtrMin>0.0)
         m_breakoutImpulseAtrMin = breakoutImpulseAtrMin;
      if(breakoutRangeBars>=4)
         m_breakoutRangeBars = breakoutRangeBars;
   }

   void SetQualityThresholds(const double minCore,const double minEdge,const bool allowAggressive,const double aggressiveDiscount,const double aggressiveFloor)
   {
      if(minCore>0.0)
         m_minQualityCore = MathMin(0.95,minCore);
      if(minEdge>0.0)
         m_minQualityEdge = MathMin(0.95,minEdge);
      m_allowAggressiveEntries = allowAggressive;
      if(aggressiveDiscount>=0.0)
         m_aggressiveDiscount = aggressiveDiscount;
      if(aggressiveFloor>0.0)
         m_aggressiveFloor = aggressiveFloor;
   }

   void ConfigureNeutralPolicy(const bool allowNeutralEdge,const double neutralRiskScale)
   {
      m_allowNeutralBiasEdge = allowNeutralEdge;
      m_neutralBiasRiskScale = MathMax(0.0,MathMin(1.0,neutralRiskScale));
   }

   bool Evaluate(const TrendBias &bias,RegimeFilter &regime,const SessionWindow session,MqlRates &bars[],const int count,
                 const bool relaxedMomentum,const bool fallbackMode,const bool verbose,const bool allowAggressiveBoost,
                 EntrySignal &signal)
   {
      // Score-driven entry filter: pullbacks/breakouts return 0..1 quality metrics so we can
      // relax/ tighten trade frequency via MinEntryQuality inputs and aggressive-mode offsets.
      signal = EntrySignal();
      signal.session = session;
      signal.regime = regime.CurrentBucket();
      signal.fallbackRelaxed = relaxedMomentum;
      signal.biasStrength = bias.strength;

      if(count<3)
      {
         if(verbose)
            Print("ENTRY TRACE: abort -> insufficient bars for evaluation");
         return false;
      }

      double atr = regime.AtrH1();
      if(atr<=0.0)
      {
         if(verbose)
            PrintFormat("ENTRY TRACE: abort -> invalid ATR %.5f",atr);
         return false;
      }

      double baseQuality = (session==SESSION_CORE ? m_minQualityCore : m_minQualityEdge);
      if(fallbackMode && session!=SESSION_CORE)
         baseQuality = m_minQualityEdge;
      double minQuality = baseQuality;
      bool aggressiveApplied = false;
      if(m_allowAggressiveEntries && allowAggressiveBoost && bias.strength==BIAS_STRONG)
      {
         minQuality = MathMax(m_aggressiveFloor,minQuality - m_aggressiveDiscount);
         aggressiveApplied = true;
         if(verbose)
            PrintFormat("ENTRY TRACE: aggressive mode -> minQuality adjusted to %.2f (base %.2f)",minQuality,baseQuality);
      }

      bool allowModerate = fallbackMode;
      bool allowNeutral = (m_allowNeutralBiasEdge && (session==SESSION_EDGE || fallbackMode));

      int evalDirection = bias.direction;
      BiasStrength activeStrength = bias.strength;

      if(activeStrength==BIAS_STRONG && evalDirection==0)
      {
         activeStrength = BIAS_NEUTRAL;
      }

      if(activeStrength==BIAS_NEUTRAL)
      {
         if(!allowNeutral)
         {
            if(verbose)
               Print("ENTRY TRACE: abort -> bias neutral and neutral trades disabled");
            return false;
         }
      }
      else if(activeStrength==BIAS_MODERATE)
      {
         if(!allowModerate)
         {
            if(verbose)
               PrintFormat("ENTRY TRACE: abort -> bias moderate but fallbackMode=%s",fallbackMode?"true":"false");
            return false;
         }
      }
      else if(activeStrength==BIAS_STRONG && evalDirection==0)
      {
         if(verbose)
            Print("ENTRY TRACE: abort -> bias strong but direction unresolved");
         return false;
      }

      bool neutralMode = (activeStrength==BIAS_NEUTRAL || evalDirection==0);
      bool produced = false;

      if(neutralMode)
      {
         double bestQuality = -1.0;
         EntrySignal candidate;
         int dirs[2] = {+1,-1};
         for(int i=0;i<2;i++)
         {
            EntrySignal temp = signal;
            if(!SelectBestSignal(dirs[i],atr,bias,session,relaxedMomentum,verbose,minQuality,bars,count,temp))
               continue;
            if(!temp.strongSetup)
            {
               if(verbose)
                  PrintFormat("ENTRY TRACE: neutral bias -> rejecting direction %d due to non-strong setup",dirs[i]);
               continue;
            }
            if(temp.quality>bestQuality)
            {
               bestQuality = temp.quality;
               candidate = temp;
            }
         }
         if(bestQuality>0.0)
         {
            candidate.biasStrength = BIAS_NEUTRAL;
            candidate.riskScale = (m_neutralBiasRiskScale>0.0 ? m_neutralBiasRiskScale : 0.0);
            signal = candidate;
            produced = candidate.riskScale>0.0;
            if(produced && verbose)
            {
               PrintFormat("ENTRY TRACE: neutral bias override -> direction=%d quality=%.2f riskScale=%.2f",
                           signal.direction,signal.quality,signal.riskScale);
            }
         }
         else if(verbose)
         {
            Print("ENTRY TRACE: neutral bias -> no qualifying strong setup");
         }
      }
      else
      {
         int direction = (evalDirection!=0 ? evalDirection : (bias.score>=0.0 ? +1 : -1));
         if(SelectBestSignal(direction,atr,bias,session,relaxedMomentum,verbose,minQuality,bars,count,signal))
         {
            signal.biasStrength = activeStrength;
            signal.riskScale = 1.0;
            if(aggressiveApplied && signal.family!=ENTRY_FAMILY_PULLBACK && signal.quality<baseQuality)
            {
               if(verbose)
                  Print("ENTRY TRACE: breakout quality below base threshold when aggressive boost was pullback-only");
               produced = false;
            }
            else
               produced = true;
         }
         else if(verbose)
         {
            Print("ENTRY TRACE: no entry pattern met the quality threshold in bias direction");
         }
      }

      if(!produced)
         return false;

      signal.valid = true;
      return true;
   }

   double StopMultiplier() const { return m_slAtrMult; }
};

#endif // __ENTRY_ENGINE_MQH__
