#ifndef __EA_RISKGUARDS_MQH__
#define __EA_RISKGUARDS_MQH__

#include "EAGlobals.mqh"
#include "utils.mqh"
#include "presets.mqh"
#include "Accounting.mqh"
#include "MarketUtils.mqh"

struct RiskRuntime
{
   double equityLimitPct;
   bool   equityFilterActive;
   double riskScale;
};

RiskRuntime gRiskRuntime = {0.0,true,1.0};

inline double LossPct(const double lossValue,const double basis)
{
   if(basis<=0.0)
      return 0.0;
   return 100.0*lossValue/MathMax(1.0,basis);
}

bool EvaluateRiskStops(const RiskGuardProfile &profile,const double equity)
{
   double dayLoss = (gDailyPnL<0.0 ? -gDailyPnL : 0.0);
   double weekLoss = (gWeeklyPnL<0.0 ? -gWeeklyPnL : 0.0);
   double monthLoss = (gMonthlyPnL<0.0 ? -gMonthlyPnL : 0.0);

   double dayBasis = MathMax(1.0,dayStartEquity);
   double dayLossPct = LossPct(dayLoss,dayBasis);
   double weekLossPct = LossPct(weekLoss,MathMax(1.0,equity));
   double monthLossPct = LossPct(monthLoss,MathMax(1.0,equity));

   if(dayLossPct>=profile.dailyLossStop)
   {
      gCoolingOffUntil = DateOfNextBrokerMidnight();
      PrintDebug(StringFormat("Risk: Daily loss %.2f%% >= %.2f%%",dayLossPct,profile.dailyLossStop));
      return false;
   }
   if(weekLossPct>=profile.weeklyLossStop)
   {
      gCoolingOffUntil = TimeCurrent()+24*3600;
      PrintDebug(StringFormat("Risk: Weekly loss %.2f%% >= %.2f%%",weekLossPct,profile.weeklyLossStop));
      return false;
   }
   if(monthLossPct>=profile.monthlyLossStop)
   {
      PrintDebug(StringFormat("Risk: Monthly loss %.2f%% >= %.2f%%",monthLossPct,profile.monthlyLossStop));
      return false;
   }
   return true;
}

void ConfigureEquityFilter(const Preset &preset,const RiskGuardProfile &profile,const Regime regime,const int aggressiveness)
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double weekLossPct = (gWeeklyPnL<0.0 && equity>0.0 ? (-gWeeklyPnL/MathMax(1.0,equity))*100.0 : 0.0);
   double limit = ResolveAdaptiveEquityLimit(preset,profile,weekLossPct,regime,aggressiveness);
   gRiskRuntime.equityFilterActive = preset.useEquityFilter;
   if(profile.equityFilterAlwaysOn)
      gRiskRuntime.equityFilterActive = true;
   if(regime==REG_HIGH && aggressiveness==2)
      gRiskRuntime.equityFilterActive = (preset.useEquityFilter && profile.equityFilterAlwaysOn);
   gRiskRuntime.equityLimitPct = limit;
   gConfig.useEquityFilter = gRiskRuntime.equityFilterActive;
   gConfig.eqUnderwaterPct = limit;
}

bool RiskGuardsAllowTrade(const Preset &preset,const RiskGuardProfile &profile,const Regime regime,const int aggressiveness,double &outRiskScale)
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity<=0.0)
      equity = AccountInfoDouble(ACCOUNT_BALANCE);
   if(!CoolingOffOk())
   {
      PrintDebug("Risk: cooling off");
      return false;
   }
   if(!EvaluateRiskStops(profile,equity))
      return false;

   ConfigureEquityFilter(preset,profile,regime,aggressiveness);

   outRiskScale = 1.0;
   if(profile.equityFilterAdaptive && gWeeklyPnL<0.0)
   {
      double stress = MathMin(1.0,MathMax(0.0,(-gWeeklyPnL/MathMax(1.0,equity))/profile.weeklyLossStop));
      outRiskScale = Clamp(1.0 - 0.5*stress,0.4,1.0);
   }
   gRiskRuntime.riskScale = outRiskScale;
   return true;
}

bool EquityFilterAllowsTrade()
{
   if(!gRiskRuntime.equityFilterActive)
      return true;
   if(gRiskRuntime.equityLimitPct>=1e5)
      return true;
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity<=0.0)
      return true;
   double ema = eqEMA;
   if(ema<=0.0)
      return true;
   double drawdown = 100.0*(ema-equity)/MathMax(1.0,ema);
   if(drawdown<=gRiskRuntime.equityLimitPct)
      return true;
   PrintDebug(StringFormat("Risk: Equity filter drawdown %.2f%% > %.2f%%",drawdown,gRiskRuntime.equityLimitPct));
   return false;
}

#endif // __EA_RISKGUARDS_MQH__
