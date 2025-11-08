#ifndef __EA_ACCOUNTING_MQH__
#define __EA_ACCOUNTING_MQH__

#include "EAGlobals.mqh"
#include "MarketUtils.mqh"

void InitAccountingState()
{
   gPauseUntil       = 0;
   gDailyPnL         = 0.0;
   gWeeklyPnL        = 0.0;
   gMonthlyPnL       = 0.0;
   gMonthlyR         = 0.0;
   gRiskScale        = 1.0;
   gTradesThisWeek   = 0;
   gTradesThisMonth  = 0;
   gLosingDaysStreak = 0;
   gCurrentDay       = -1;
   gCurrentWeek      = -1;
   gCurrentMonth     = -1;
}

int CurrentMonthId(const datetime whenTime)
{
   MqlDateTime t;
   TimeToStruct(whenTime,t);
   return t.year*100 + t.mon;
}

int CurrentDaySerial(const datetime whenTime)
{
   return (int)(whenTime/86400);
}

int CurrentIsoWeekId(const datetime whenTime)
{
   MqlDateTime t;
   TimeToStruct(whenTime,t);
   int wday = t.day_of_week;
   if(wday==0)
      wday=7;
   datetime thursday = whenTime + (4 - wday)*86400;
   MqlDateTime th;
   TimeToStruct(thursday,th);
   int week = (th.day_of_year-1)/7 + 1;
   return th.year*100 + week;
}

bool IsNewDayUTC(const datetime whenTime)
{
   int daySerial = CurrentDaySerial(whenTime);
   if(gCurrentDay==-1)
   {
      gCurrentDay = daySerial;
      return false;
   }
   if(daySerial!=gCurrentDay)
   {
      gCurrentDay = daySerial;
      return true;
   }
   return false;
}

bool IsNewDayUTC()
{
   return IsNewDayUTC(TimeGMT());
}

bool IsNewWeekUTC(const datetime whenTime)
{
   int weekId = CurrentIsoWeekId(whenTime);
   if(gCurrentWeek==-1)
   {
      gCurrentWeek = weekId;
      return false;
   }
   if(weekId!=gCurrentWeek)
   {
      gCurrentWeek = weekId;
      return true;
   }
   return false;
}

bool IsNewWeekUTC()
{
   return IsNewWeekUTC(TimeGMT());
}

bool IsNewMonthUTC(const datetime whenTime)
{
   int monthId = CurrentMonthId(whenTime);
   if(gCurrentMonth==-1)
   {
      gCurrentMonth = monthId;
      return false;
   }
   if(monthId!=gCurrentMonth)
   {
      gCurrentMonth = monthId;
      return true;
   }
   return false;
}

bool IsNewMonthUTC()
{
   return IsNewMonthUTC(TimeGMT());
}

void UpdateAccounting()
{
   datetime nowUtc = TimeGMT();
   if(nowUtc<=0)
      nowUtc = TimeCurrent();

   bool newMonth = IsNewMonthUTC(nowUtc);
   bool newWeek  = IsNewWeekUTC(nowUtc);
   bool newDay   = IsNewDayUTC(nowUtc);

   if(newDay)
   {
      if(gDailyPnL<0.0)
         gLosingDaysStreak++;
      else
         gLosingDaysStreak = 0;
      gDailyPnL = 0.0;
   }

   if(newWeek)
   {
      gWeeklyPnL      = 0.0;
      gTradesThisWeek = 0;
      gLosingDaysStreak = 0;
      gPauseUntil     = 0;
   }

   if(newMonth)
   {
      gMonthlyPnL      = 0.0;
      gMonthlyR        = 0.0;
      gTradesThisMonth = 0;
      gPauseUntil      = 0;
      gRiskScale       = 1.0;
   }
}

double ResolveRiskPerLot(const PositionMemo &memo)
{
   if(memo.riskPerLot>0.0)
      return memo.riskPerLot;
   double point=0.0,tickValue=0.0,tickSize=0.0;
   if(!GetSymbolDouble(SYMBOL_POINT,point,"point") || point<=0.0)
      return 0.0;
   if(!GetSymbolDouble(SYMBOL_TRADE_TICK_VALUE,tickValue,"tick_value") || tickValue<=0.0)
      return 0.0;
   if(!GetSymbolDouble(SYMBOL_TRADE_TICK_SIZE,tickSize,"tick_size") || tickSize<=0.0)
      return 0.0;
   double riskPrice = memo.initialRiskPoints*point;
   return (riskPrice/tickSize)*tickValue;
}

void HandleTradeAccounting(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result)
{
   if(trans.type!=TRADE_TRANSACTION_DEAL_ADD)
      return;

   ulong deal=trans.deal;
   if(deal==0)
      return;

   string symbol=HistoryDealGetString(deal,DEAL_SYMBOL);
   if(symbol!=gConfig.symbol)
      return;

   long magic=HistoryDealGetInteger(deal,DEAL_MAGIC);
   if(magic!=gConfig.magic)
      return;

   ENUM_DEAL_ENTRY entry=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal,DEAL_ENTRY);
   double volume = HistoryDealGetDouble(deal,DEAL_VOLUME);

   if(entry==DEAL_ENTRY_IN)
   {
      if(volume>0.0)
      {
         gTradesThisWeek++;
         gTradesThisMonth++;
      }
      return;
   }

   if(entry!=DEAL_ENTRY_OUT && entry!=DEAL_ENTRY_INOUT && entry!=DEAL_ENTRY_OUT_BY)
      return;

   double profit = HistoryDealGetDouble(deal,DEAL_PROFIT);
   double swap   = HistoryDealGetDouble(deal,DEAL_SWAP);
   double commission = HistoryDealGetDouble(deal,DEAL_COMMISSION);
   double netProfit = profit + swap + commission;

   gDailyPnL  += netProfit;
   gWeeklyPnL += netProfit;
   gMonthlyPnL+= netProfit;

   if(volume<=0.0)
      return;

   ulong positionId = (ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID);
   int memoIndex = FindMemoIndex(positionId);
   double riskPerLot = 0.0;
   if(memoIndex>=0)
      riskPerLot = ResolveRiskPerLot(positionMemos[memoIndex]);

   if(riskPerLot<=0.0)
      return;

   double riskValue = riskPerLot*volume;
   if(riskValue<=0.0)
      return;

   gMonthlyR += netProfit/riskValue;
}

double R_MTD(void)
{
   return gMonthlyR;
}

#endif // __EA_ACCOUNTING_MQH__
