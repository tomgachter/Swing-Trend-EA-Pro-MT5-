//+------------------------------------------------------------------+
//| XAU_Swing_TrendEA_Pro.mq5                                        |
//| Swing-trading Expert Advisor for XAUUSD                          |
//+------------------------------------------------------------------+
#property strict

#define EA_GLOBALS_IMPLEMENTATION
#include "modules/EAGlobals.mqh"
#undef EA_GLOBALS_IMPLEMENTATION

#include "modules/MarketUtils.mqh"
#include "modules/TradeManagement.mqh"

int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);

   if(!SymbolSelect(InpSymbol,true))
   {
      PrintDebug("Symbol selection failed");
      return INIT_FAILED;
   }

   hATR_H4   = iATR(InpSymbol,InpTF_TrailATR,InpATR_Period);
   hATR_D1   = iATR(InpSymbol,PERIOD_D1,InpATR_D1_Period);
   hATR_Entry= iATR(InpSymbol,InpTF_Entry,14);
   hEMA_E    = iMA (InpSymbol,InpTF_Entry, InpEMA_Entry_Period,0,MODE_EMA,PRICE_CLOSE);
   hEMA_T1   = iMA (InpSymbol,InpTF_Trend1,InpEMA_Trend1_Period,0,MODE_EMA,PRICE_CLOSE);
   hEMA_T2   = iMA (InpSymbol,InpTF_Trend2,InpEMA_Trend2_Period,0,MODE_EMA,PRICE_CLOSE);
   hEMA_T3   = iMA (InpSymbol,InpTF_Trend3,InpEMA_Trend3_Period,0,MODE_EMA,PRICE_CLOSE);
   hADX_H4   = iADX(InpSymbol,InpTF_Trend1,InpADX_Period);
   hFractals = iFractals(InpSymbol,InpTF_Entry);

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
}

void OnTick()
{
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity>equityPeak)
      equityPeak=equity;

   if(InpUseEquityFilter)
   {
      double a=MathMax(0.0,MathMin(1.0,InpEqEMA_Alpha));
      if(eqEMA<=0.0)
         eqEMA=equity;
      else
         eqEMA = a*equity + (1.0-a)*eqEMA;
   }

   if(!IsNewBar(InpTF_Entry))
   {
      ManagePosition();
      return;
   }

   if((int)(TimeCurrent()/86400)!=daySerialAnchor)
      ResetDailyAnchors();

   ManagePosition();

   if(InpUseSessionBias && !SessionOk())
   {
      PrintDebug("Gate: session bias");
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

   if(InpUseEquityFilter && !EquityFilterOk())
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

   if(InpUseSlopeFilter && !SlopeOkRelaxed(hEMA_E,InpUseClosedBarTrend?1:0,dir,adx))
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

   if(OpenPositionsByMagic()>=InpMaxOpenPositions)
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

   if(InpEntryMode==ENTRY_PULLBACK)
   {
      double ema1,ema2,c1,c2;
      if(!CopyAt(hEMA_E,0,1,ema1,"EMA entry") || !CopyAt(hEMA_E,0,2,ema2,"EMA entry") ||
         !CopyCloseAt(InpSymbol,InpTF_Entry,1,c1,"Close pullback") || !CopyCloseAt(InpSymbol,InpTF_Entry,2,c2,"Close pullback"))
         return;

      if(dir>0 && c2<ema2 && c1>ema1)
         trigger=true;
      if(dir<0 && c2>ema2 && c1<ema1)
         trigger=true;
   }
   else if(InpEntryMode==ENTRY_BREAKOUT || InpEntryMode==ENTRY_HYBRID)
   {
      double hi,lo;
      if(!DonchianHL(InpSymbol,InpTF_Entry,MathMax(2,donBars),hi,lo))
         return;

      double buyTrig  = hi + InpBreakoutBufferPts*pt;
      double sellTrig = lo - InpBreakoutBufferPts*pt;

      if(dir>0 && ask>buyTrig)
         trigger=true;
      if(dir<0 && bid<sellTrig)
         trigger=true;

      if(!trigger && InpEntryMode==ENTRY_HYBRID)
      {
         double ema1,ema2,c1,c2;
         if(CopyAt(hEMA_E,0,1,ema1,"EMA hybrid") && CopyAt(hEMA_E,0,2,ema2,"EMA hybrid") &&
            CopyCloseAt(InpSymbol,InpTF_Entry,1,c1,"Close hybrid") && CopyCloseAt(InpSymbol,InpTF_Entry,2,c2,"Close hybrid"))
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
   if(pf<=0.0 || trades<40.0)
      return -1.0;
   double ddPenalty = MathMax(0.3,1.0-(eqdd/10.0));
   double sizeBonus = MathMin(MathSqrt(trades/60.0),1.25);
   return pf*ddPenalty*sizeBonus;
}

void OnTesterDeinit()
{
   ReportTesterDiagnostics();
}

void ReportTesterDiagnostics(void)
{
   if(!MQLInfoInteger(MQL_TESTER))
      return;

   double quality = TesterStatistics(STAT_MODELLING_QUALITY);
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
//+------------------------------------------------------------------+
