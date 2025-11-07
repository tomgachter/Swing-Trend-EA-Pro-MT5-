//+------------------------------------------------------------------+
//|  Swing_Trend_EA_Pro_v2.mq5                                       |
//|  FTMO Swing-compliant trend-swing Expert Advisor                 |
//|  Builds on Swing Trend concepts with tighter risk governance     |
//+------------------------------------------------------------------+
#property strict
#property copyright   "Swing Trend EA Pro"
#property link        "https://example.com"

#include <Trade/Trade.mqh>

//--- input parameters -------------------------------------------------
input string            InpSymbol               = "XAUUSD";        // Trading symbol
input ENUM_TIMEFRAMES   InpTF_Entry             = PERIOD_H1;       // Entry timeframe
input ENUM_TIMEFRAMES   InpTF_SignalATR         = PERIOD_H1;       // ATR TF for entries
input ENUM_TIMEFRAMES   InpTF_StopATR           = PERIOD_H4;       // ATR TF for risk management
input ENUM_TIMEFRAMES   InpTF_Trend1            = PERIOD_H4;       // Trend vote timeframe 1
input ENUM_TIMEFRAMES   InpTF_Trend2            = PERIOD_D1;       // Trend vote timeframe 2
input ENUM_TIMEFRAMES   InpTF_Trend3            = PERIOD_W1;       // Trend vote timeframe 3

input int               InpEMA_Entry_Period     = 21;              // EMA period (entry TF)
input int               InpEMA_Trend1_Period    = 34;              // EMA period (TF1)
input int               InpEMA_Trend2_Period    = 55;              // EMA period (TF2)
input int               InpEMA_Trend3_Period    = 89;              // EMA period (TF3)
input int               InpTrendVotesRequired   = 3;               // Required aligned votes
input bool              InpUseSlopeFilter       = true;            // Use EMA slope confirmation

input int               InpATR_Period_Stop      = 14;              // ATR period for SL/TP
input int               InpATR_Period_Signal    = 14;              // ATR period for signal context
input double            InpATR_SL_mult_Base     = 3.0;             // Base ATR SL multiple
input double            InpATR_TP_mult_Base     = 3.75;            // Base ATR TP multiple
input double            InpATR_Trail_mult       = 1.7;             // ATR multiple for trailing
input double            InpBreakEven_ATR        = 1.8;             // ATR distance required before BE
input int               InpBreakEven_MinBars    = 4;               // Minimum bars before BE

input int               InpCooldownBars         = 5;               // Bars to wait between trades
input bool              InpUseSessionBias       = true;            // Enforce trading sessions
input int               InpSess1_StartHour      = 7;               // Session 1 start (broker time)
input int               InpSess1_EndHour        = 12;              // Session 1 end (broker time)
input int               InpSess2_StartHour      = 13;              // Session 2 start (broker time)
input int               InpSess2_EndHour        = 21;              // Session 2 end (broker time)
input int               InpTZ_OffsetMinutes     = 0;               // Manual offset vs server (minutes)

input double            InpRegimeMinFactor      = 0.75;            // Minimum ATR factor vs pivot
input double            InpRegimeMaxFactor      = 1.60;            // Maximum ATR factor vs pivot
input double            InpATR_D1_Pivot         = 12000.0;         // Pivot ATR value (points)
input int               InpATR_D1_Period        = 14;              // ATR period for regime filter
input int               InpADX_Period           = 14;              // ADX period (H4)
input double            InpMinADX_H4            = 22.0;            // Minimum ADX threshold

input double            InpRiskPerTradePct      = 1.0;             // Risk per trade (% equity)
input double            InpMaxDailyLossPct      = 4.0;             // Max daily loss (% equity)
input double            InpMaxTotalLossPct      = 8.0;             // Max total loss (% from equity peak)
input double            InpMaxSpreadPoints      = 400.0;           // Maximum spread allowed

input int               InpMagic                = 20240517;        // Magic number for EA
input bool              InpDebug                = true;            // Enable debug logging

//--- globals ----------------------------------------------------------
CTrade   trade;
int      hATR_Stop      = INVALID_HANDLE;
int      hATR_Signal    = INVALID_HANDLE;
int      hATR_D1        = INVALID_HANDLE;
int      hEMA_Entry     = INVALID_HANDLE;
int      hEMA_T1        = INVALID_HANDLE;
int      hEMA_T2        = INVALID_HANDLE;
int      hEMA_T3        = INVALID_HANDLE;
int      hADX_H4        = INVALID_HANDLE;

datetime g_lastBarTime      = 0;
datetime g_lastEntryBar     = 0;
datetime g_dayAnchor        = 0;
double   g_dayStartEquity   = 0.0;
double   g_equityPeak       = 0.0;

//--- helper forward declarations --------------------------------------
bool      IsNewBar();
void      ResetDailyAnchors();
bool      CheckRiskLimits();
bool      CheckSessionWindow();
int       GetTrendVote();
bool      CheckSlopeBias(const int trendDir);
bool      CheckRegimeWindow(double &atrPoints);
bool      CheckADX(double &adxValue);
bool      CheckSpread();
double    CalculateRiskLots(const ENUM_POSITION_TYPE direction,const double stopPrice);
void      OpenTrade(const int trendDir);
void      ManageTrade();
void      UpdateEquityAnchors();
void      PrintDebug(const string text);

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetAsyncMode(false);

   if(!SymbolSelect(InpSymbol,true))
   {
      PrintDebug("Symbol selection failed");
      return INIT_FAILED;
   }

   hATR_Stop   = iATR(InpSymbol,InpTF_StopATR,InpATR_Period_Stop);
   hATR_Signal = iATR(InpSymbol,InpTF_SignalATR,InpATR_Period_Signal);
   hATR_D1     = iATR(InpSymbol,PERIOD_D1,InpATR_D1_Period);
   hEMA_Entry  = iMA (InpSymbol,InpTF_Entry, InpEMA_Entry_Period,0,MODE_EMA,PRICE_CLOSE);
   hEMA_T1     = iMA (InpSymbol,InpTF_Trend1,InpEMA_Trend1_Period,0,MODE_EMA,PRICE_CLOSE);
   hEMA_T2     = iMA (InpSymbol,InpTF_Trend2,InpEMA_Trend2_Period,0,MODE_EMA,PRICE_CLOSE);
   hEMA_T3     = iMA (InpSymbol,InpTF_Trend3,InpEMA_Trend3_Period,0,MODE_EMA,PRICE_CLOSE);
   hADX_H4     = iADX(InpSymbol,InpTF_Trend1,InpADX_Period);

   int handles[]={hATR_Stop,hATR_Signal,hATR_D1,hEMA_Entry,hEMA_T1,hEMA_T2,hEMA_T3,hADX_H4};
   const string names[] = {"ATR Stop","ATR Signal","ATR D1","EMA Entry","EMA T1","EMA T2","EMA T3","ADX"};
   for(int i=0;i<ArraySize(handles);++i)
   {
      if(handles[i]==INVALID_HANDLE)
      {
         PrintDebug(StringFormat("Indicator handle failed: %s",names[i]));
         return INIT_FAILED;
      }
   }

   ResetDailyAnchors();
   g_equityPeak = AccountInfoDouble(ACCOUNT_EQUITY);

   PrintDebug("Swing_Trend_EA_Pro_v2 initialised");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   int handles[]={hATR_Stop,hATR_Signal,hATR_D1,hEMA_Entry,hEMA_T1,hEMA_T2,hEMA_T3,hADX_H4};
   for(int i=0;i<ArraySize(handles);++i)
   {
      if(handles[i]!=INVALID_HANDLE)
         IndicatorRelease(handles[i]);
   }
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   UpdateEquityAnchors();

   ManageTrade();

   if(!IsNewBar())
      return;

   if(PositionSelect(InpSymbol) && PositionGetInteger(POSITION_MAGIC)==InpMagic)
      return; // enforce single active trade

   if(!CheckRiskLimits())
      return;

   if(InpUseSessionBias && !CheckSessionWindow())
      return;

   if(!CheckSpread())
      return;

   double regimeAtr=0.0;
   if(!CheckRegimeWindow(regimeAtr))
      return;

   double adx=0.0;
   if(!CheckADX(adx))
      return;

   int trendDir=GetTrendVote();
   if(trendDir==0)
      return;

   if(InpUseSlopeFilter && !CheckSlopeBias(trendDir))
      return;

   if(g_lastEntryBar!=0)
   {
      int secondsSince = (int)(TimeCurrent() - g_lastEntryBar);
      if(secondsSince >= 0 && secondsSince < InpCooldownBars*PeriodSeconds(InpTF_Entry))
      {
         PrintDebug("Cooldown active");
         return;
      }
   }

   // Price pullback check (mean reversion entry)
   double emaEntry[]= {0.0,0.0};
   if(CopyBuffer(hEMA_Entry,0,1,2,emaEntry)!=2)
      return;

   double atrSignal[1];
   if(CopyBuffer(hATR_Signal,0,1,1,atrSignal)!=1 || atrSignal[0]<=0.0)
      return;

   double prevClose = iClose(InpSymbol,InpTF_Entry,1);
   double prevHigh  = iHigh (InpSymbol,InpTF_Entry,1);
   double prevLow   = iLow  (InpSymbol,InpTF_Entry,1);

   bool allowEntry=false;
   double pullbackThreshold = 0.25*atrSignal[0];
   if(regimeAtr>0.0)
   {
      double point=0.0;
      if(SymbolInfoDouble(InpSymbol,SYMBOL_POINT,point) && point>0.0)
      {
         double maxPullback = regimeAtr*0.5*point;
         pullbackThreshold = MathMin(pullbackThreshold,maxPullback);
      }
   }
   if(trendDir>0)
   {
      if(prevClose>emaEntry[0] && prevLow<=emaEntry[0]-pullbackThreshold)
         allowEntry=true;
   }
   else if(trendDir<0)
   {
      if(prevClose<emaEntry[0] && prevHigh>=emaEntry[0]+pullbackThreshold)
         allowEntry=true;
   }

   if(!allowEntry)
   {
      PrintDebug("Entry conditions not met");
      return;
   }

   OpenTrade(trendDir);
}

//+------------------------------------------------------------------+
//| Manage open position                                              |
//+------------------------------------------------------------------+
void ManageTrade()
{
   if(!PositionSelect(InpSymbol) || PositionGetInteger(POSITION_MAGIC)!=InpMagic)
      return;

   double atrStop[1];
   if(CopyBuffer(hATR_Stop,0,0,1,atrStop)!=1 || atrStop[0]<=0.0)
      return;

   double atrDistance=atrStop[0];

   datetime openTime=(datetime)PositionGetInteger(POSITION_TIME);
   int barsOpen = (int)((TimeCurrent()-openTime)/PeriodSeconds(InpTF_Entry));
   if(barsOpen<0)
      barsOpen=0;

   double bid=0.0,ask=0.0;
   if(!SymbolInfoDouble(InpSymbol,SYMBOL_BID,bid) || !SymbolInfoDouble(InpSymbol,SYMBOL_ASK,ask))
      return;
   double price=PositionGetDouble(POSITION_PRICE_OPEN);
   double currentSL=PositionGetDouble(POSITION_SL);
   double currentTP=PositionGetDouble(POSITION_TP);
   long   posType=PositionGetInteger(POSITION_TYPE);

   double breakEvenPrice = price;
   double beDistance     = InpBreakEven_ATR*atrDistance;

   if(posType==POSITION_TYPE_BUY)
   {
      double bidNow=0.0;
      if(!SymbolInfoDouble(InpSymbol,SYMBOL_BID,bidNow))
         return;
      double mfe=(bidNow-price);
      if((currentSL<breakEvenPrice || currentSL==0.0) && mfe>=beDistance && barsOpen>=InpBreakEven_MinBars)
      {
         trade.PositionModify(InpSymbol,breakEvenPrice,currentTP);
         PrintDebug("Break-even secured (buy)");
      }

      double trailDist = InpATR_Trail_mult*atrDistance;
      double newSL = MathMax(currentSL, bidNow-trailDist);
      if(bidNow>price && newSL>currentSL && newSL>breakEvenPrice)
      {
         trade.PositionModify(InpSymbol,newSL,currentTP);
         PrintDebug("Trailing SL updated (buy)");
      }
   }
   else if(posType==POSITION_TYPE_SELL)
   {
      double askNow=0.0;
      if(!SymbolInfoDouble(InpSymbol,SYMBOL_ASK,askNow))
         return;
      double mfe=(price-askNow);
      if((currentSL>breakEvenPrice || currentSL==0.0) && mfe>=beDistance && barsOpen>=InpBreakEven_MinBars)
      {
         trade.PositionModify(InpSymbol,breakEvenPrice,currentTP);
         PrintDebug("Break-even secured (sell)");
      }

      double trailDist = InpATR_Trail_mult*atrDistance;
      double newSL = MathMin(currentSL, askNow+trailDist);
      if(askNow<price && (currentSL==0.0 || newSL<currentSL) && newSL<breakEvenPrice)
      {
         trade.PositionModify(InpSymbol,newSL,currentTP);
         PrintDebug("Trailing SL updated (sell)");
      }
   }

   if(!CheckRiskLimits())
   {
      trade.PositionClose(InpSymbol);
      PrintDebug("Position closed due to risk limits");
   }
}

//+------------------------------------------------------------------+
//| Attempt to open new trade                                         |
//+------------------------------------------------------------------+
void OpenTrade(const int trendDir)
{
   ENUM_ORDER_TYPE orderType = (trendDir>0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
   ENUM_POSITION_TYPE posType = (trendDir>0 ? POSITION_TYPE_BUY : POSITION_TYPE_SELL);

   double price=0.0;
   if(trendDir>0)
   {
      if(!SymbolInfoDouble(InpSymbol,SYMBOL_ASK,price))
         return;
   }
   else
   {
      if(!SymbolInfoDouble(InpSymbol,SYMBOL_BID,price))
         return;
   }

   double atrStop[1];
   if(CopyBuffer(hATR_Stop,0,0,1,atrStop)!=1 || atrStop[0]<=0.0)
      return;

   double point=0.0;
   if(!SymbolInfoDouble(InpSymbol,SYMBOL_POINT,point) || point<=0.0)
      return;

   double slDistance = InpATR_SL_mult_Base*atrStop[0];
   double tpDistance = InpATR_TP_mult_Base*atrStop[0];

   double sl = (trendDir>0 ? price - slDistance : price + slDistance);
   double tp = (trendDir>0 ? price + tpDistance : price - tpDistance);

   double lots = CalculateRiskLots(posType,sl);
   if(lots<=0.0)
   {
      PrintDebug("Lot calculation failed");
      return;
   }

   trade.SetDeviationInPoints(30);
   if(trade.PositionOpen(InpSymbol,orderType,lots,price,sl,tp,"SwingTrendV2"))
   {
      g_lastEntryBar = TimeCurrent();
      PrintDebug("Trade opened");
   }
   else
   {
      PrintDebug(StringFormat("Order send failed err=%d",_LastError));
   }
}

//+------------------------------------------------------------------+
//| Calculate lot size by risk percentage                             |
//+------------------------------------------------------------------+
double CalculateRiskLots(const ENUM_POSITION_TYPE direction,const double stopPrice)
{
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double riskPct = MathMin(InpRiskPerTradePct,1.0);
   double riskAmount = equity*(riskPct/100.0);

   double tickValue=0.0,tickSize=0.0,point=0.0;
   if(!SymbolInfoDouble(InpSymbol,SYMBOL_TRADE_TICK_VALUE,tickValue) ||
      !SymbolInfoDouble(InpSymbol,SYMBOL_TRADE_TICK_SIZE,tickSize) ||
      !SymbolInfoDouble(InpSymbol,SYMBOL_POINT,point))
      return 0.0;

   if(tickValue<=0.0 || tickSize<=0.0 || point<=0.0)
      return 0.0;

   double price=0.0;
   if(direction==POSITION_TYPE_BUY)
   {
      if(!SymbolInfoDouble(InpSymbol,SYMBOL_ASK,price))
         return 0.0;
   }
   else
   {
      if(!SymbolInfoDouble(InpSymbol,SYMBOL_BID,price))
         return 0.0;
   }
   double distance = MathAbs(price-stopPrice);
   if(distance<=0.0)
      return 0.0;

   double valuePerLot = (distance/tickSize)*tickValue;
   if(valuePerLot<=0.0)
      return 0.0;

   double lots = riskAmount/valuePerLot;
   double minLot=0.0,lotStep=0.0,maxLot=0.0;
   if(!SymbolInfoDouble(InpSymbol,SYMBOL_VOLUME_MIN,minLot) ||
      !SymbolInfoDouble(InpSymbol,SYMBOL_VOLUME_STEP,lotStep) ||
      !SymbolInfoDouble(InpSymbol,SYMBOL_VOLUME_MAX,maxLot))
      return 0.0;

   if(lotStep<=0.0)
      return 0.0;

   lots = MathMax(minLot,MathMin(maxLot,MathFloor(lots/lotStep+1e-8)*lotStep));
   int lotDigits = (int)MathCeil(-MathLog10(lotStep));
   lotDigits = MathMax(lotDigits,0);
   return NormalizeDouble(lots,lotDigits);
}

//+------------------------------------------------------------------+
//| Risk limit checks                                                 |
//+------------------------------------------------------------------+
bool CheckRiskLimits()
{
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);

   if(equity>g_equityPeak)
      g_equityPeak=equity;

   double dailyLossPct = 0.0;
   if(g_dayStartEquity>0.0)
      dailyLossPct = 100.0*(g_dayStartEquity-equity)/g_dayStartEquity;

   double totalLossPct = 0.0;
   if(g_equityPeak>0.0)
      totalLossPct = 100.0*(g_equityPeak-equity)/g_equityPeak;

   bool ok = true;
   if(dailyLossPct>=InpMaxDailyLossPct-1e-4)
   {
      PrintDebug("Daily loss limit reached");
      ok=false;
   }

   if(totalLossPct>=InpMaxTotalLossPct-1e-4)
   {
      PrintDebug("Total loss limit reached");
      ok=false;
   }

   return ok;
}

//+------------------------------------------------------------------+
//| Check session window                                              |
//+------------------------------------------------------------------+
bool CheckSessionWindow()
{
   datetime serverTime=TimeTradeServer();
   if(serverTime==0)
      serverTime=TimeCurrent();

   datetime adjusted=serverTime + InpTZ_OffsetMinutes*60;
   MqlDateTime dt; TimeToStruct(adjusted,dt);

   int hour=dt.hour;
   bool inSession=false;

   if(InpSess1_StartHour<=InpSess1_EndHour)
   {
      if(hour>=InpSess1_StartHour && hour<InpSess1_EndHour)
         inSession=true;
   }

   if(InpSess2_StartHour<=InpSess2_EndHour)
   {
      if(hour>=InpSess2_StartHour && hour<InpSess2_EndHour)
         inSession=true;
   }

   if(!inSession)
      PrintDebug("Outside trading sessions");

   return inSession;
}

//+------------------------------------------------------------------+
//| Trend vote calculation                                            |
//+------------------------------------------------------------------+
int GetTrendVote()
{
   double emaEntry[2],ema1[2],ema2[2],ema3[2];
   if(CopyBuffer(hEMA_Entry,0,0,2,emaEntry)!=2) return 0;
   if(CopyBuffer(hEMA_T1,0,0,2,ema1)!=2) return 0;
   if(CopyBuffer(hEMA_T2,0,0,2,ema2)!=2) return 0;
   if(CopyBuffer(hEMA_T3,0,0,2,ema3)!=2) return 0;

   double closeEntry=iClose(InpSymbol,InpTF_Entry,0);
   double closeT1   =iClose(InpSymbol,InpTF_Trend1,0);
   double closeT2   =iClose(InpSymbol,InpTF_Trend2,0);
   double closeT3   =iClose(InpSymbol,InpTF_Trend3,0);

   int votesUp=0,votesDown=0;

   if(closeEntry>emaEntry[0]) votesUp++; else votesDown++;
   if(closeT1>ema1[0])       votesUp++; else votesDown++;
   if(closeT2>ema2[0])       votesUp++; else votesDown++;
   if(closeT3>ema3[0])       votesUp++; else votesDown++;

   int totalVotes = MathMax(votesUp,votesDown);
   if(totalVotes<InpTrendVotesRequired)
      return 0;

   return (votesUp>votesDown ? 1 : (votesDown>votesUp ? -1 : 0));
}

//+------------------------------------------------------------------+
//| EMA slope confirmation                                            |
//+------------------------------------------------------------------+
bool CheckSlopeBias(const int trendDir)
{
   const int lookback=3;
   double emaNow[lookback+1];
   if(CopyBuffer(hEMA_Entry,0,0,lookback+1,emaNow)!=lookback+1)
      return false;

   double slope=emaNow[0]-emaNow[lookback];

   if(trendDir>0 && slope<=0.0)
      return false;
   if(trendDir<0 && slope>=0.0)
      return false;

   return true;
}

//+------------------------------------------------------------------+
//| ATR regime filter                                                 |
//+------------------------------------------------------------------+
bool CheckRegimeWindow(double &atrPoints)
{
   double point=0.0;
   if(!SymbolInfoDouble(InpSymbol,SYMBOL_POINT,point) || point<=0.0)
      return false;

   double atr[1];
   if(CopyBuffer(hATR_D1,0,0,1,atr)!=1 || atr[0]<=0.0)
      return false;

   atrPoints = atr[0]/point;
   double factor = atr[0]/InpATR_D1_Pivot;

   if(factor<InpRegimeMinFactor || factor>InpRegimeMaxFactor)
   {
      PrintDebug("ATR regime filter blocked trade");
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| ADX filter                                                        |
//+------------------------------------------------------------------+
bool CheckADX(double &adxValue)
{
   double adx[1];
   if(CopyBuffer(hADX_H4,2,0,1,adx)!=1)
      return false;

   adxValue=adx[0];
   if(adxValue<InpMinADX_H4)
   {
      PrintDebug("ADX below threshold");
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Spread guard                                                      |
//+------------------------------------------------------------------+
bool CheckSpread()
{
   double tickSize=0.0;
   if(!SymbolInfoDouble(InpSymbol,SYMBOL_TRADE_TICK_SIZE,tickSize) || tickSize<=0.0)
      return false;

   double ask=0.0,bid=0.0;
   if(!SymbolInfoDouble(InpSymbol,SYMBOL_ASK,ask) || !SymbolInfoDouble(InpSymbol,SYMBOL_BID,bid))
      return false;

   double spreadPoints=(ask-bid)/tickSize;
   if(spreadPoints>InpMaxSpreadPoints)
   {
      PrintDebug("Spread too wide");
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| State helpers                                                     |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime barTime=iTime(InpSymbol,InpTF_Entry,0);
   if(barTime==0)
      return false;

   if(barTime!=g_lastBarTime)
   {
      g_lastBarTime=barTime;
      return true;
   }
   return false;
}

void ResetDailyAnchors()
{
   datetime serverTime=TimeTradeServer();
   if(serverTime==0)
      serverTime=TimeCurrent();

   MqlDateTime dt; TimeToStruct(serverTime,dt);
   dt.hour=0; dt.min=0; dt.sec=0;
   g_dayAnchor=StructToTime(dt);
   g_dayStartEquity=AccountInfoDouble(ACCOUNT_EQUITY);
}

void UpdateEquityAnchors()
{
   datetime serverTime=TimeTradeServer();
   if(serverTime==0)
      serverTime=TimeCurrent();

   if(g_dayAnchor==0 || serverTime-g_dayAnchor>=24*60*60)
      ResetDailyAnchors();
}

void PrintDebug(const string text)
{
   if(InpDebug)
      Print(StringFormat("[SwingTrendV2] %s",text));
}

//+------------------------------------------------------------------+
//| Tester statistics hook (session tracking placeholder)             |
//+------------------------------------------------------------------+
double OnTester()
{
   // Placeholder for future session performance aggregation
   return 0.0;
}

