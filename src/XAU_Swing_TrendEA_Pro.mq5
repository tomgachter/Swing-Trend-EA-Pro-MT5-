//+------------------------------------------------------------------+
//| XAU_Swing_TrendEA_Pro.mq5                                        |
//| Swing-trading Expert Advisor for XAUUSD                          |
//+------------------------------------------------------------------+
#property strict

#include "modules/TesterCompat.mqh"

#include "modules/EAGlobals.mqh"
#include "modules/MarketUtils.mqh"
#include "modules/Accounting.mqh"
#include "modules/TradeManagement.mqh"

void ReportMonthlyPerformance(void);
void ReportTesterDiagnostics(void);
void ReportTradeCorrelations(void);

int OnInit()
{
   gStartupTime = TimeCurrent();
   ApplyPreset(InpPresetSelection);
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

   if(gConfig.useEquityFilter)
   {
      double a=MathMax(0.0,MathMin(1.0,gConfig.eqEmaAlpha));
      if(eqEMA<=0.0)
         eqEMA=equity;
      else
         eqEMA = a*equity + (1.0-a)*eqEMA;
   }

   if(!IsNewBar(gConfig.tfEntry))
   {
      ManagePosition();
      return;
   }

   if((int)(TimeCurrent()/86400)!=daySerialAnchor)
      ResetDailyAnchors();

   ManagePosition();

   datetime now = TimeCurrent();
   datetime adjusted = now + gConfig.tzOffsetHours*3600;
   MqlDateTime localStruct;
   TimeToStruct(adjusted,localStruct);
   int dayOfMonth = localStruct.day;

   double minAdxThreshold = gConfig.minAdxH4;
   double breakoutAtrFrac = InpBreakoutBufferATR;
   double guardRiskScale   = 1.0;
   if(!CanOpenNewTrade(equity,dayOfMonth,gTradesThisMonth,gTradesThisWeek,gMonthlyPnL,gWeeklyPnL,
                       gLosingDaysStreak,now,minAdxThreshold,breakoutAtrFrac,guardRiskScale))
   {
      PrintDebug("Gate: Guard");
      return;
   }

   gRiskScale = MathMax(0.2,MathMin(1.0,guardRiskScale));

   if(!CoolingOffOk())
   {
      PrintDebug("Gate: CoolingOff");
      return;
   }

   if(gConfig.useSessionBias && !SessionOk())
   {
      PrintDebug("Gate: Session");
      return;
   }

   if(InpNoMondayMorning)
   {
      int dow = localStruct.day_of_week;
      if(dow==1 && localStruct.hour<12)
      {
      PrintDebug("Gate: MondayMorning");
      return;
   }
   }

   if(!NewsFilterOk())
   {
      PrintDebug("Gate: News");
      return;
   }

   if(FridayFlatWindow())
   {
      PrintDebug("Gate: FridayFlat");
      return;
   }

   int spread=0;
   if(!SpreadOK(spread))
   {
      PrintDebug(StringFormat("Gate: Spread=%d",spread));
      return;
   }

   double dayLoss,dd;
   if(!RiskOK(dayLoss,dd))
   {
      PrintDebug(StringFormat("Gate: Risk DL=%.2f DD=%.2f",dayLoss,dd));
      return;
   }

   if(gConfig.useEquityFilter && !EquityFilterOk(dayOfMonth,gTradesThisMonth))
   {
      PrintDebug("Gate: EqFilter");
      return;
   }

   double atrD1pts=0.0;
   if(!RegimeOK(atrD1pts))
   {
      PrintDebug("Gate: regime");
      return;
   }

   double adx=0.0;
   if(!ADX_OK(adx,minAdxThreshold))
   {
      PrintDebug("Gate: ADX");
      return;
   }

   int dir=TrendDirection();
   if(dir==0)
   {
      PrintDebug("Gate: Trend");
      return;
   }

   if(!HTFConfirmOk(dir))
   {
      PrintDebug("Gate: HTFConfirm");
      return;
   }

   if(gConfig.useSlopeFilter && !SlopeOkRelaxed(hEMA_E,gConfig.useClosedBarTrend?1:0,dir,adx,minAdxThreshold))
   {
      PrintDebug("Gate: Slope");
      return;
   }

   double distATR=0.0;
   if(!ExtensionOk(distATR))
   {
      PrintDebug(StringFormat("Gate: Extension=%.2fATR",distATR));
      return;
   }

   if(!CooldownOk())
   {
      PrintDebug("Gate: Cooldown");
      return;
   }

   if(OpenPositionsByMagic()>=gConfig.maxOpenPositions)
   {
      PrintDebug("Gate: MaxPositions");
      return;
   }

   int donBars=0;
   double slMult=0.0,tpMult=0.0;
   GetRegimeFactors(atrD1pts,donBars,slMult,tpMult);

   double pt=0.0;
   if(!GetSymbolDouble(SYMBOL_POINT,pt,"point") || pt<=0.0)
      return;

   double bid=0.0,ask=0.0;
   if(!GetBidAsk(bid,ask))
      return;

   bool trigger=false;
   ENUM_ORDER_TYPE orderType = (dir>0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);

   if(gConfig.entryMode==ENTRY_PULLBACK)
   {
      double ema1,ema2,c1,c2;
      if(!CopyAt(hEMA_E,0,1,ema1,"EMA entry") || !CopyAt(hEMA_E,0,2,ema2,"EMA entry") ||
         !CopyCloseAt(gConfig.symbol,gConfig.tfEntry,1,c1,"Close pullback") || !CopyCloseAt(gConfig.symbol,gConfig.tfEntry,2,c2,"Close pullback"))
         return;

      if(dir>0 && c2<ema2 && c1>ema1)
         trigger=true;
      if(dir<0 && c2>ema2 && c1<ema1)
         trigger=true;
   }
   else if(gConfig.entryMode==ENTRY_BREAKOUT || gConfig.entryMode==ENTRY_HYBRID)
   {
      double hi,lo;
      if(!DonchianHL(gConfig.symbol,gConfig.tfEntry,MathMax(2,donBars),hi,lo))
         return;

      double atrEntry=0.0;
      double atrPts=0.0;
      bool   atrReady=false;
      if(CopyAt(hATR_Entry,0,1,atrEntry,"ATR breakout") && atrEntry>0.0)
      {
         atrPts = atrEntry/pt;
         if(atrPts>0.0)
            atrReady=true;
      }

      double bufferPts=gConfig.breakoutBufferPts;
      if(atrReady)
      {
         double atrBufferPts = breakoutAtrFrac*atrPts;
         bufferPts = MathMax(bufferPts,atrBufferPts);
      }

      double buyTrig  = hi + bufferPts*pt;
      double sellTrig = lo - bufferPts*pt;

      if(dir>0 && ask>buyTrig)
         trigger=true;
      if(dir<0 && bid<sellTrig)
         trigger=true;

      if(!trigger && gConfig.entryMode==ENTRY_HYBRID)
      {
         double ema1,ema2,c1,c2;
         if(CopyAt(hEMA_E,0,1,ema1,"EMA hybrid") && CopyAt(hEMA_E,0,2,ema2,"EMA hybrid") &&
            CopyCloseAt(gConfig.symbol,gConfig.tfEntry,1,c1,"Close hybrid") && CopyCloseAt(gConfig.symbol,gConfig.tfEntry,2,c2,"Close hybrid"))
         {
            if(dir>0 && c2<ema2 && c1>ema1)
               trigger=true;
            if(dir<0 && c2>ema2 && c1<ema1)
               trigger=true;
         }
      }
   }

   if(trigger)
      EnterTrade(orderType,false);
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
   double pf      = (double)TesterStatistics(STAT_PROFIT_FACTOR);
   double eqdd    = (double)TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
   double trades  = (double)TesterStatistics(STAT_TRADES);
   double sharpe  = (double)TesterStatistics(STAT_SHARPE_RATIO);
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
      endTime = (datetime)TesterStatistics(STAT_LAST_TRADE_TIME);
   datetime startTime = (datetime)TesterStatistics(STAT_START_TRADE_TIME);
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
