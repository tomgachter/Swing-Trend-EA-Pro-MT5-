//+------------------------------------------------------------------+
//|                                                 XAU_Swing_TrendEA |
//|      ATR/trend/news gated Expert Advisor for XAUUSD (H1)         |
//+------------------------------------------------------------------+
#property version   "2.0"
#property strict

#include <Trade/Trade.mqh>
#include "modules/CalendarBridge.mqh"

// --- Legacy public inputs (kept for compatibility) -----------------
input double        RiskPerTradePercent      = 0.50;  // % of equity per trade
input double        MaxDailyLossPercent      = 5.00;  // realised + open loss cap per day in %
input double        MaxStaticDrawdownPercent = 12.00; // static equity DD kill switch (<=0 disables)
input bool          AllowLongs               = true;  // enable long trades
input bool          AllowShorts              = true;  // enable short trades
#ifdef LEGACY_COMPAT
// Legacy-only inputs retained for backward compatibility with old setfiles.
input int           SessionStartHour         = 7;     // Legacy placeholder (unused)
input int           SessionEndHour           = 14;    // Legacy placeholder (unused)
input int           BiasMode                 = 1;     // Legacy placeholder (unused)
input int           RRProfile                = 1;     // Legacy placeholder (unused)
input bool          EnableFallbackEntries    = true;  // Legacy placeholder (unused)
#endif
input bool          AllowMondayTrading       = true;
input bool          AllowTuesdayTrading      = true;
input bool          AllowWednesdayTrading    = true;
input bool          AllowThursdayTrading     = true;
input bool          AllowFridayTrading       = true;
input double        MondayRiskScale          = 0.65;
input double        TuesdayRiskScale         = 1.00;
input double        WednesdayRiskScale       = 0.85;
input double        ThursdayRiskScale        = 0.90;
input double        FridayRiskScale          = 0.75;
input bool          RestrictEntryHours       = true;
input int           AllowedEntryHourStart    = 9;
input int           AllowedEntryHourEnd      = 12;

// --- New ATR risk inputs -------------------------------------------
input int           ATR_Period               = 14;
input double        ATR_SL_Mult              = 1.2;
input double        ATR_TP_Mult              = 2.2;
input double        Breakeven_ATR            = 0.8;
input double        Trail_ATR_Step           = 0.25;

// --- Trend / Regime inputs ----------------------------------------
input int           EMAfast                  = 50;
input int           EMAslow                  = 200;
input bool          UseTrendFilter           = true;
input int           ADX_Period               = 14;
input double        ADX_MinTrend             = 18.0;
input double        ADX_MaxMR                = 12.0;

// --- Session & news gating inputs ----------------------------------
input double        StartHour                = 10.0;  // broker time decimal hour
input double        EndHour                  = 11.5;  // broker time decimal hour
input bool          UseNewsFilter            = true;
input int           MaxSpreadPoints          = 200;

// --- Dynamic weekday weighting -------------------------------------
input int           NWeeks                   = 12;

// --- Session risk guard --------------------------------------------
input int           MaxLosingTradesPerDay    = 2;
input double        MaxRPerDay               = -1.0;

// --- Time based exits ----------------------------------------------
input int           NoProgressMinutes        = 120;
input double        MinProgressR             = 0.3;
input double        EarlyMAE_R               = 0.7;
input int           EarlyMAE_Minutes         = 45;

// --- Safety ---------------------------------------------------------
input int           MagicBase                = 20241026; // Base magic seed (derived per symbol/TF)

const string  TRADE_COMMENT = "XAU_Swing_TrendEA_Pro";
const ENUM_TIMEFRAMES WORK_TF = PERIOD_H1;
const ENUM_TIMEFRAMES CONFIRM_TF = PERIOD_H4;

class PositionMeta
{
public:
   ulong    ticket;
   double   riskMoney;
   double   initialStop;
   double   atrAtEntry;
   datetime entryTime;
   bool     movedToBE;
   double   minR;
};

struct WeekdayStats
{
   double expectancy;
   int    trades;
};

CTrade gTrader;
ulong gExpertMagic = 0;
int gAtrHandle = INVALID_HANDLE;
int gEmaFastH1 = INVALID_HANDLE;
int gEmaSlowH1 = INVALID_HANDLE;
int gEmaFastH4 = INVALID_HANDLE;
int gEmaSlowH4 = INVALID_HANDLE;
int gAdxHandle = INVALID_HANDLE;
datetime gLastBarTime = 0;
datetime gCurrentDay = 0;
double gDayStartEquity = 0.0;
double gInitialEquity = 0.0;
bool   gDailyLossHalt = false;
int    gLosingTradesToday = 0;
double gSumRToday = 0.0;
double gFallbackWeights[7];
bool   gUseDynamicWeights = false;
WeekdayStats gWeekdayStats[7];
string gLastBlockReason = "";

struct PositionMetaArray
{
   PositionMeta data[];
   int IndexOf(const ulong ticket) const
   {
      for(int i=0;i<ArraySize(data);i++)
         if(data[i].ticket==ticket)
            return i;
      return -1;
   }
   PositionMeta* Get(const ulong ticket)
   {
      int idx = IndexOf(ticket);
      if(idx<0)
         return NULL;
      return &data[idx];
   }
   void Ensure(const ulong ticket,const double riskMoney,const double atr,const datetime entry,const double stop)
   {
      if(IndexOf(ticket)>=0)
         return;
      PositionMeta meta;
      meta.ticket = ticket;
      meta.riskMoney = riskMoney;
      meta.atrAtEntry = atr;
      meta.entryTime = entry;
      meta.initialStop = stop;
      meta.movedToBE = false;
      meta.minR = 0.0;
      int newSize = ArraySize(data)+1;
      ArrayResize(data,newSize);
      data[newSize-1] = meta;
   }
   void Remove(const ulong ticket)
   {
      int idx = IndexOf(ticket);
      if(idx<0)
         return;
      int last = ArraySize(data)-1;
      if(idx!=last)
         data[idx] = data[last];
      ArrayResize(data,last);
   }
} gMeta;

// Forward declarations
bool AllowedToTradeNow();
bool AllowedToTradeNowInternal(string &reason);
bool TrendUp();
bool TrendDown();
bool NewsBlockActive();
double CalcATR();
double CalcPositionSizeByRisk(const double entryPrice,const double stopPrice,const int direction);
void UpdateStops(const ulong ticket);
void UpdateRiskCountersOnClose(const double profit,const double riskMoney);
void ManageOpenPositions();
void ApplyTimeExits(const ulong ticket);
void EvaluateSignals();
bool TryOpenPositionWithCooldown(const int direction,const double volume,const double entryPrice,const double sl,const double tp);
bool HasOpenPosition();
void UpdateWeekdayExpectancies();
void CloseAllPositions();
ulong DerivedMagic(const string symbol,const ENUM_TIMEFRAMES tf,const int magicBase);

// Utility helpers ----------------------------------------------------
double DecimalHourToMinutes(const double hour)
{
   double minutes = hour*60.0;
   return MathMax(0.0,MathMin(1439.0,minutes));
}

// Derive a deterministic magic number per symbol/timeframe to avoid collisions.
ulong DerivedMagic(const string symbol,const ENUM_TIMEFRAMES tf,const int magicBase)
{
   return (ulong)(magicBase + (int)tf*100 + (int)StringGetCharacter(symbol,0));
}

void RefreshFallbackWeights()
{
   ArrayInitialize(gFallbackWeights,1.0);
   gFallbackWeights[1] = MathMax(0.0,MondayRiskScale);
   gFallbackWeights[2] = MathMax(0.0,TuesdayRiskScale);
   gFallbackWeights[3] = MathMax(0.0,WednesdayRiskScale);
   gFallbackWeights[4] = MathMax(0.0,ThursdayRiskScale);
   gFallbackWeights[5] = MathMax(0.0,FridayRiskScale);
}

void ResetDayState()
{
   gCurrentDay = TimeCurrent();
   gDayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   gDailyLossHalt = false;
   gLosingTradesToday = 0;
   gSumRToday = 0.0;
}

bool IsNewTradingDay(const datetime now)
{
   if(gCurrentDay==0)
      return true;
   MqlDateTime dtNow,dtPrev;
   TimeToStruct(now,dtNow);
   TimeToStruct(gCurrentDay,dtPrev);
   return (dtNow.day!=dtPrev.day || dtNow.mon!=dtPrev.mon || dtNow.year!=dtPrev.year);
}

bool InitIndicators()
{
   gAtrHandle = iATR(_Symbol,WORK_TF,ATR_Period);
   gEmaFastH1 = iMA(_Symbol,WORK_TF,EMAfast,0,MODE_EMA,PRICE_CLOSE);
   gEmaSlowH1 = iMA(_Symbol,WORK_TF,EMAslow,0,MODE_EMA,PRICE_CLOSE);
   gEmaFastH4 = iMA(_Symbol,CONFIRM_TF,EMAfast,0,MODE_EMA,PRICE_CLOSE);
   gEmaSlowH4 = iMA(_Symbol,CONFIRM_TF,EMAslow,0,MODE_EMA,PRICE_CLOSE);
   gAdxHandle = iADX(_Symbol,WORK_TF,ADX_Period);
   return (gAtrHandle!=INVALID_HANDLE && gEmaFastH1!=INVALID_HANDLE &&
           gEmaSlowH1!=INVALID_HANDLE && gEmaFastH4!=INVALID_HANDLE &&
           gEmaSlowH4!=INVALID_HANDLE && gAdxHandle!=INVALID_HANDLE);
}

void ReleaseIndicators()
{
   if(gAtrHandle!=INVALID_HANDLE)   IndicatorRelease(gAtrHandle);
   if(gEmaFastH1!=INVALID_HANDLE)   IndicatorRelease(gEmaFastH1);
   if(gEmaSlowH1!=INVALID_HANDLE)   IndicatorRelease(gEmaSlowH1);
   if(gEmaFastH4!=INVALID_HANDLE)   IndicatorRelease(gEmaFastH4);
   if(gEmaSlowH4!=INVALID_HANDLE)   IndicatorRelease(gEmaSlowH4);
   if(gAdxHandle!=INVALID_HANDLE)   IndicatorRelease(gAdxHandle);
}

int OnInit()
{
   if(MagicBase==0)
   {
      Print("MagicBase must be non-zero to derive a unique magic number.");
      return INIT_PARAMETERS_INCORRECT;
   }
   const string tradeSymbol = _Symbol; // Always trade the chart symbol.
   // Derive a deterministic magic based on the traded symbol and the working timeframe.
   gExpertMagic = DerivedMagic(tradeSymbol,WORK_TF,MagicBase);
   gTrader.SetExpertMagicNumber(gExpertMagic);
   gTrader.SetDeviationInPoints(80);
   gInitialEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   RefreshFallbackWeights();
   if(!InitIndicators())
   {
      Print("Indicator init failed");
      return INIT_FAILED;
   }
#if EA_CALENDAR_SUPPORTED==0
   if(UseNewsFilter)
      Print("WARNING: News filter enabled, but calendar not supported on this terminal. News filter is inactive.");
#endif
   ResetDayState();
   gLastBarTime = 0;
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   ReleaseIndicators();
}

bool IsNewBar()
{
   datetime currentBar = iTime(_Symbol,WORK_TF,0);
   if(currentBar==0)
      return false;
   if(currentBar==gLastBarTime)
      return false;
   if(currentBar<gLastBarTime)
      return false;
   gLastBarTime = currentBar;
   return true;
}

void OnTick()
{
   datetime now = TimeCurrent();
   if(IsNewTradingDay(now))
   {
      UpdateWeekdayExpectancies();
      ResetDayState();
   }

   ManageOpenPositions();

   if(!IsNewBar())
      return;

   EvaluateSignals();
}

void SyncPositionMeta()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol)
         continue;
      if(PositionGetInteger(POSITION_MAGIC)!=(long)gExpertMagic)
         continue;
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double stop = PositionGetDouble(POSITION_SL);
      if(stop<=0.0)
         continue;
      double stopDistance = MathAbs(entry-stop);
      double tickValue = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
      double tickSize = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
      double volume = PositionGetDouble(POSITION_VOLUME);
      double riskPerLot = (tickSize>0.0 ? stopDistance/tickSize*tickValue : 0.0);
      double riskMoney = riskPerLot*volume;
      datetime entryTime = (datetime)PositionGetInteger(POSITION_TIME);
      gMeta.Ensure(ticket,riskMoney,CalcATR(),entryTime,stop);
   }
}

void ManageOpenPositions()
{
   SyncPositionMeta();
   if(PositionsTotal()==0)
      return; // Fast exit when nothing is open.
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol)
         continue;
      if(PositionGetInteger(POSITION_MAGIC)!=(long)gExpertMagic)
         continue;
      // Only manage positions that belong to this EA instance (symbol + derived magic).
      UpdateStops(ticket);
      ApplyTimeExits(ticket);
   }
}

void ApplyTimeExits(const ulong ticket)
{
   PositionMeta *meta = gMeta.Get(ticket);
   if(meta==NULL)
      return;
   double profit = PositionGetDouble(POSITION_PROFIT);
   double rNow = (meta.riskMoney>0.0 ? profit/meta.riskMoney : 0.0);
   meta.minR = MathMin(meta.minR,rNow);
   double minutesInTrade = (TimeCurrent()-meta.entryTime)/60.0;
   if(minutesInTrade>=NoProgressMinutes && rNow<MinProgressR)
   {
      PrintFormat("Time exit: %.2fR after %.0f minutes",rNow,minutesInTrade);
      gTrader.PositionClose(ticket);
      return;
   }
   if(minutesInTrade<=EarlyMAE_Minutes && meta.minR<=-EarlyMAE_R)
   {
      PrintFormat("Early MAE exit: %.2fR",meta.minR);
      gTrader.PositionClose(ticket);
   }
}

bool TryOpenPositionWithCooldown(const int direction,const double volume,const double entryPrice,const double sl,const double tp)
{
   static datetime lastFailTime = 0;
   static int lastFailCode = 0;

   // Avoid spamming margin-related requests for a while after a failure.
   if(lastFailCode==ERR_NOT_ENOUGH_MONEY && (TimeCurrent()-lastFailTime)<3600)
   {
      Print("Skip entry due to recent ERR_NOT_ENOUGH_MONEY");
      return false;
   }

   bool ok = (direction>0 ? gTrader.Buy(volume,_Symbol,entryPrice,sl,tp,TRADE_COMMENT)
                          : gTrader.Sell(volume,_Symbol,entryPrice,sl,tp,TRADE_COMMENT));
   if(!ok)
   {
      lastFailTime = TimeCurrent();
      lastFailCode = GetLastError();
      PrintFormat("Entry failed (%d) at %s",lastFailCode,TimeToString(lastFailTime,TIME_DATE|TIME_SECONDS));
   }
   else
   {
      lastFailCode = 0;
   }

   return ok;
}

void EvaluateSignals()
{
   if(!AllowedToTradeNow())
      return;
   if(HasOpenPosition())
      return;

   double closes[];
   ArrayResize(closes,3);
   ArraySetAsSeries(closes,true);
   if(CopyClose(_Symbol,WORK_TF,1,3,closes)<3)
      return;
   double highs[];
   double lows[];
   ArrayResize(highs,3);
   ArrayResize(lows,3);
   ArraySetAsSeries(highs,true);
   ArraySetAsSeries(lows,true);
   if(CopyHigh(_Symbol,WORK_TF,1,3,highs)<3)
      return;
   if(CopyLow(_Symbol,WORK_TF,1,3,lows)<3)
      return;

   bool upTrend = TrendUp();
   bool downTrend = TrendDown();
   double adx=0.0;
   double adxBuf[1];
   if(CopyBuffer(gAdxHandle,0,0,1,adxBuf)>0)
      adx = adxBuf[0];
   bool strongTrend = (adx>=ADX_MinTrend || ADX_MinTrend<=0.0);
   bool allowCounter = (adx<=ADX_MaxMR);

   int direction = 0;
   if(UseTrendFilter)
   {
      if(upTrend && strongTrend && AllowLongs && closes[0]>highs[1])
         direction = 1;
      else if(downTrend && strongTrend && AllowShorts && closes[0]<lows[1])
         direction = -1;
      else if(allowCounter)
      {
         double emaFast[1];
         CopyBuffer(gEmaFastH1,0,0,1,emaFast);
         if(!upTrend && AllowLongs && closes[0]>emaFast[0])
            direction = 1;
         else if(!downTrend && AllowShorts && closes[0]<emaFast[0])
            direction = -1;
      }
   }
   else
   {
      if(AllowLongs && closes[0]>highs[1])
         direction = 1;
      else if(AllowShorts && closes[0]<lows[1])
         direction = -1;
   }

   if(direction==0)
      return;

   double atr = CalcATR();
   if(atr<=0.0)
      return;
   double entryPrice = (direction>0 ? SymbolInfoDouble(_Symbol,SYMBOL_ASK) : SymbolInfoDouble(_Symbol,SYMBOL_BID));
   double sl = (direction>0 ? entryPrice-atr*ATR_SL_Mult : entryPrice+atr*ATR_SL_Mult);
   double tp = (direction>0 ? entryPrice+atr*ATR_TP_Mult : entryPrice-atr*ATR_TP_Mult);
   double volume = CalcPositionSizeByRisk(entryPrice,sl,direction);
   if(volume<=0.0)
      return;
   bool ok = TryOpenPositionWithCooldown(direction,volume,entryPrice,sl,tp);
   if(ok)
      PrintFormat("Opened %s %.2f lots",direction>0?"BUY":"SELL",volume);
}

bool HasOpenPosition()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;
      if(PositionGetInteger(POSITION_MAGIC)!=(long)gExpertMagic)
         continue;
      if(PositionGetString(POSITION_SYMBOL)==_Symbol)
         return true;
   }
   return false;
}

bool AllowedToTradeNow()
{
   string reason="";
   bool allow = AllowedToTradeNowInternal(reason);
   if(!allow)
   {
      gLastBlockReason = reason;
      Print(reason);
      Comment(reason);
   }
   else
   {
      gLastBlockReason = "";
      Comment("Trading enabled");
   }
   return allow;
}

bool AllowedToTradeNowInternal(string &reason)
{
   datetime now = TimeCurrent();
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(MaxStaticDrawdownPercent>0.0)
   {
      double floorEquity = gInitialEquity*(1.0-MaxStaticDrawdownPercent/100.0);
      if(equity<=floorEquity)
      {
         reason = "Static DD limit";
         CloseAllPositions();
         return false;
      }
   }
   if(MaxDailyLossPercent>0.0)
   {
      double floorDaily = gDayStartEquity*(1.0-MaxDailyLossPercent/100.0);
      if(equity<=floorDaily)
      {
         gDailyLossHalt = true;
         reason = "Daily loss limit";
         CloseAllPositions();
         return false;
      }
   }
   if(gDailyLossHalt)
   {
      reason = "Daily halt";
      return false;
   }
   MqlDateTime dt;
   TimeToStruct(now,dt);
   if(dt.day_of_week==0 || dt.day_of_week==6)
   {
      reason = "Weekend";
      return false;
   }
   bool dayAllowed = ((dt.day_of_week==1 && AllowMondayTrading) ||
                      (dt.day_of_week==2 && AllowTuesdayTrading) ||
                      (dt.day_of_week==3 && AllowWednesdayTrading) ||
                      (dt.day_of_week==4 && AllowThursdayTrading) ||
                      (dt.day_of_week==5 && AllowFridayTrading));
   if(!dayAllowed)
   {
      reason = "Weekday blocked";
      return false;
   }
   if(MaxLosingTradesPerDay>0 && gLosingTradesToday>=MaxLosingTradesPerDay)
   {
      reason = "Loss count guard";
      return false;
   }
   if(gSumRToday<=MaxRPerDay)
   {
      reason = "R guard";
      return false;
   }
   if(RestrictEntryHours)
   {
      if(dt.hour<AllowedEntryHourStart || dt.hour>AllowedEntryHourEnd)
      {
         reason = "Hour whitelist";
         return false;
      }
   }
   double minute = dt.hour*60 + dt.min;
   double startMin = DecimalHourToMinutes(StartHour);
   double endMin = DecimalHourToMinutes(EndHour);
   bool sessionClosed = false;
   if(startMin<=endMin)
      sessionClosed = (minute<startMin || minute>endMin);
   else
      sessionClosed = (minute>endMin && minute<startMin); // Overnight session window
   if(sessionClosed)
   {
      reason = "Session closed";
      return false;
   }
   double bid = SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double spreadPts = (ask-bid)/_Point;
   if(spreadPts>MaxSpreadPoints)
   {
      reason = StringFormat("Spread %.1f > %d",spreadPts,MaxSpreadPoints);
      return false;
   }
   if(UseNewsFilter && NewsBlockActive())
   {
      reason = "News block";
      return false;
   }
   return true;
}

bool TrendUp()
{
   double fastH1[1],slowH1[1],fastH4[1],slowH4[1];
   if(CopyBuffer(gEmaFastH1,0,0,1,fastH1)<=0) return false;
   if(CopyBuffer(gEmaSlowH1,0,0,1,slowH1)<=0) return false;
   if(CopyBuffer(gEmaFastH4,0,0,1,fastH4)<=0) return false;
   if(CopyBuffer(gEmaSlowH4,0,0,1,slowH4)<=0) return false;
   return (fastH1[0]>slowH1[0] && fastH4[0]>slowH4[0]);
}

bool TrendDown()
{
   double fastH1[1],slowH1[1],fastH4[1],slowH4[1];
   if(CopyBuffer(gEmaFastH1,0,0,1,fastH1)<=0) return false;
   if(CopyBuffer(gEmaSlowH1,0,0,1,slowH1)<=0) return false;
   if(CopyBuffer(gEmaFastH4,0,0,1,fastH4)<=0) return false;
   if(CopyBuffer(gEmaSlowH4,0,0,1,slowH4)<=0) return false;
   return (fastH1[0]<slowH1[0] && fastH4[0]<slowH4[0]);
}

bool NewsBlockActive()
{
   if(!UseNewsFilter)
      return false;
#if EA_CALENDAR_SUPPORTED==0
   static bool warned=false;
   if(!warned)
   {
      Print("WARNING: News filter enabled, but calendar not supported on this terminal. News filter is inactive.");
      warned=true;
   }
   return false;
#else
     datetime now = TimeCurrent();
   datetime from = now-1800;
   datetime to = now+1800;
   if(!CalendarSelect(from,to))
      return false;
   MqlCalendarEvent ev;
   for(int i=0;i<CalendarEventTotal();i++)
   {
      if(!CalendarEventByIndex(i,ev))
         continue;
      if(ev.importance!=CALENDAR_IMPORTANCE_HIGH)
         continue;
      bool relevant = (ev.currency=="USD" || StringFind(StringToUpper(ev.title),"GOLD")>=0);
      if(!relevant)
         continue;
      if(ev.time>=from && ev.time<=to)
         return true;
   }
   return false;
#endif
}

double CalcATR()
{
   double buffer[1];
   if(CopyBuffer(gAtrHandle,0,0,1,buffer)<=0)
      return 0.0;
   return buffer[0];
}

void UpdateWeekdayExpectancies()
{
   datetime to = TimeCurrent();
   datetime from = to - (datetime)(NWeeks*7*86400);
   if(!HistorySelect(from,to))
   {
      gUseDynamicWeights = false;
      return;
   }
   double profit[7];
   int trades[7];
   ArrayInitialize(profit,0.0);
   ArrayInitialize(trades,0);
   int total = HistoryDealsTotal();
   for(int i=0;i<total;i++)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(deal,DEAL_MAGIC)!=(long)gExpertMagic)
         continue;
      if(HistoryDealGetString(deal,DEAL_SYMBOL)!=_Symbol)
         continue;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal,DEAL_ENTRY)!=DEAL_ENTRY_OUT)
         continue;
      datetime exitTime = (datetime)HistoryDealGetInteger(deal,DEAL_TIME);
      MqlDateTime dt;
      TimeToStruct(exitTime,dt);
      double p = HistoryDealGetDouble(deal,DEAL_PROFIT)+
                 HistoryDealGetDouble(deal,DEAL_COMMISSION)+
                 HistoryDealGetDouble(deal,DEAL_SWAP);
      if(dt.day_of_week>=0 && dt.day_of_week<7)
      {
         profit[dt.day_of_week]+=p;
         trades[dt.day_of_week]++;
      }
   }
   int totalTrades = 0;
   double minExp = 1e9;
   double maxExp = -1e9;
   for(int d=0;d<7;d++)
   {
      gWeekdayStats[d].trades = trades[d];
      gWeekdayStats[d].expectancy = (trades[d]>0 ? profit[d]/trades[d] : 0.0);
      if(trades[d]>0)
      {
         totalTrades += trades[d];
         minExp = MathMin(minExp,gWeekdayStats[d].expectancy);
         maxExp = MathMax(maxExp,gWeekdayStats[d].expectancy);
      }
   }
   if(totalTrades<10 || minExp==1e9)
   {
      gUseDynamicWeights = false;
      return;
   }
   if(MathAbs(maxExp-minExp)<1e-6)
      maxExp = minExp+1e-6;
   gUseDynamicWeights = true;
   for(int d=0;d<7;d++)
   {
      if(gWeekdayStats[d].trades>0)
      {
         double norm = (gWeekdayStats[d].expectancy-minExp)/(maxExp-minExp);
         gWeekdayStats[d].expectancy = 0.5 + norm*(1.1-0.5);
      }
      else
         gWeekdayStats[d].expectancy = 1.0;
   }
}

double WeekdayWeight(const int dayOfWeek)
{
   if(gUseDynamicWeights)
   {
      if(dayOfWeek>=0 && dayOfWeek<7)
         return MathMax(0.5,MathMin(1.1,gWeekdayStats[dayOfWeek].expectancy));
      return 1.0;
   }
   if(dayOfWeek>=0 && dayOfWeek<7 && gFallbackWeights[dayOfWeek]>0.0)
      return gFallbackWeights[dayOfWeek];
   return 1.0;
}

double CalcPositionSizeByRisk(const double entryPrice,const double stopPrice,const int direction)
{
   double riskPercent = MathMax(0.0,RiskPerTradePercent);
   if(riskPercent<=0.0)
      return 0.0;
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(),dt);
   double weight = WeekdayWeight(dt.day_of_week);
   double riskMoney = equity*(riskPercent/100.0)*weight;
   double stopDistance = MathAbs(entryPrice-stopPrice);
   double tickValue = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tickValue<=0.0 || tickSize<=0.0 || stopDistance<=0.0)
      return 0.0;
   double riskPerLot = stopDistance/tickSize*tickValue;
   double volume = riskMoney/riskPerLot;
   double step = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   double minVol = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxVol = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   if(step<=0.0) step = 0.01;
   volume = MathFloor(volume/step)*step;
   volume = MathMax(minVol,MathMin(maxVol,volume));
   if(volume<minVol)
      return 0.0;
   int digits = (int)MathCeil(-MathLog10(step));
   return NormalizeDouble(volume,digits);
}

void UpdateStops(const ulong ticket)
{
   if(!PositionSelectByTicket(ticket))
      return;
   PositionMeta *meta = gMeta.Get(ticket);
   if(meta==NULL)
      return;
   double atr = CalcATR();
   if(atr<=0.0)
      return;
   ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double entry = PositionGetDouble(POSITION_PRICE_OPEN);
   double price = PositionGetDouble(POSITION_PRICE_CURRENT);
   double stop = PositionGetDouble(POSITION_SL);
   double move = (type==POSITION_TYPE_BUY ? price-entry : entry-price);
   double trigger = Breakeven_ATR*atr;
   if(trigger>0.0 && move>=trigger)
      meta.movedToBE = true;
   double desiredSL = stop;
   if(meta.movedToBE)
   {
      desiredSL = entry;
      double step = Trail_ATR_Step*atr;
      if(step>0.0)
      {
         if(type==POSITION_TYPE_BUY)
            desiredSL = MathMax(desiredSL,price-step);
         else
            desiredSL = MathMin(desiredSL,price+step);
      }
   }
   if(type==POSITION_TYPE_BUY && desiredSL>stop+_Point)
      gTrader.PositionModify(ticket,desiredSL,PositionGetDouble(POSITION_TP));
   else if(type==POSITION_TYPE_SELL && desiredSL<stop-_Point)
      gTrader.PositionModify(ticket,desiredSL,PositionGetDouble(POSITION_TP));
}

void UpdateRiskCountersOnClose(const double profit,const double riskMoney)
{
   double r = (riskMoney>0.0 ? profit/riskMoney : 0.0);
   gSumRToday += r;
   if(profit<0.0)
      gLosingTradesToday++;
}

void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result)
{
   if(trans.type!=TRADE_TRANSACTION_DEAL_ADD)
      return;
   ulong deal = trans.deal;
   if(deal==0)
      return;
   if(HistoryDealGetInteger(deal,DEAL_MAGIC)!=(long)gExpertMagic)
      return;
   if(HistoryDealGetString(deal,DEAL_SYMBOL)!=_Symbol)
      return;
   ENUM_DEAL_ENTRY entryType = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal,DEAL_ENTRY);
   if(entryType!=DEAL_ENTRY_OUT)
      return;
   ulong positionId = (ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID);
   PositionMeta *meta = gMeta.Get(positionId);
   if(meta==NULL)
      return;
   double profit = HistoryDealGetDouble(deal,DEAL_PROFIT)+
                   HistoryDealGetDouble(deal,DEAL_COMMISSION)+
                   HistoryDealGetDouble(deal,DEAL_SWAP);
   UpdateRiskCountersOnClose(profit,meta.riskMoney);
   gMeta.Remove(positionId);
}

void CloseAllPositions()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;
      if(PositionGetInteger(POSITION_MAGIC)!=(long)gExpertMagic)
         continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol)
         continue;
      gTrader.PositionClose(ticket);
   }
}
