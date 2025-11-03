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

//+------------------------------------------------------------------+
//| Forward declarations                                             |
//+------------------------------------------------------------------+
void       PrintDebug(const string text);
bool       GetSymbolDouble(const ENUM_SYMBOL_INFO_DOUBLE prop,double &value,const string tag);
bool       GetSymbolInteger(const ENUM_SYMBOL_INFO_INTEGER prop,long &value,const string tag);
bool       GetBidAsk(double &bid,double &ask);
bool       GetVolumeLimits(double &minVol,double &maxVol,double &step);
double     NormalizeLots(double lots);

bool       IsNewBar(const ENUM_TIMEFRAMES tf);
bool       CopyAt(const int handle,const int buffer,const int shift,double &value,const string tag="");
bool       CopyCloseAt(const string symbol,const ENUM_TIMEFRAMES tf,const int shift,double &value,const string tag="");
bool       SpreadOK(int &spread);
bool       RiskOK(double &dayLoss,double &dd);
bool       RegimeOK(double &atrD1pts);
bool       ADX_OK(double &adxOut);
bool       DonchianHL(const string symbol,const ENUM_TIMEFRAMES tf,const int bars,double &hi,double &lo);
int        TrendDirection(void);
bool       SlopeOkRelaxed(const int handle,const int shift,const int dir,const double adxH4);
bool       ExtensionOk(double &distATR);
bool       CooldownOk(void);
int        OpenPositionsByMagic(void);
void       EnterTrade(const ENUM_ORDER_TYPE type,const bool isAddon=false);
double     CalcRiskLots(const double slPrice,const ENUM_ORDER_TYPE type,const bool isAddon=false);
void       ManagePosition(void);
int        BarsSinceOpen(void);
void       ResetDailyAnchors(void);
bool       SessionOk(void);
int        AdjustedHour(const MqlDateTime &t);
bool       EquityFilterOk(void);
void       GetRegimeFactors(const double atrD1pts,int &donchianBars,double &slMult,double &tpMult);
void       TryOpenAddonIfEligible(void);

//+------------------------------------------------------------------+
//| Utility helpers                                                  |
//+------------------------------------------------------------------+
void PrintDebug(const string text)
{
   if(InpDebug)
      Print(text);
}

bool GetSymbolDouble(const ENUM_SYMBOL_INFO_DOUBLE prop,double &value,const string tag)
{
   if(SymbolInfoDouble(InpSymbol,prop,value))
      return true;
   if(InpDebug)
      PrintFormat("SymbolInfoDouble failed [%s] prop=%d err=%d",tag,(int)prop,_LastError);
   return false;
}

bool GetSymbolInteger(const ENUM_SYMBOL_INFO_INTEGER prop,long &value,const string tag)
{
   if(SymbolInfoInteger(InpSymbol,prop,value))
      return true;
   if(InpDebug)
      PrintFormat("SymbolInfoInteger failed [%s] prop=%d err=%d",tag,(int)prop,_LastError);
   return false;
}

bool GetBidAsk(double &bid,double &ask)
{
   if(!GetSymbolDouble(SYMBOL_BID,bid,"bid") || !GetSymbolDouble(SYMBOL_ASK,ask,"ask"))
      return false;
   if(bid<=0.0 || ask<=0.0)
   {
      PrintDebug("Bid/Ask invalid");
      return false;
   }
   return true;
}

bool GetVolumeLimits(double &minVol,double &maxVol,double &step)
{
   if(!GetSymbolDouble(SYMBOL_VOLUME_MIN,minVol,"vol_min") ||
      !GetSymbolDouble(SYMBOL_VOLUME_MAX,maxVol,"vol_max") ||
      !GetSymbolDouble(SYMBOL_VOLUME_STEP,step,"vol_step"))
      return false;
   return true;
}

double NormalizeLots(double lots)
{
   double minVol,maxVol,step;
   if(!GetVolumeLimits(minVol,maxVol,step))
      return 0.0;
   if(step>0.0)
      lots=MathFloor((lots+1e-12)/step)*step;
   lots=MathMax(minVol,MathMin(maxVol,lots));
   return lots;
}

//+------------------------------------------------------------------+
//| Framework functions                                              |
//+------------------------------------------------------------------+
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
//| Helper and gate implementations                                  |
//+------------------------------------------------------------------+
bool IsNewBar(const ENUM_TIMEFRAMES tf)
{
   MqlRates rates[];
   ArraySetAsSeries(rates,true);
   if(CopyRates(InpSymbol,tf,0,2,rates)<2)
   {
      PrintDebug("CopyRates failed in IsNewBar");
      return false;
   }

   if(lastBarTime==rates[0].time)
      return false;

   lastBarTime=rates[0].time;
   return true;
}

bool CopyAt(const int handle,const int buffer,const int shift,double &value,const string tag)
{
   value=0.0;
   if(handle==INVALID_HANDLE)
   {
      PrintDebug(StringFormat("CopyAt invalid handle [%s]",tag));
      return false;
   }

   double data[];
   int copied=CopyBuffer(handle,buffer,shift,1,data);
   if(copied!=1)
   {
      if(InpDebug)
         PrintFormat("CopyBuffer failed [%s] handle=%d buf=%d shift=%d err=%d",tag,handle,buffer,shift,_LastError);
      return false;
   }

   value=data[0];
   return true;
}

bool CopyCloseAt(const string symbol,const ENUM_TIMEFRAMES tf,const int shift,double &value,const string tag)
{
   value=0.0;
   double closes[];
   int copied=CopyClose(symbol,tf,shift,1,closes);
   if(copied!=1)
   {
      if(InpDebug)
         PrintFormat("CopyClose failed [%s] shift=%d err=%d",tag,shift,_LastError);
      return false;
   }
   value=closes[0];
   return true;
}

bool SpreadOK(int &spread)
{
   spread=0;
   long raw=0;
   if(!GetSymbolInteger(SYMBOL_SPREAD,raw,"spread"))
      return false;
   spread=(int)raw;
   return (spread<=InpMaxSpreadPoints);
}

bool RiskOK(double &dayLoss,double &dd)
{
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   if(dayStartEquity<=0.0)
      dayStartEquity=equity;
   if(equityPeak<=0.0)
      equityPeak=equity;

   dayLoss = 100.0*(dayStartEquity-equity)/MathMax(1.0,dayStartEquity);
   dd      = 100.0*(equityPeak-equity)/MathMax(1.0,equityPeak);

   if(dayLoss>=InpMaxDailyLossPct)
      return false;
   if(dd>=InpMaxDrawdownPct)
      return false;
   return true;
}

bool RegimeOK(double &atrD1pts)
{
   atrD1pts=0.0;
   double point=0.0;
   if(!GetSymbolDouble(SYMBOL_POINT,point,"point") || point<=0.0)
      return false;

   double atr=0.0;
   if(!CopyAt(hATR_D1,0,0,atr,"ATR D1") || atr<=0.0)
      return false;

   atrD1pts = atr/point;
   if(atrD1pts<InpATR_D1_MinPts || atrD1pts>InpATR_D1_MaxPts)
      return false;

   return true;
}

bool ADX_OK(double &adxOut)
{
   adxOut=0.0;
   if(!CopyAt(hADX_H4,0,1,adxOut,"ADX"))
      return false;
   return (adxOut>=InpMinADX_H4);
}

bool DonchianHL(const string symbol,const ENUM_TIMEFRAMES tf,const int bars,double &hi,double &lo)
{
   hi=0.0;
   lo=0.0;
   if(bars<=0)
      return false;

   MqlRates rates[];
   ArraySetAsSeries(rates,true);
   int copied=CopyRates(symbol,tf,1,bars,rates);
   if(copied<bars)
   {
      if(InpDebug)
         PrintFormat("CopyRates failed for Donchian bars=%d got=%d err=%d",bars,copied,_LastError);
      return false;
   }

   hi=rates[0].high;
   lo=rates[0].low;
   for(int i=1;i<bars;i++)
   {
      if(rates[i].high>hi)
         hi=rates[i].high;
      if(rates[i].low<lo)
         lo=rates[i].low;
   }
   return true;
}

int TrendDirection(void)
{
   int shift=InpUseClosedBarTrend?1:0;
   double ma1,ma2,ma3,p1,p2,p3;
   if(!CopyAt(hEMA_T1,0,shift,ma1,"EMA trend1")) return 0;
   if(!CopyAt(hEMA_T2,0,shift,ma2,"EMA trend2")) return 0;
   if(!CopyAt(hEMA_T3,0,shift,ma3,"EMA trend3")) return 0;
   if(!CopyCloseAt(InpSymbol,InpTF_Trend1,shift,p1,"Close trend1")) return 0;
   if(!CopyCloseAt(InpSymbol,InpTF_Trend2,shift,p2,"Close trend2")) return 0;
   if(!CopyCloseAt(InpSymbol,InpTF_Trend3,shift,p3,"Close trend3")) return 0;

   int up=0,down=0;
   if(p1>ma1) up++; else if(p1<ma1) down++;
   if(p2>ma2) up++; else if(p2<ma2) down++;
   if(p3>ma3) up++; else if(p3<ma3) down++;

   int need=MathMax(1,MathMin(3,InpTrendVotesRequired));
   if(up>=need && down<need)
      return +1;
   if(down>=need && up<need)
      return -1;
   return 0;
}

bool SlopeOkRelaxed(const int handle,const int shift,const int dir,const double adxH4)
{
   if(!InpUseSlopeFilter)
      return true;

   double a,b;
   if(!CopyAt(handle,0,shift,a,"Slope a") || !CopyAt(handle,0,shift+1,b,"Slope b"))
      return false;

   double slope=a-b;
   if(dir>0 && slope<=0.0)
      return (adxH4>=25.0);
   if(dir<0 && slope>=0.0)
      return (adxH4>=25.0);
   return true;
}

bool ExtensionOk(double &distATR)
{
   distATR=0.0;
   double ema=0.0,close=0.0;
   if(!CopyAt(hEMA_E,0,1,ema,"EMA extension") || !CopyCloseAt(InpSymbol,InpTF_Entry,1,close,"Close extension"))
      return true;

   double point=0.0;
   if(!GetSymbolDouble(SYMBOL_POINT,point,"point") || point<=0.0)
      return true;

   double atr=0.0;
   if(!CopyAt(hATR_Entry,0,1,atr,"ATR entry") || atr<=0.0)
      return true;

   double atrPts = atr/point;
   if(atrPts<=0.0)
      return true;

   distATR = MathAbs(close-ema)/point/atrPts;
   return (distATR<=InpMaxExtension_ATR);
}

bool CooldownOk(void)
{
   if(InpCooldownBars<=0 || lastEntryBarTime==0)
      return true;

   int shift=iBarShift(InpSymbol,InpTF_Entry,lastEntryBarTime,true);
   if(shift<0)
      return true;

   return (shift>=InpCooldownBars);
}

bool SessionOk(void)
{
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(),timeStruct);
   int hour=AdjustedHour(timeStruct);
   bool s1=(hour>=InpSess1_StartHour && hour<InpSess1_EndHour);
   bool s2=(hour>=InpSess2_StartHour && hour<InpSess2_EndHour);
   return (s1||s2);
}

int AdjustedHour(const MqlDateTime &t)
{
   int hour=(t.hour+InpTZ_OffsetHours)%24;
   if(hour<0)
      hour+=24;
   return hour;
}

bool EquityFilterOk(void)
{
   if(!InpUseEquityFilter)
      return true;

   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double limit = eqEMA*(1.0-InpEqUnderwaterPct/100.0);
   return (equity>=limit);
}

void GetRegimeFactors(const double atrD1pts,int &donchianBars,double &slMult,double &tpMult)
{
   double pivot = MathMax(1.0,InpATR_D1_Pivot);
   double factor = atrD1pts/pivot;
   factor = MathMin(InpRegimeMaxFactor,MathMax(InpRegimeMinFactor,factor));

   double base = InpDonchianBars_Base;
   double lower = MathMax(2.0,base-InpDonchianBars_MinMax);
   double upper = base + InpDonchianBars_MinMax;
   double scaled = base*factor;
   scaled = MathMax(lower,MathMin(upper,scaled));
   donchianBars = (int)MathRound(scaled);

   slMult = InpATR_SL_mult_Base * factor;
   tpMult = InpATR_TP_mult_Base * factor;
}

int BarsSinceOpen(void)
{
   if(!PositionSelect(InpSymbol))
      return 9999;
   datetime openTime=(datetime)PositionGetInteger(POSITION_TIME);
   int shift=iBarShift(InpSymbol,InpTF_Entry,openTime,true);
   return (shift<0?9999:shift);
}

void ResetDailyAnchors(void)
{
   daySerialAnchor = (int)(TimeCurrent()/86400);
   dayStartEquity  = AccountInfoDouble(ACCOUNT_EQUITY);
}

int OpenPositionsByMagic(void)
{
   int count=0;
   for(int i=PositionsTotal()-1;i>=0;--i)
   {
      ulong ticket=PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL)!=InpSymbol)
         continue;
      if((int)PositionGetInteger(POSITION_MAGIC)!=InpMagic)
         continue;
      count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| Trade entry and sizing                                           |
//+------------------------------------------------------------------+
void EnterTrade(const ENUM_ORDER_TYPE type,const bool isAddon)
{
   if(OpenPositionsByMagic()>=InpMaxOpenPositions)
      return;

   double point=0.0;
   if(!GetSymbolDouble(SYMBOL_POINT,point,"point") || point<=0.0)
      return;

   double bid=0.0,ask=0.0;
   if(!GetBidAsk(bid,ask))
      return;

   double atrD1pts=0.0;
   if(!RegimeOK(atrD1pts))
   {
      PrintDebug("Enter: regime not ready");
      return;
   }

   int donBars=0;
   double slMult=0.0,tpMult=0.0;
   GetRegimeFactors(atrD1pts,donBars,slMult,tpMult);

   double atr=0.0;
   if(!CopyAt(hATR_H4,0,0,atr,"ATR H4") || atr<=0.0)
   {
      PrintDebug("Enter: ATR(H4) not ready");
      return;
   }

   double atrPts=atr/point;
   double price = (type==ORDER_TYPE_BUY ? ask : bid);
   double slPts = slMult*atrPts;
   double tpPts = tpMult*atrPts;

   double sl = (type==ORDER_TYPE_BUY ? price - slPts*point : price + slPts*point);
   double tp = (type==ORDER_TYPE_BUY ? price + tpPts*point : price - tpPts*point);

   double lots = CalcRiskLots(sl,type,isAddon);
   lots = NormalizeLots(lots);
   if(lots<=0.0)
      return;

   trade.SetDeviationInPoints(30);
   const string comment = isAddon ? "XAU_Swing_ADD" : "XAU_Swing_BASE";
   if(trade.PositionOpen(InpSymbol,type,lots,price,sl,tp,comment))
   {
      lastEntryBarTime = lastBarTime;
      didPartialClose  = false;
      if(!isAddon)
      {
         lastBaseOpenPrice = price;
         lastBaseLots      = lots;
         addonsOpened      = 0;
      }
      else
      {
         addonsOpened++;
      }
      PrintDebug(isAddon?"Addon opened":"Base opened");
   }
   else
   {
      PrintDebug(StringFormat("Enter failed err=%d",_LastError));
   }
}

double CalcRiskLots(const double slPrice,const ENUM_ORDER_TYPE type,const bool isAddon)
{
   if(InpUseFixedLots)
   {
      double base=InpFixedLots;
      return (isAddon ? base*InpAddonLotFactor : base);
   }

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmt = balance*(InpRiskPerTradePct/100.0);

   double bid=0.0,ask=0.0;
   if(!GetBidAsk(bid,ask))
      return 0.0;

   double price = (type==ORDER_TYPE_BUY ? ask : bid);

   double tickValue=0.0,tickSize=0.0;
   if(!GetSymbolDouble(SYMBOL_TRADE_TICK_VALUE,tickValue,"tick_value") ||
      !GetSymbolDouble(SYMBOL_TRADE_TICK_SIZE,tickSize,"tick_size"))
      return 0.0;

   double distance = MathAbs(price-slPrice);
   if(distance<=0.0 || tickSize<=0.0 || tickValue<=0.0)
      return 0.0;

   double lots = riskAmt / ((distance/tickSize)*tickValue);
   if(isAddon)
      lots*=InpAddonLotFactor;

   return lots;
}

//+------------------------------------------------------------------+
//| Trade management                                                 |
//+------------------------------------------------------------------+
void ManagePosition(void)
{
   TryOpenAddonIfEligible();

   if(!PositionSelect(InpSymbol))
      return;

   if(BarsSinceOpen()<InpMinHoldBars)
      return;

   double point=0.0;
   if(!GetSymbolDouble(SYMBOL_POINT,point,"point") || point<=0.0)
      return;

   double atr=0.0;
   if(!CopyAt(hATR_H4,0,0,atr,"ATR H4 manage") || atr<=0.0)
      return;

   double atrPts=atr/point;

   long type=PositionGetInteger(POSITION_TYPE);
   double curSL=PositionGetDouble(POSITION_SL);
   double curTP=PositionGetDouble(POSITION_TP);
   double openPrice=PositionGetDouble(POSITION_PRICE_OPEN);
   double volume=PositionGetDouble(POSITION_VOLUME);

   double adx=0.0;
   bool adxPass = ADX_OK(adx);
   bool adxAvailable = (adxPass || adx>0.0);
   int trendDir = TrendDirection();

   bool closeByTrend=false;
   if(trendDir!=0)
   {
      if(type==POSITION_TYPE_BUY && trendDir<0)
         closeByTrend=true;
      else if(type==POSITION_TYPE_SELL && trendDir>0)
         closeByTrend=true;
   }

   bool closeByAdx = (adxAvailable && adx<InpMinADX_H4);
   if(closeByTrend || closeByAdx)
   {
      if(trade.PositionClose(InpSymbol))
      {
         didPartialClose   = false;
         addonsOpened      = 0;
         lastBaseOpenPrice = 0.0;
         lastBaseLots      = 0.0;
      }
      return;
   }

   double bid=0.0,ask=0.0;
   if(!GetBidAsk(bid,ask))
      return;
   double mid=(bid+ask)*0.5;

   double beDist=InpBreakEven_ATR*atrPts;
   if(type==POSITION_TYPE_BUY)
   {
      double progress=(mid-openPrice)/point;
      if((curSL==0.0 || curSL<openPrice) && progress>=beDist)
      {
         trade.PositionModify(InpSymbol,openPrice,curTP);
      }
   }
   else if(type==POSITION_TYPE_SELL)
   {
      double progress=(openPrice-mid)/point;
      if((curSL==0.0 || curSL>openPrice) && progress>=beDist)
      {
         trade.PositionModify(InpSymbol,openPrice,curTP);
      }
   }

   double atrD1pts=0.0;
   if(!RegimeOK(atrD1pts))
      return;

   int dummyBars=0;
   double slMult=0.0,tpMult=0.0;
   GetRegimeFactors(atrD1pts,dummyBars,slMult,tpMult);

   double riskPts = slMult*atrPts;
   if(!didPartialClose && InpPartialClose_Pct>0.0 && riskPts>0.0)
   {
      double rMultiple = (type==POSITION_TYPE_BUY ? (mid-openPrice)/(riskPts*point) : (openPrice-mid)/(riskPts*point));
      if(rMultiple>=InpPartialClose_R)
      {
         double minVol,maxVol,step;
         if(GetVolumeLimits(minVol,maxVol,step))
         {
            double closeVol = volume*(InpPartialClose_Pct/100.0);
            if(step>0.0)
               closeVol=MathFloor((closeVol+1e-12)/step)*step;
            if(closeVol>=minVol && closeVol<volume)
            {
               if(trade.PositionClosePartial(InpSymbol,closeVol))
                  didPartialClose=true;
            }
         }
      }
   }

   if(InpTrailingMode==TRAIL_ATR)
   {
      double trailDist=InpATR_Trail_mult*atrPts*point;
      if(type==POSITION_TYPE_BUY)
      {
         double proposed=bid-trailDist;
         double newSL=(curSL==0.0?proposed:MathMax(curSL,proposed));
         if(newSL>curSL)
            trade.PositionModify(InpSymbol,newSL,curTP);
      }
      else if(type==POSITION_TYPE_SELL)
      {
         double proposed=ask+trailDist;
         double newSL=(curSL==0.0?proposed:MathMin(curSL,proposed));
         if(newSL<curSL || curSL==0.0)
            trade.PositionModify(InpSymbol,newSL,curTP);
      }
   }
   else if(InpTrailingMode==TRAIL_FRACTAL)
   {
      double up[],dn[];
      ArraySetAsSeries(up,true);
      ArraySetAsSeries(dn,true);
      if(CopyBuffer(hFractals,0,2+InpFractal_ShiftBars,1,up)==1 &&
         CopyBuffer(hFractals,1,2+InpFractal_ShiftBars,1,dn)==1)
      {
         if(type==POSITION_TYPE_BUY && dn[0]>0.0)
         {
            double newSL=(curSL==0.0?dn[0]:MathMax(curSL,dn[0]));
            if(newSL>curSL)
               trade.PositionModify(InpSymbol,newSL,curTP);
         }
         if(type==POSITION_TYPE_SELL && up[0]>0.0)
         {
            double newSL=(curSL==0.0?up[0]:MathMin(curSL,up[0]));
            if(newSL<curSL || curSL==0.0)
               trade.PositionModify(InpSymbol,newSL,curTP);
         }
      }
   }
}

void TryOpenAddonIfEligible(void)
{
   if(!InpUsePyramiding)
      return;
   if(addonsOpened>=InpMaxAddonsPerBase)
      return;
   if(OpenPositionsByMagic()>=InpMaxOpenPositions)
      return;

   if(!PositionSelect(InpSymbol))
      return;

   if(lastBaseOpenPrice<=0.0 || lastBaseLots<=0.0)
      return;

   long type=PositionGetInteger(POSITION_TYPE);
   double curSL=PositionGetDouble(POSITION_SL);
   double openPrice=PositionGetDouble(POSITION_PRICE_OPEN);

   bool atBE=(type==POSITION_TYPE_BUY ? (curSL>=openPrice && curSL!=0.0) : (curSL!=0.0 && curSL<=openPrice));
   if(!atBE)
      return;

   double point=0.0;
   if(!GetSymbolDouble(SYMBOL_POINT,point,"point") || point<=0.0)
      return;

   double atr=0.0;
   if(!CopyAt(hATR_H4,0,0,atr,"ATR H4 addon") || atr<=0.0)
      return;

   double atrPts=atr/point;
   double bid=0.0,ask=0.0;
   if(!GetBidAsk(bid,ask))
      return;

   double stepDist = InpAddonStep_ATR*atrPts*point;

   if(type==POSITION_TYPE_BUY)
   {
      if((ask-lastBaseOpenPrice) >= (addonsOpened+1)*stepDist)
         EnterTrade(ORDER_TYPE_BUY,true);
   }
   else if(type==POSITION_TYPE_SELL)
   {
      if((lastBaseOpenPrice-bid) >= (addonsOpened+1)*stepDist)
         EnterTrade(ORDER_TYPE_SELL,true);
   }
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
//+------------------------------------------------------------------+
