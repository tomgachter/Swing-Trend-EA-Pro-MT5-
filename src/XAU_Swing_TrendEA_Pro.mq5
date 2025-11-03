//+------------------------------------------------------------------+
//| XAU_Swing_TrendEA_Pro.mq5                                        |
//| Swing-trading Expert Advisor for XAUUSD                          |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>

CTrade trade;

//+------------------------------------------------------------------+
//| Input parameters                                                 |
//+------------------------------------------------------------------+
input string            InpSymbol               = "XAUUSD";        // Trading symbol

//--- Timeframes
input ENUM_TIMEFRAMES   InpTF_Entry             = PERIOD_H1;       // Entry timeframe
input ENUM_TIMEFRAMES   InpTF_TrailATR          = PERIOD_H4;       // ATR timeframe for stops and trailing
input ENUM_TIMEFRAMES   InpTF_Trend1            = PERIOD_H4;       // Trend vote 1 timeframe
input ENUM_TIMEFRAMES   InpTF_Trend2            = PERIOD_D1;       // Trend vote 2 timeframe
input ENUM_TIMEFRAMES   InpTF_Trend3            = PERIOD_W1;       // Trend vote 3 timeframe

//--- Trend filters
input int               InpEMA_Entry_Period     = 20;              // Entry EMA period
input int               InpEMA_Trend1_Period    = 34;              // H4 trend EMA period
input int               InpEMA_Trend2_Period    = 34;              // D1 trend EMA period
input int               InpEMA_Trend3_Period    = 50;              // W1 trend EMA period
input int               InpTrendVotesRequired   = 2;               // Votes required for bias
input bool              InpUseClosedBarTrend    = true;            // Use closed bars for trend votes
input bool              InpUseSlopeFilter       = false;           // Optional EMA slope filter

//--- Entry mode
enum EntryMode { ENTRY_BREAKOUT=0, ENTRY_PULLBACK=1, ENTRY_HYBRID=2 };
input EntryMode         InpEntryMode            = ENTRY_HYBRID;    // Entry execution mode

//--- Donchian breakout
input int               InpDonchianBars_Base    = 12;              // Base Donchian channel length
input double            InpDonchianBars_MinMax  = 8.0;             // Min/max deviation from base
input double            InpBreakoutBufferPts    = 6.0;             // Breakout buffer in points

//--- Regime controls
input int               InpATR_D1_Period        = 14;              // ATR period for D1 regime
input double            InpATR_D1_MinPts        = 4000.0;          // Minimum D1 ATR in points
input double            InpATR_D1_MaxPts        = 45000.0;         // Maximum D1 ATR in points
input double            InpATR_D1_Pivot         = 12000.0;         // Pivot D1 ATR for scaling
input double            InpRegimeMinFactor      = 0.80;            // Minimum scaling factor
input double            InpRegimeMaxFactor      = 1.40;            // Maximum scaling factor
input int               InpADX_Period           = 14;              // ADX period (H4)
input double            InpMinADX_H4            = 15.0;            // Minimum ADX threshold

//--- Stops and targets
input int               InpATR_Period           = 14;              // ATR period for SL/TP (H4)
input double            InpATR_SL_mult_Base     = 2.6;             // Base ATR multiple for SL
input double            InpATR_TP_mult_Base     = 3.6;             // Base ATR multiple for TP

//--- Position management
input int               InpMinHoldBars          = 6;               // Minimum bars before management
input double            InpBreakEven_ATR        = 1.0;             // ATR to reach before BE move
input double            InpPartialClose_R       = 2.0;             // R multiple to trigger partial close
input double            InpPartialClose_Pct     = 50.0;            // Percentage closed at partial target

//--- Trailing options
enum TrailingMode { TRAIL_OFF=0, TRAIL_ATR=1, TRAIL_FRACTAL=2 };
input TrailingMode      InpTrailingMode         = TRAIL_ATR;       // Trailing mode
input double            InpATR_Trail_mult       = 1.0;             // ATR multiple for trailing
input int               InpFractal_ShiftBars    = 2;               // Fractal shift bars

//--- Anti-noise controls
input int               InpCooldownBars         = 2;               // Bars between new entries
input double            InpMaxExtension_ATR     = 1.6;             // Maximum distance from EMA in ATR

//--- Session filters
input bool              InpUseSessionBias       = false;           // Restrict entries to sessions
input int               InpSess1_StartHour      = 7;               // Session 1 start (UTC)
input int               InpSess1_EndHour        = 12;              // Session 1 end (UTC)
input int               InpSess2_StartHour      = 13;              // Session 2 start (UTC)
input int               InpSess2_EndHour        = 22;              // Session 2 end (UTC)
input int               InpTZ_OffsetHours       = 0;               // Broker time offset vs UTC

//--- Pyramiding
input bool              InpUsePyramiding        = true;            // Enable add-on positions
input int               InpMaxAddonsPerBase     = 2;               // Maximum add-ons per base trade
input double            InpAddonStep_ATR        = 0.8;             // ATR distance per add-on
input double            InpAddonLotFactor       = 0.6;             // Lot multiplier for add-ons

//--- Equity filter
input bool              InpUseEquityFilter      = true;            // Enable equity curve filter
input double            InpEqEMA_Alpha          = 0.06;            // EMA alpha for equity filter
input double            InpEqUnderwaterPct      = 1.0;             // Allowed equity drawdown vs EMA

//--- Position sizing and limits
input bool              InpUseFixedLots         = false;           // Use fixed lot size
input double            InpFixedLots            = 0.50;            // Fixed lot size
input double            InpRiskPerTradePct      = 0.80;            // Risk per trade (% of balance)
input int               InpMaxOpenPositions     = 3;               // Maximum simultaneous positions

//--- Risk guards
input double            InpMaxDailyLossPct      = 5.0;             // Daily loss guard (% of equity)
input double            InpMaxDrawdownPct       = 10.0;            // Equity drawdown guard (%)
input int               InpMaxSpreadPoints      = 600;             // Maximum allowed spread (points)

//--- Magic number and debug
input int               InpMagic                = 11235813;        // Magic number for trades
input bool              InpDebug                = true;            // Enable debug logging

//+------------------------------------------------------------------+
//| State                                                            |
//+------------------------------------------------------------------+
datetime   lastBarTime              = 0;
datetime   lastEntryBarTime         = 0;
bool       didPartialClose          = false;
double     dayStartEquity           = 0.0;
double     equityPeak               = 0.0;
int        daySerialAnchor          = -1;
double     eqEMA                    = 0.0;
double     lastBaseOpenPrice        = 0.0;
double     lastBaseLots             = 0.0;
int        addonsOpened             = 0;
// Stores the most recent valid D1 ATR regime measurement for management fallbacks.
double     lastValidAtrD1Pts        = InpATR_D1_Pivot;

//+------------------------------------------------------------------+
//| Indicator handles                                                |
//+------------------------------------------------------------------+
int        hATR_H4                  = INVALID_HANDLE;
int        hATR_D1                  = INVALID_HANDLE;
int        hATR_Entry               = INVALID_HANDLE;
int        hEMA_E                   = INVALID_HANDLE;
int        hEMA_T1                  = INVALID_HANDLE;
int        hEMA_T2                  = INVALID_HANDLE;
int        hEMA_T3                  = INVALID_HANDLE;
int        hADX_H4                  = INVALID_HANDLE;
int        hFractals                = INVALID_HANDLE;

#include "modules\\MarketUtils.mqh"
#include "modules\\TradeManagement.mqh"

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
