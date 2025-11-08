//+------------------------------------------------------------------+
//| XAU_Swing_TrendEA_Pro.mq5                                        |
//| Refactored swing/breakout Expert Advisor for XAUUSD (MT5)        |
//| Session: 07:00-14:45, Bias votes: EMA20(H1)/EMA34(H4)/EMA50(D1)  |
//| Risk: ATR-aligned SL/TP, partial exits + ATR trailing            |
//+------------------------------------------------------------------+
#property strict

#include <Trade\Trade.mqh>

#include "modules/RegimeFilter.mqh"
#include "modules/SessionFilter.mqh"
#include "modules/BiasEngine.mqh"
#include "modules/EntryEngine.mqh"
#include "modules/Sizer.mqh"
#include "modules/BrokerUtils.mqh"
#include "modules/RiskEngine.mqh"
#include "modules/ExitEngine.mqh"

input RiskMode         InpRiskMode = RISK_PERCENT_PER_TRADE;  // Risk allocation model
input double            RiskPerTrade = 0.75;                // Percent or lots depending on mode
input double            MaxDailyRiskPercent = 5.0;          // Daily loss+open risk cap in %
input double            MaxEquityDDPercentForCloseAll = 12; // Hard equity drawdown kill switch
input ulong             MagicNumber = 20241026;             // Trade identifier
input string            TradeComment = "XAU_Swing_TrendEA_Pro";
input bool              EnableChartAnnotations = true;
input bool              RandomizeEntryExit = false;

//--- globals
BrokerUtils   gBroker;
RegimeFilter  gRegime;
SessionFilter gSession;
BiasEngine    gBias;
EntryEngine   gEntry;
PositionSizer gSizer;
RiskEngine    gRisk;
ExitEngine    gExit;

datetime      gLastBarTime = 0;

//--- helper declarations
bool IsNewBar();
void EvaluateNewBar();
void ManageOpenPositions();
bool HasDirectionalPosition(const int direction);
void AnnotateChart(const string message,const color col=clrDodgerBlue);
void AttemptEntry(const EntrySignal &signal);
void CloseAllPositions();

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   gBroker.Configure(MagicNumber,TradeComment,20);
   gEntry.Configure(RandomizeEntryExit);
   gExit.Configure(gEntry.TrailMultiplier(),15.0);
   gRisk.Configure(InpRiskMode,RiskPerTrade,MaxDailyRiskPercent,MaxEquityDDPercentForCloseAll);
   if(!gRegime.Init(_Symbol,14))
   {
      Print("Failed to initialise regime filter");
      return INIT_FAILED;
   }
   if(!gBias.Init(_Symbol))
   {
      Print("Failed to initialise bias engine");
      return INIT_FAILED;
   }
   if(!gSizer.Init(_Symbol))
   {
      Print("Failed to initialise position sizer");
      return INIT_FAILED;
   }
   gRegime.Update(true);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialisation                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
}

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
{
   gRisk.OnNewDay();
   gRegime.Update();

   if(gRisk.EquityKillSwitchTriggered())
   {
      Print("Equity drawdown kill switch triggered");
      CloseAllPositions();
      return;
   }

   ManageOpenPositions();

   if(!IsNewBar())
      return;

   EvaluateNewBar();
}

//+------------------------------------------------------------------+
//| Detect new bar                                                   |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime currentBar = iTime(_Symbol,PERIOD_H1,0);
   if(currentBar<=0)
      return false;
   if(gLastBarTime==0)
   {
      gLastBarTime = currentBar;
      return false;
   }
   if(currentBar!=gLastBarTime)
   {
      gLastBarTime = currentBar;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Evaluate entries on bar close                                    |
//+------------------------------------------------------------------+
void EvaluateNewBar()
{
   if(!gBias.Update(gRegime))
      return;

   SessionWindow window;
   datetime signalTime = gLastBarTime;
   if(!gSession.AllowsEntry(signalTime,window))
   {
      AnnotateChart("Session filter blocked entry",clrSilver);
      return;
   }

   if(HasDirectionalPosition(gBias.Direction()))
      return;

   MqlRates rates[6];
   int copied = CopyRates(_Symbol,PERIOD_H1,0,6,rates);
   if(copied<3)
      return;

   EntrySignal signal;
   if(!gEntry.Evaluate(gBias,gRegime,window,rates,copied,signal))
      return;

   AttemptEntry(signal);
}

//+------------------------------------------------------------------+
//| Manage open positions                                            |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   gExit.Manage(gBroker,gSizer,gRegime);
}

//+------------------------------------------------------------------+
//| Check for open position in direction                             |
//+------------------------------------------------------------------+
bool HasDirectionalPosition(const int direction)
{
   if(direction==0)
      return true;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol)
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=MagicNumber)
         continue;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Attempt to open trade                                            |
//+------------------------------------------------------------------+
void AttemptEntry(const EntrySignal &signal)
{
   double stopPoints = gSizer.StopDistancePoints(signal.entryPrice,signal.stopLoss);
   if(stopPoints<=0.0)
      return;

   double volume=0.0;
   double riskPercent=0.0;
   if(!gRisk.AllowNewTrade(stopPoints,gSizer,volume,riskPercent))
   {
      AnnotateChart("Risk guard prevented entry",clrTomato);
      return;
   }

   double tp = 0.0; // trailing handles final exit
   if(!gBroker.OpenPosition(signal.direction,volume,signal.entryPrice,signal.stopLoss,tp))
   {
      PrintFormat("Order open failed for direction %d",signal.direction);
      return;
   }

   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol)
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=MagicNumber)
         continue;
      gExit.Register(ticket,signal,stopPoints,volume,riskPercent);
      gRisk.OnTradeOpened(riskPercent);
      AnnotateChart(StringFormat("Opened %s %.2flots",signal.direction>0?"BUY":"SELL",volume),clrGreen);
      break;
   }
}

//+------------------------------------------------------------------+
//| Chart annotation helper                                          |
//+------------------------------------------------------------------+
void AnnotateChart(const string message,const color col)
{
   if(!EnableChartAnnotations)
      return;
   Comment(message);
}

//+------------------------------------------------------------------+
//| Close all positions                                              |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol)
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=MagicNumber)
         continue;
      gBroker.ClosePosition(ticket);
   }
}

//+------------------------------------------------------------------+
//| Trade transaction                                                |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result)
{
   if(trans.type==TRADE_TRANSACTION_DEAL_ADD && trans.deal>0)
   {
      ulong deal = trans.deal;
      ENUM_DEAL_ENTRY entryType = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal,DEAL_ENTRY);
      double profit = HistoryDealGetDouble(deal,DEAL_PROFIT);
      ulong positionId = (ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID);
      if(entryType==DEAL_ENTRY_OUT)
      {
         double riskRemoved = 0.0;
         if(!PositionSelectByTicket(positionId))
            riskRemoved = gExit.OnPositionClosed(positionId);
         gRisk.OnTradeClosed(profit,riskRemoved);
      }
   }
}

//+------------------------------------------------------------------+
//| OnTester acceptance checks                                       |
//+------------------------------------------------------------------+
double OnTester()
{
   double trades = TesterStatistics((ENUM_STATISTICS)STAT_TRADES);
   double winTrades = TesterStatistics((ENUM_STATISTICS)STAT_PROFIT_TRADES);
   double profitFactor = TesterStatistics((ENUM_STATISTICS)STAT_PROFIT_FACTOR);
   double maxDD = TesterStatistics((ENUM_STATISTICS)STAT_EQUITY_DDRELATIVE);
   double sharpe = TesterStatistics((ENUM_STATISTICS)STAT_SHARPE_RATIO);
   double avgHoldHours = TesterStatistics((ENUM_STATISTICS)STAT_AVG_HOLD_TIME)/3600.0;
   double equityCorr = TesterStatistics((ENUM_STATISTICS)STAT_LINEAR_CORRELATION_EQUITY);
   double winRate = (trades>0.0 ? winTrades/trades*100.0 : 0.0);

   bool pass=true;
   if(trades<2500 || trades>3400) pass=false;
   if(winRate<49.0 || winRate>53.0) pass=false;
   if(profitFactor<1.26 || profitFactor>1.36) pass=false;
   if(maxDD>12.0) pass=false;
   if(sharpe<1.6 || sharpe>2.4) pass=false;
   if(avgHoldHours<6.0 || avgHoldHours>10.0) pass=false;
   if(equityCorr<0.80) pass=false;

   PrintFormat("Tester summary: trades=%.0f winRate=%.2f%% PF=%.2f DD=%.2f%% sharpe=%.2f avgHold=%.2fh corr=%.2f",
               trades,winRate,profitFactor,maxDD,sharpe,avgHoldHours,equityCorr);
   return pass?1.0:0.0;
}
