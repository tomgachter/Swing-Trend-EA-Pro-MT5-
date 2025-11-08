#ifndef __EA_PRESETS_MQH__
#define __EA_PRESETS_MQH__

enum Regime
{
   REG_LOW = 0,
   REG_MID = 1,
   REG_HIGH = 2
};

enum ENUM_RiskGuardsPreset
{
   RISK_CONSERVATIVE = 0,
   RISK_BALANCED     = 1,
   RISK_OFFENSIVE    = 2
};

struct Preset
{
   // --- Entry ---
   int   votesRequired;
   int   donchBarsMin,donchBarsMax;
   double breakoutBufATR_Min,breakoutBufATR_Max;
   double adxMin;

   // --- Exit ---
   bool  useTP;
   double trailATR_K_low;
   double trailATR_K_high;
   bool  usePartial;
   double partialPct;
   double partialAtR;
   bool  useTimeStop;
   int   timeStopHours;

   // --- Pyramiding ---
   int   maxAddons;
   double addonStepATR;
   double addonMaxTotalRiskMult;

   // --- Filters ---
   bool  useEquityFilter;
   double equityUnderwaterPctBase;
   bool  useSessionBias;
};

struct RiskGuardProfile
{
   double dailyLossStop;
   double weeklyLossStop;
   double monthlyLossStop;
   double monthlyLossMultiplier;
   bool   equityFilterAlwaysOn;
   bool   equityFilterAdaptive;
};

inline double __preset_lerp(const double a,const double b,const double t)
{
   return a + (b-a)*t;
}

double PresetBufferATR(const Preset &preset,const Regime regime)
{
   double t = 0.0;
   if(regime==REG_MID)
      t=0.5;
   else if(regime==REG_HIGH)
      t=1.0;
   return __preset_lerp(preset.breakoutBufATR_Min,preset.breakoutBufATR_Max,t);
}

int PresetDonchianBars(const Preset &preset,const Regime regime)
{
   double base = (double)preset.donchBarsMin;
   double span = (double)(preset.donchBarsMax-preset.donchBarsMin);
   double t = 0.0;
   if(regime==REG_MID)
      t=0.5;
   else if(regime==REG_HIGH)
      t=1.0;
   return (int)MathRound(base + span*t);
}

double PresetTrailK(const Preset &preset,const Regime regime,const bool isAddon)
{
   double t=0.0;
   if(regime==REG_MID)
      t=0.5;
   else if(regime==REG_HIGH)
      t=1.0;
   double k=__preset_lerp(preset.trailATR_K_low,preset.trailATR_K_high,t);
   if(isAddon)
      k = MathMax(0.6,k-0.2);
   return k;
}

Regime DetectRegime()
{
   const int atrPeriod=14;
   const int emaPeriod=60;
   int handle = iATR(_Symbol,PERIOD_D1,atrPeriod);
   if(handle==INVALID_HANDLE)
      return REG_MID;

   double atrSeries[];
   ArraySetAsSeries(atrSeries,true);
   int copied = CopyBuffer(handle,0,0,emaPeriod,atrSeries);
   IndicatorRelease(handle);

   if(copied<emaPeriod)
      return REG_MID;

   double atrD1 = atrSeries[0];
   double alpha = 2.0/(emaPeriod+1.0);
   double ema   = atrSeries[emaPeriod-1];
   for(int i=emaPeriod-2;i>=0;--i)
      ema = alpha*atrSeries[i] + (1.0-alpha)*ema;
   double atrRef = ema;
   if(atrRef<=0.0)
      return REG_MID;
   double low = 0.9*atrRef;
   double high= 1.3*atrRef;
   if(atrD1<low)
      return REG_LOW;
   if(atrD1>high)
      return REG_HIGH;
   return REG_MID;
}

Preset MakePreset(const int aggressiveness,const Regime regime,const ENUM_RiskGuardsPreset guards)
{
   Preset preset;
   preset.votesRequired = 2;
   preset.donchBarsMin = 12;
   preset.donchBarsMax = 18;
   preset.breakoutBufATR_Min = 0.10;
   preset.breakoutBufATR_Max = 0.18;
   preset.adxMin = 22.0;
   preset.useTP = false;
   preset.trailATR_K_low = 1.2;
   preset.trailATR_K_high= 2.0;
   preset.usePartial = true;
   preset.partialPct = 30.0;
   preset.partialAtR = 2.2;
   preset.useTimeStop = false;
   preset.timeStopHours = 48;
   preset.maxAddons = 2;
   preset.addonStepATR = 0.8;
   preset.addonMaxTotalRiskMult = 2.2;
   preset.useEquityFilter = true;
   preset.equityUnderwaterPctBase = 5.0;
   preset.useSessionBias = false;

   switch(aggressiveness)
   {
      case 0: // Defensive
         preset.votesRequired = 2;
         preset.adxMin = 26.0;
         preset.donchBarsMin = 14;
         preset.donchBarsMax = 20;
         preset.breakoutBufATR_Min = 0.15;
         preset.breakoutBufATR_Max = 0.25;
         preset.trailATR_K_low = 1.1;
         preset.trailATR_K_high= 1.6;
         preset.usePartial = true;
         preset.partialPct = 45.0;
         preset.partialAtR = 2.0;
         preset.useTimeStop = (regime==REG_LOW);
         preset.timeStopHours = 48;
         preset.useTP = (regime==REG_LOW);
         preset.addonMaxTotalRiskMult = 1.6;
         break;
      case 2: // Aggressive
         preset.votesRequired = 2;
         preset.adxMin = 19.0;
         preset.donchBarsMin = 8;
         preset.donchBarsMax = 14;
         preset.breakoutBufATR_Min = 0.04;
         preset.breakoutBufATR_Max = 0.16;
         preset.trailATR_K_low = 1.4;
         preset.trailATR_K_high= 2.2;
         preset.usePartial = false;
         preset.partialPct = 18.0;
         preset.partialAtR = 2.5;
         preset.useTimeStop = false;
         preset.useTP = false;
         preset.addonMaxTotalRiskMult = 2.6;
         break;
      default: // Neutral
         preset.votesRequired = 2;
         preset.adxMin = 23.0;
         if(regime==REG_LOW)
         {
            preset.donchBarsMin = 8;
            preset.donchBarsMax = 12;
            preset.breakoutBufATR_Min = 0.05;
            preset.breakoutBufATR_Max = 0.10;
            preset.useTP = true;
            preset.useTimeStop = true;
            preset.timeStopHours = 48;
         }
         else if(regime==REG_HIGH)
         {
            preset.donchBarsMin = 16;
            preset.donchBarsMax = 20;
            preset.breakoutBufATR_Min = 0.15;
            preset.breakoutBufATR_Max = 0.25;
         }
         else
         {
            preset.donchBarsMin = 12;
            preset.donchBarsMax = 16;
            preset.breakoutBufATR_Min = 0.10;
            preset.breakoutBufATR_Max = 0.15;
         }
         preset.trailATR_K_low = 1.2;
         preset.trailATR_K_high= 2.0;
         preset.usePartial = true;
         preset.partialPct = 30.0;
         preset.partialAtR = 2.2;
         preset.useTimeStop = (regime==REG_LOW);
         preset.useTP = (regime==REG_LOW);
         preset.addonMaxTotalRiskMult = 2.0;
         break;
   }

   switch(guards)
   {
      case RISK_CONSERVATIVE:
         preset.useEquityFilter = true;
         preset.equityUnderwaterPctBase = 4.0;
         break;
      case RISK_OFFENSIVE:
         preset.equityUnderwaterPctBase = 6.5;
         preset.useEquityFilter = (regime!=REG_HIGH);
         break;
      default:
         preset.equityUnderwaterPctBase = 5.5;
         preset.useEquityFilter = true;
         break;
   }

   if(aggressiveness==2 && regime==REG_HIGH && guards==RISK_OFFENSIVE)
      preset.useEquityFilter=false;

   return preset;
}

RiskGuardProfile MakeRiskGuardProfile(const ENUM_RiskGuardsPreset guards)
{
   RiskGuardProfile profile;
   switch(guards)
   {
      case RISK_CONSERVATIVE:
         profile.dailyLossStop = 3.0;
         profile.weeklyLossStop = 1.0;
         profile.monthlyLossMultiplier = 1.2;
         profile.equityFilterAlwaysOn = true;
         profile.equityFilterAdaptive = false;
         break;
      case RISK_OFFENSIVE:
         profile.dailyLossStop = 5.0;
         profile.weeklyLossStop = 2.0;
         profile.monthlyLossMultiplier = 2.0;
         profile.equityFilterAlwaysOn = false;
         profile.equityFilterAdaptive = true;
         break;
      default:
         profile.dailyLossStop = 4.0;
         profile.weeklyLossStop = 1.5;
         profile.monthlyLossMultiplier = 1.8;
         profile.equityFilterAlwaysOn = false;
         profile.equityFilterAdaptive = true;
         break;
   }
   profile.monthlyLossStop = profile.weeklyLossStop*profile.monthlyLossMultiplier;
   return profile;
}

double ResolveAdaptiveEquityLimit(const Preset &preset,const RiskGuardProfile &profile,const double wtdPnLPct,const Regime regime,const int aggressiveness)
{
   double base = preset.equityUnderwaterPctBase;
   if(profile.equityFilterAlwaysOn)
      return base;
   if(!profile.equityFilterAdaptive)
      return base;
   double adaptive = 0.5*MathMax(0.0,-wtdPnLPct);
   double limit = MathMax(base,adaptive);
   if(regime==REG_HIGH && aggressiveness==2)
      limit = 1e6;
   return limit;
}

#endif // __EA_PRESETS_MQH__
