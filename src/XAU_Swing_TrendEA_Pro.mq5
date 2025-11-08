//+------------------------------------------------------------------+
//| XAU_Swing_TrendEA_Pro.mq5                                        |
//| Swing-trading Expert Advisor for XAUUSD                          |
//+------------------------------------------------------------------+
#property strict

#define EA_DEBUG 1

#include "modules/TesterCompat.mqh"

#include "modules/EAGlobals.mqh"
#include "modules/utils.mqh"
#include "modules/MarketUtils.mqh"
#include "modules/Accounting.mqh"
#include "modules/riskguards.mqh"
#include "modules/entries.mqh"
#include "modules/exits.mqh"
#include "modules/TradeManagement.mqh"

void ReportMonthlyPerformance(void);
void ReportTesterDiagnostics(void);
void ReportTradeCorrelations(void);

int OnInit()
{
   gStartupTime = TimeCurrent();
   ApplyPreset(InpPresetSelection);
   gRegime      = DetectRegime();
   gRiskProfile = MakeRiskGuardProfile(RiskGuardsPreset);
   gPreset      = MakePreset(Aggressiveness,gRegime,RiskGuardsPreset);
   gConfig.riskPerTradePct  = RiskPct;
   gConfig.minAdxH4         = gPreset.adxMin;
   gConfig.trendVotesRequired = gPreset.votesRequired;
   gConfig.allowPyramiding  = Pyramiding;
   gConfig.maxOpenPositions = MaxOpenPositions;
   gConfig.maxAddonsPerBase = gPreset.maxAddons;
   gConfig.addonStepAtr     = gPreset.addonStepATR;
   gConfig.useEquityFilter  = gPreset.useEquityFilter;
   gConfig.partialCloseEnable = gPreset.usePartial;
   gConfig.partialClosePct    = gPreset.partialPct;
   gConfig.partialCloseR      = gPreset.partialAtR;
   gConfig.useTimeStop        = gPreset.useTimeStop;
   gConfig.timeStopHours      = gPreset.timeStopHours;
   gConfig.useSessionBias     = gPreset.useSessionBias;
   gConfig.trailingMode       = TRAIL_CHANDELIER;
   trade.SetExpertMagicNumber(gConfig.magic);

   if(!SymbolSelect(gConfig.symbol,true))
   {
      PrintDebug("Symbol selection failed");
      return INIT_FAILED;
   }

   hATR_H4   = iATR(gConfig.symbol,gConfig.tfTrailAtr,gConfig.atrPeriod);
   hATR_D1   = iATR(gConfig.symbol,PERIOD_D1,gConfig.atrD1Period);
   hATR_Entry= iATR(gConfig.symbol,gConfig.tfEntry,14);
   hEMA_E    = iMA (gConfig.symbol,gConfig.tfEntry, gConfig.emaEntryPeriod,0,MODE_EMA,PRICE_CLOSE);
   hEMA_T1   = iMA (gConfig.symbol,gConfig.tfTrend1,gConfig.emaTrend1Period,0,MODE_EMA,PRICE_CLOSE);
   hEMA_T2   = iMA (gConfig.symbol,gConfig.tfTrend2,gConfig.emaTrend2Period,0,MODE_EMA,PRICE_CLOSE);
   hEMA_T3   = iMA (gConfig.symbol,gConfig.tfTrend3,gConfig.emaTrend3Period,0,MODE_EMA,PRICE_CLOSE);
   hADX_H4   = iADX(gConfig.symbol,gConfig.tfTrend1,gConfig.adxPeriod);
   hFractals = iFractals(gConfig.symbol,gConfig.tfEntry);

   int handles[]={hATR_H4,hATR_D1,hATR_Entry,hEMA_E,hEMA_T1,hEMA_T2,hEMA_T3,hADX_H4,hFractals};
   const string names[] = {"ATR_H4","ATR_D1","ATR_Entry","EMA_Entry","EMA_T1","EMA_T2","EMA_T3","ADX_H4","Fractals"};
   for(int i=0;i<ArraySize(handles);++i)
   {
      if(handles[i]==INVALID_HANDLE)
      {
         PrintFormat("Indicator handle failed: %s",names[i]);
         return INIT_FAILED;
      }
   }

   ResetDailyAnchors();
   InitAccountingState();
   UpdateAccounting();
   equityPeak = AccountInfoDouble(ACCOUNT_EQUITY);
   eqEMA      = equityPeak;
   lastValidAtrD1Pts = gConfig.atrD1Pivot;

   ConfigureEquityFilter(gPreset,gRiskProfile,gRegime,Aggressiveness);
   PrintDebug(StringFormat("Init regime=%s votes=%d adx=%.1f risk=%.2f%%",EnumToString(gRegime),gPreset.votesRequired,gPreset.adxMin,RiskPct));

   PrintDebug("XAU_Swing_TrendEA_Pro initialised");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   int handles[]={hATR_H4,hATR_D1,hATR_Entry,hEMA_E,hEMA_T1,hEMA_T2,hEMA_T3,hADX_H4,hFractals};
   for(int i=0;i<ArraySize(handles);++i)
   {
      if(handles[i]!=INVALID_HANDLE)
         IndicatorRelease(handles[i]);
   }
   ReportTradeCorrelations();
}

void OnTick()
{
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity>equityPeak)
      equityPeak=equity;

   UpdateAccounting();

   double a=MathMax(0.0,MathMin(1.0,gConfig.eqEmaAlpha));
   if(eqEMA<=0.0)
      eqEMA=equity;
   else
      eqEMA = a*equity + (1.0-a)*eqEMA;

   if(!IsNewBar(gConfig.tfEntry))
   {
      ManagePosition();
      return;
   }

   if((int)(TimeCurrent()/86400)!=daySerialAnchor)
      ResetDailyAnchors();

   double atrD1=0.0;
   if(CopyAt(hATR_D1,0,0,atrD1,"ATR D1 value"))
   {
      double point=SafePoint();
      if(atrD1>0.0 && point>0.0)
         lastValidAtrD1Pts = atrD1/point;
   }

   gRegime = DetectRegime();
   gPreset = MakePreset(Aggressiveness,gRegime,RiskGuardsPreset);
   gConfig.minAdxH4 = gPreset.adxMin;
   gConfig.trendVotesRequired = gPreset.votesRequired;
   gConfig.maxAddonsPerBase = gPreset.maxAddons;
   gConfig.addonStepAtr     = gPreset.addonStepATR;
   gConfig.partialCloseEnable = gPreset.usePartial;
   gConfig.partialClosePct    = gPreset.partialPct;
   gConfig.partialCloseR      = gPreset.partialAtR;
   gConfig.useTimeStop        = gPreset.useTimeStop;
   gConfig.timeStopHours      = gPreset.timeStopHours;
   gConfig.useEquityFilter    = gPreset.useEquityFilter;
   gConfig.useSessionBias     = gPreset.useSessionBias;
   ConfigureEquityFilter(gPreset,gRiskProfile,gRegime,Aggressiveness);

   ManagePosition();

   if(FridayFlatWindow())
   {
      PrintDebug("Gate: FridayFlat");
      return;
   }

   double riskScale=1.0;
   if(!RiskGuardsAllowTrade(gPreset,gRiskProfile,gRegime,Aggressiveness,riskScale))
      return;
   gRiskScale = riskScale;

   if(!EquityFilterAllowsTrade())
      return;

   if(!CooldownOk())
      return;

   int spreadLimit = gConfig.maxSpreadPoints;
   if(gRegime==REG_HIGH)
      spreadLimit = (int)MathRound(spreadLimit*1.25);
   int spread=0;
   if(!SpreadOK(spread,spreadLimit))
   {
      PrintDebug(StringFormat("Gate: Spread=%d limit=%d",spread,spreadLimit));
      return;
   }

   EntrySignal signal;
   if(!BuildEntrySignal(signal))
      return;

   ENUM_ORDER_TYPE orderType = (signal.direction>0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
   PrintDebug(StringFormat("Entry %s regime=%s adx=%.1f atrPts=%.1f",(signal.direction>0?"BUY":"SELL"),EnumToString(gRegime),signal.adxValue,signal.atrEntryPts));
   EnterTrade(orderType,false,signal);
}

void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result)
{
   HandleTradeAccounting(trans,request,result);
}

//+------------------------------------------------------------------+
//| OnTester                                                         |
//+------------------------------------------------------------------+
double OnTester()
{
   double pf      = (double)TesterStatistics((ENUM_STATISTICS)STAT_PROFIT_FACTOR);
   double eqdd    = (double)TesterStatistics((ENUM_STATISTICS)STAT_EQUITY_DDREL_PERCENT);
   double trades  = (double)TesterStatistics((ENUM_STATISTICS)STAT_TRADES);
   double sharpe  = (double)TesterStatistics((ENUM_STATISTICS)STAT_SHARPE_RATIO);
   ReportMonthlyPerformance();
   if(pf<=0.0 || trades<60.0)
      return -DBL_MAX;
   if(eqdd<=0.0)
      eqdd=0.01;
   return pf*MathMax(0.0,sharpe)/(1.0+eqdd);
}

void OnTesterDeinit()
{
   ReportTesterDiagnostics();
   ReportTradeCorrelations();
}

void ReportMonthlyPerformance(void)
{
   if(!MQLInfoInteger(MQL_TESTER))
      return;

   datetime endTime = TimeCurrent();
   if(endTime<=0)
      endTime = (datetime)TesterStatistics((ENUM_STATISTICS)STAT_LAST_TRADE_TIME);
   datetime startTime = (datetime)TesterStatistics((ENUM_STATISTICS)STAT_START_TRADE_TIME);
   if(startTime<=0 || startTime>endTime)
      startTime = 0;

   if(!HistorySelect(startTime,endTime))
      return;

   int totalDeals = HistoryDealsTotal();
   if(totalDeals<=0)
      return;

   int monthIds[];
   double monthPnls[];
   int monthTrades[];

   for(int i=0;i<totalDeals;++i)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket==0)
         continue;

      string symbol = HistoryDealGetString(ticket,DEAL_SYMBOL);
      if(symbol!=gConfig.symbol)
         continue;

      long magic = HistoryDealGetInteger(ticket,DEAL_MAGIC);
      if(magic!=gConfig.magic)
         continue;

      ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket,DEAL_ENTRY);
      if(entry!=DEAL_ENTRY_OUT && entry!=DEAL_ENTRY_OUT_BY && entry!=DEAL_ENTRY_INOUT)
         continue;

      datetime dealTime = (datetime)HistoryDealGetInteger(ticket,DEAL_TIME);
      int monthId = CurrentMonthId(dealTime);

      int idx=-1;
      for(int j=0;j<ArraySize(monthIds);++j)
      {
         if(monthIds[j]==monthId)
         {
            idx=j;
            break;
         }
      }
      if(idx<0)
      {
         idx=ArraySize(monthIds);
         ArrayResize(monthIds,idx+1);
         ArrayResize(monthPnls,idx+1);
         ArrayResize(monthTrades,idx+1);
         monthIds[idx]=monthId;
         monthPnls[idx]=0.0;
         monthTrades[idx]=0;
      }

      double profit = HistoryDealGetDouble(ticket,DEAL_PROFIT);
      double swap   = HistoryDealGetDouble(ticket,DEAL_SWAP);
      double commission = HistoryDealGetDouble(ticket,DEAL_COMMISSION);
      double netProfit = profit + swap + commission;

      monthPnls[idx]   += netProfit;
      monthTrades[idx] += 1;
   }

   int totalMonths = ArraySize(monthIds);
   if(totalMonths<=0)
      return;

   int greenMonths=0;
   int zeroMonths=0;
   double totalTrades=0.0;

   for(int i=0;i<totalMonths;++i)
   {
      if(monthPnls[i]>0.0)
         greenMonths++;
      if(MathAbs(monthPnls[i])<1e-6)
         zeroMonths++;
      totalTrades += monthTrades[i];
   }

   int order[];
   ArrayResize(order,totalMonths);
   for(int i=0;i<totalMonths;++i)
      order[i]=i;
   for(int i=0;i<totalMonths-1;++i)
   {
      for(int j=i+1;j<totalMonths;++j)
      {
         if(monthIds[order[j]]<monthIds[order[i]])
         {
            int tmp=order[i];
            order[i]=order[j];
            order[j]=tmp;
         }
      }
   }

   int currentRed=0;
   int maxRed=0;
   for(int i=0;i<totalMonths;++i)
   {
      double pnl = monthPnls[order[i]];
      if(pnl<0.0)
      {
         currentRed++;
         if(currentRed>maxRed)
            maxRed=currentRed;
      }
      else
      {
         currentRed=0;
      }
   }

   double sortedPnls[];
   ArrayCopy(sortedPnls,monthPnls);
   ArraySort(sortedPnls);

   double median=0.0;
   if(totalMonths%2==1)
      median = sortedPnls[totalMonths/2];
   else if(totalMonths>1)
      median = 0.5*(sortedPnls[totalMonths/2-1]+sortedPnls[totalMonths/2]);

   double greenPct = 100.0*((double)greenMonths/MathMax(1,totalMonths));
   double avgTrades = totalTrades/MathMax(1.0,(double)totalMonths);

   PrintFormat("Diag: GreenMonths %.1f%% | ZeroMonths %d | MaxRedMonthsInRow %d | AvgTradesPerMonth %.2f | MedianMonthlyPnL %.2f",
               greenPct,zeroMonths,maxRed,avgTrades,median);
}

void ReportTesterDiagnostics(void)
{
   if(!MQLInfoInteger(MQL_TESTER))
      return;

   double quality = TesterStatistics((ENUM_STATISTICS)STAT_MODELLING_QUALITY);
   if(quality<=0.0)
   {
      Print("Tester: modelling quality information is unavailable.");
      return;
   }

   PrintFormat("Tester: modelling quality %.2f%%",quality);
   if(quality<50.0)
   {
      const string modellingMsg = "Tester: modelling quality is very low. Download higher quality tick history in the MT5 History Center and re-run using 'Every tick based on real ticks' for reliable results.";
      Print(modellingMsg);
   }
}

void ReportTradeCorrelations(void)
{
   int total=ArraySize(completedTrades);
   if(total<5)
   {
      Print("Stats: insufficient closed trades for MFE/MAE regression.");
      return;
   }

   double sumProfit=0.0,sumProfit2=0.0;
   double sumMfe=0.0,sumMfe2=0.0,sumProfitMfe=0.0;
   double sumMae=0.0,sumMae2=0.0,sumProfitMae=0.0;

   for(int i=0;i<total;++i)
   {
      double risk = (completedTrades[i].initialRiskPts>1e-9 ? completedTrades[i].initialRiskPts : 1.0);
      double profitR = completedTrades[i].profitPts/risk;
      double mfeR    = completedTrades[i].mfePts/risk;
      double maeR    = completedTrades[i].maePts/risk;

      sumProfit+=profitR;
      sumProfit2+=profitR*profitR;
      sumMfe+=mfeR;
      sumMfe2+=mfeR*mfeR;
      sumProfitMfe+=profitR*mfeR;
      sumMae+=maeR;
      sumMae2+=maeR*maeR;
      sumProfitMae+=profitR*maeR;
   }

   double n = (double)total;
   double varProfit = (sumProfit2 - (sumProfit*sumProfit)/n)/MathMax(n-1.0,1.0);
   double varMfe    = (sumMfe2 - (sumMfe*sumMfe)/n)/MathMax(n-1.0,1.0);
   double varMae    = (sumMae2 - (sumMae*sumMae)/n)/MathMax(n-1.0,1.0);
   double covMfe    = (sumProfitMfe - (sumProfit*sumMfe)/n)/MathMax(n-1.0,1.0);
   double covMae    = (sumProfitMae - (sumProfit*sumMae)/n)/MathMax(n-1.0,1.0);

   double slopeMfe = (varMfe>1e-9 ? covMfe/varMfe : 0.0);
   double slopeMae = (varMae>1e-9 ? covMae/varMae : 0.0);

   double corrMfe = 0.0;
   if(varProfit>1e-9 && varMfe>1e-9)
      corrMfe = covMfe/MathSqrt(varProfit*varMfe);
   double corrMae = 0.0;
   if(varProfit>1e-9 && varMae>1e-9)
      corrMae = covMae/MathSqrt(varProfit*varMae);

   double r2Mfe = corrMfe*corrMfe;
   double r2Mae = corrMae*corrMae;

   PrintFormat("Stats: MFE vs Profit slope=%.3f R^2=%.3f | MAE vs Profit slope=%.3f R^2=%.3f (n=%d)",
               slopeMfe,r2Mfe,slopeMae,r2Mae,total);
}
//+------------------------------------------------------------------+
