//+------------------------------------------------------------------+
//| XAU_Swing_TrendEA_Pro.mq5                                        |
//| Swing-trading Expert Advisor for XAUUSD                          |
//+------------------------------------------------------------------+
#property strict

#include "modules/TesterCompat.mqh"

#include "modules/EAGlobals.mqh"
#include "modules/MarketUtils.mqh"
#include "modules/TradeManagement.mqh"

int OnInit()
{
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

   if(!CoolingOffOk())
   {
      PrintDebug("Gate: cooling off");
      return;
   }

   if(gConfig.useSessionBias && !SessionOk())
   {
      PrintDebug("Gate: session bias");
      return;
   }

   if(!NewsFilterOk())
   {
      PrintDebug("Gate: news filter");
      return;
   }

   if(FridayFlatWindow())
   {
      PrintDebug("Gate: Friday flat window");
      return;
   }

   int spread=0;
   if(!SpreadOK(spread))
   {
      PrintDebug(StringFormat("Gate: spread %d",spread));
      return;
   }

   double dayLoss,dd;
   if(!RiskOK(dayLoss,dd))
   {
      PrintDebug(StringFormat("Gate: risk DL=%.2f DD=%.2f",dayLoss,dd));
      return;
   }

   if(gConfig.useEquityFilter && !EquityFilterOk())
   {
      PrintDebug("Gate: equity filter");
      return;
   }

   double atrD1pts=0.0;
   if(!RegimeOK(atrD1pts))
   {
      PrintDebug("Gate: regime");
      return;
   }

   double adx=0.0;
   if(!ADX_OK(adx))
   {
      PrintDebug("Gate: ADX");
      return;
   }

   int dir=TrendDirection();
   if(dir==0)
   {
      PrintDebug("Gate: trend votes");
      return;
   }

   if(!HTFConfirmOk(dir))
   {
      PrintDebug("Gate: HTF confirm");
      return;
   }

   if(gConfig.useSlopeFilter && !SlopeOkRelaxed(hEMA_E,gConfig.useClosedBarTrend?1:0,dir,adx))
   {
      PrintDebug("Gate: slope");
      return;
   }

   double distATR=0.0;
   if(!ExtensionOk(distATR))
   {
      PrintDebug(StringFormat("Gate: extension %.2f ATR",distATR));
      return;
   }

   if(!CooldownOk())
   {
      PrintDebug("Gate: cooldown");
      return;
   }

   if(OpenPositionsByMagic()>=gConfig.maxOpenPositions)
   {
      PrintDebug("Gate: max positions");
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
         double atrBufferPts = InpBreakoutBufferATR*atrPts;
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

//+------------------------------------------------------------------+
//| OnTester                                                         |
//+------------------------------------------------------------------+
double OnTester()
{
   double pf      = (double)TesterStatistics(STAT_PROFIT_FACTOR);
   double eqdd    = (double)TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
   double trades  = (double)TesterStatistics(STAT_TRADES);
   double sharpe  = (double)TesterStatistics(STAT_SHARPE_RATIO);
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
