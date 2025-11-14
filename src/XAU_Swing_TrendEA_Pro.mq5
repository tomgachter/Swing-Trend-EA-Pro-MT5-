//+------------------------------------------------------------------+
//| XAU_Swing_TrendEA_Pro.mq5                                        |
//| Refactored swing/breakout Expert Advisor for XAUUSD (MT5)        |
//| Session: 07:00-14:45, Bias votes: EMA20(H1)/EMA34(H4)/EMA50(D1)  |
//| Risk: ATR stop sizing, R-multiple partials/trailing/time-stop    |
//+------------------------------------------------------------------+
#property strict

#include <Trade\Trade.mqh>

#include "modules/TesterCompat.mqh"
#include "modules/RegimeFilter.mqh"
#include "modules/SessionFilter.mqh"
#include "modules/BiasEngine.mqh"
#include "modules/EntryEngine.mqh"
#include "modules/Sizer.mqh"
#include "modules/BrokerUtils.mqh"
#include "modules/RiskEngine.mqh"
#include "modules/ExitEngine.mqh"

// --- Risk / session framework -------------------------------------------------
input RiskMode         InpRiskMode = RISK_PERCENT_PER_TRADE;  // Risk allocation model
input double           RiskPerTrade = 0.75;                   // Percent or lots depending on mode
input double           MaxDailyRiskPercent = 5.0;             // Daily loss+open risk cap in %
input double           MaxEquityDDPercentForCloseAll = 12.0;  // Hard equity drawdown kill switch
input ulong            MagicNumber = 20241026;                // Trade identifier
input string           TradeComment = "XAU_Swing_TrendEA_Pro";
input bool             EnableChartAnnotations = true;
input bool             RandomizeEntryExit = false;
input int              PropFirmDayStartHour = 0;              // Serverzeit-Offset für Tagesanker
input bool             UseStaticOverallDD   = true;           // Statischer Gesamt-DD (prop-konform)
input int              SlippageBudgetPoints = 80;             // Worst-case Slippage für Budgetprüfung
input int              MaxSpreadPoints      = 200;            // Maximaler Spread in Punkten für neue Einstiege
input int              SessionStartHour     = 7;
input int              SessionStartMinute   = 0;
input int              SessionEndHour       = 14;
input int              SessionEndMinute     = 45;
input bool             AllowSessionOverrideInDebug = false;

// Balanced XAU H1 preset reference (see README for symbol-specific tweaks):
// RiskPerTrade=0.75, MaxDailyRiskPercent=5, MaxEquityDDPercentForCloseAll=12,
// BiasSlopeThH1/H4/D1=0.020/0.018/0.015, MinEntryQualityCore/Edge=0.7/0.8,
// PartialCloseFraction=0.5, BreakEven_R=1.0, PartialTP_R=1.2, FinalTP_R=2.5,
// TrailStart_R=1.5, TrailDistance_R=1.0, MaxBarsInTrade=30, MaxNewTradesPerDay=5,
// MaxLosingTradesPerDay=3, MaxLosingTradesInARow=3, RiskScaleAfterLosingStreak=0.5.

// --- Bias tuning -------------------------------------------------------------
input int              BiasVotesRequired     = 2;      // Mehrheitsvotum (kept for compatibility)
input double           BiasSlopeThH1         = 0.020;
input double           BiasSlopeThH4         = 0.018;
input double           BiasSlopeThD1         = 0.015;
input bool             AllowNeutralBiasOnEdge= true;   // Edge-Session: starkes Setup darf trotz neutralem Bias
input double           NeutralBiasRiskScale  = 0.50;   // Risiko-Reduktion bei neutralem Bias Override

// --- Entry sensitivity & scoring --------------------------------------------
input double           PullbackBodyATRMin    = 0.35;   // Mindestkörpergröße relativ ATR
input double           BreakoutImpulseATRMin = 0.35;   // Mindestimpuls relativ ATR
input int              BreakoutRangeBars     = 5;      // Range-Breite für Breakout-Box
input double           MinEntryQualityCore   = 0.70;   // Score-Schwelle Kernsession
input double           MinEntryQualityEdge   = 0.80;   // Score-Schwelle Edge/Fallback
input bool             AllowAggressiveEntries= true;   // Aggressiver handeln bei positivem Lauf
input int              MaxNewTradesPerDay    = 5;      // Maximal neue Einstiege pro Tag
input ENUM_TIMEFRAMES  EntryTF               = PERIOD_H1;

// --- Fallback & bias relaxation ---------------------------------------------
input bool             EnableWeekdayFallback = true;   // relaxed mode not only on Friday
input int              FallbackMinHour       = 12;     // earliest hour for fallback
input int              FallbackMaxPer7D      = 2;      // fire when < this in last 7D
input double           StopLossATRMultiplier = 1.2;    // initial SL = ATR * multiplier
input bool             UseDynamicRisk        = true;
input bool             EnableFallbackEntry   = true;

// --- R-based trade management ------------------------------------------------
input double           PartialCloseFraction  = 0.50;   // Anteil der Position beim Teilgewinn
input double           BreakEven_R           = 1.0;    // ab 1R SL auf Break-even
input double           PartialTP_R           = 1.2;    // Teilgewinn-Level in R
input double           FinalTP_R             = 2.5;    // finales Ziel in R (wenn hartes TP aktiv)
input double           TrailStart_R          = 1.5;    // ab dieser R-Multiple trailen
input double           TrailDistance_R       = 1.0;    // Abstand in R für Trailing-Stop
input bool             UseHardFinalTP        = true;   // TP beim Entry setzen
input bool             UseTimeStop           = true;   // Max-Bars-Stop aktivieren
input int              MaxBarsInTrade        = 30;     // Zeit-Stop (Bars des EntryTF)
input double           TimeStopProtectR      = 0.5;    // SL auf xR anziehen bei Time-Stop

// --- Risk discipline extensions ---------------------------------------------
input int              MaxLosingTradesPerDay = 3;
input int              MaxLosingTradesInARow = 3;
input double           RiskScaleAfterLosingStreak = 0.50; // <0 => Handel pausiert

input bool             DebugMode = true;    // ausführliches Logging + Debug-Fallbacks
input bool             ForceVerboseDecisionLog = false; // erzwingt detaillierte Entscheidungs-Logs ohne Debug-Overrides

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
datetime      gEntryHistory[];
int           gFallbackWeekId = -1;
bool          gFallbackUsedThisWeek = false;
bool          gVerboseDecisionLog = false;
const int     RECENT_TRADE_WINDOW = 10;
double        gRecentTradePnL[RECENT_TRADE_WINDOW];
int           gRecentTradeCount = 0;

//--- helper declarations
bool IsNewBar();
void EvaluateNewBar();
void ManageOpenPositions();
bool HasDirectionalPosition(const int direction);
void AnnotateChart(const string message,const color col=clrDodgerBlue);
void AttemptEntry(const EntrySignal &signal);
void CloseAllPositions();
void RecordEntryTime(const datetime entryTime,const bool fallbackTrade);
void CleanupEntryHistory(const datetime reference);
int  EntriesLastSevenDays(const datetime reference);
int  ComputeWeekId(const datetime time);
bool ShouldUseFallbackEntry(const datetime signalTime,const int recentEntries);
void ResetRecentPnL();
void RecordClosedTradePnL(const double profit);
bool RecentPnLPositive();

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   gVerboseDecisionLog = (DebugMode || ForceVerboseDecisionLog);
   gBroker.Configure(MagicNumber,TradeComment,20);
   gSession.Configure(SessionStartHour,SessionStartMinute,SessionEndHour,SessionEndMinute);
   gSession.SetDebugMode(DebugMode,AllowSessionOverrideInDebug);
   gEntry.Configure(RandomizeEntryExit);
   gEntry.ConfigureSensitivity(PullbackBodyATRMin,BreakoutImpulseATRMin,BreakoutRangeBars);
   gEntry.SetStopMultiplier(StopLossATRMultiplier);
   gEntry.SetQualityThresholds(MinEntryQualityCore,MinEntryQualityEdge,AllowAggressiveEntries,0.05,0.60);
   gEntry.ConfigureNeutralPolicy(AllowNeutralBiasOnEdge,NeutralBiasRiskScale);
   gExit.ConfigureRManagement(PartialCloseFraction,BreakEven_R,PartialTP_R,FinalTP_R,TrailStart_R,TrailDistance_R,
                              UseHardFinalTP,UseTimeStop,MaxBarsInTrade,TimeStopProtectR);
   gExit.SetEntryTimeframe(EntryTF);
   gExit.SetVerbose(gVerboseDecisionLog);
   string persistKey = StringFormat("STEA:%s:%I64u",_Symbol,MagicNumber);
   gRisk.Configure(InpRiskMode,RiskPerTrade,MaxDailyRiskPercent,MaxEquityDDPercentForCloseAll,
                   PropFirmDayStartHour,persistKey,UseStaticOverallDD,(double)SlippageBudgetPoints);
   gRisk.SetDebugMode(DebugMode);
   gRisk.SetVerboseMode(gVerboseDecisionLog);
   gRisk.SetDynamicRiskEnabled(UseDynamicRisk);
   // Daily discipline guard: cap trades / losing streaks in prop-firm style sessions.
   gRisk.ConfigureTradeDiscipline(MaxNewTradesPerDay,MaxLosingTradesPerDay,MaxLosingTradesInARow,RiskScaleAfterLosingStreak);
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
   gBias.ConfigureThresholds(BiasVotesRequired,BiasSlopeThH1,BiasSlopeThH4,BiasSlopeThD1);
   gBias.SetSlopeThreshold(1.0);
   gBias.SetDebug(gVerboseDecisionLog);
   if(!gSizer.Init(_Symbol))
   {
      Print("Failed to initialise position sizer");
      return INIT_FAILED;
   }
   gRegime.Update(true);
   ArrayResize(gEntryHistory,0);
   gFallbackWeekId = -1;
   gFallbackUsedThisWeek = false;
   ResetRecentPnL();
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialisation                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   gBias.Release();
   gRegime.Release();
}

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
{
   gRisk.OnNewDay();
   gRegime.Update();
   gRisk.RefreshOpenRisk(gSizer,MagicNumber);

   if(gRisk.DailyLimitBreached())
   {
      Print("Daily equity loss limit breached -> closing all positions");
      CloseAllPositions();
      return;
   }

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
   datetime currentBar = iTime(_Symbol,EntryTF,0);
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
   datetime signalTime = gLastBarTime;
   int recentEntries = EntriesLastSevenDays(signalTime);
   int currentWeek = ComputeWeekId(signalTime);
   if(currentWeek!=gFallbackWeekId)
   {
      gFallbackWeekId = currentWeek;
      gFallbackUsedThisWeek = false;
   }
   bool useFallback = ShouldUseFallbackEntry(signalTime,recentEntries);
   double slopeScale = (useFallback ? 0.75 : 1.0);
   gBias.SetSlopeThreshold(slopeScale);
   // Diagnose: Zuvor brach die Entry-Kette still ab. Das detaillierte Logging macht jetzt sichtbar,
   // welche Stufe (Bias/Session/Daten) einen Trade verhindert.
   if(gVerboseDecisionLog)
   {
      PrintFormat("ENTRY TRACE: new bar %s fallback=%s slopeScale=%.2f entries7d=%d",TimeToString(signalTime,TIME_DATE|TIME_MINUTES),
                  useFallback?"true":"false",slopeScale,recentEntries);
   }
   if(!gBias.Update(gRegime))
   {
      if(gVerboseDecisionLog)
      {
         PrintFormat("ENTRY TRACE: Bias update failed at %s",TimeToString(signalTime,TIME_DATE|TIME_MINUTES));
      }
      return;
   }

   TrendBias bias;
   gBias.ComputeTrendBias(bias,useFallback,useFallback);
   if(gVerboseDecisionLog)
   {
      PrintFormat("BIAS TRACE: dir=%d strength=%d score=%.3f votesStrong L%d/S%d votesNear L%d/S%d slopes=%.3f/%.3f/%.3f th=%.3f/%.3f/%.3f",
                  bias.direction,(int)bias.strength,bias.score,
                  bias.votesStrongLong,bias.votesStrongShort,
                  bias.votesNearLong,bias.votesNearShort,
                  bias.slopeH1,bias.slopeH4,bias.slopeD1,
                  bias.thresholdH1,bias.thresholdH4,bias.thresholdD1);
   }

   SessionWindow window;
   if(!gSession.AllowsEntry(signalTime,window))
   {
      AnnotateChart("Session filter blocked entry",clrSilver);
      if(DebugMode)
         PrintFormat("ENTRY DEBUG: Session filter blocked entry at %s",TimeToString(signalTime,TIME_DATE|TIME_MINUTES));
      else if(gVerboseDecisionLog)
         PrintFormat("ENTRY TRACE: Session filter blocked entry at %s",TimeToString(signalTime,TIME_DATE|TIME_MINUTES));
      return;
   }

   // use a dynamic rates buffer because ArraySetAsSeries only affects dynamic arrays
   MqlRates rates[];
   ArraySetAsSeries(rates,true);
   int barsNeeded = MathMax(6,BreakoutRangeBars+2);
   int copied = CopyRates(_Symbol,EntryTF,0,barsNeeded,rates);
   if(copied<3)
   {
      if(gVerboseDecisionLog)
         PrintFormat("ENTRY TRACE: insufficient rate data copied=%d",copied);
      return;
   }

   EntrySignal signal;
   bool allowAggressiveBoost = (AllowAggressiveEntries && RecentPnLPositive());
   if(!gEntry.Evaluate(bias,gRegime,window,rates,copied,useFallback,useFallback,gVerboseDecisionLog,allowAggressiveBoost,signal))
   {
      if(gVerboseDecisionLog)
         Print("ENTRY TRACE: EntryEngine returned no signal");
      return;
   }

   if(HasDirectionalPosition(signal.direction))
   {
      AnnotateChart("Position in same direction already open",clrSilver);
      return;
   }

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
      return false;

   ENUM_POSITION_TYPE need = (direction>0 ? POSITION_TYPE_BUY : POSITION_TYPE_SELL);
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol)
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=MagicNumber)
         continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)!=need)
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
   if(DebugMode)
   {
      PrintFormat("ENTRY DEBUG: AttemptEntry dir=%d entry=%.2f stop=%.2f quality=%.2f biasStrength=%d riskScale=%.2f fallback=%s",
                  signal.direction,signal.entryPrice,signal.stopLoss,signal.quality,(int)signal.biasStrength,
                  signal.riskScale,signal.fallbackRelaxed?"true":"false");
   }
   double stopPoints = gSizer.StopDistancePoints(signal.entryPrice,signal.stopLoss);
   if(stopPoints<=0.0)
   {
      if(DebugMode)
         Print("ENTRY DEBUG: stopPoints <= 0 -> abort entry");
      return;
   }

   if(DebugMode)
      PrintFormat("ENTRY DEBUG: computed stopPoints=%.1f",stopPoints);

   double bid = SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double point = SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   if(point<=0.0)
      point = _Point;
   if(point>0.0)
   {
      int spreadPts = (int)MathRound((ask-bid)/point);
      if(spreadPts>MaxSpreadPoints)
      {
         if(EnableChartAnnotations)
            AnnotateChart("Spread zu hoch",clrTomato);
         if(DebugMode)
            PrintFormat("ENTRY DEBUG: spreadPts=%d > MaxSpreadPoints=%d -> skip entry",spreadPts,MaxSpreadPoints);
         else
            PrintFormat("Spread %dpt > MaxSpreadPoints %d -> Entry verworfen",spreadPts,MaxSpreadPoints);
         return;
      }
      else if(DebugMode)
      {
         PrintFormat("ENTRY DEBUG: spreadPts=%d within limit %d",spreadPts,MaxSpreadPoints);
      }
   }

   double volume=0.0;
   double riskPercent=0.0;
   if(!gRisk.AllowNewTrade(stopPoints,gSizer,gRegime,volume,riskPercent,signal.riskScale))
   {
      AnnotateChart("Risk guard prevented entry",clrTomato);
      if(DebugMode)
         Print("ENTRY DEBUG: RiskEngine.AllowNewTrade() returned false");
      return;
   }

   if(DebugMode)
      PrintFormat("ENTRY DEBUG: proposed volume=%.4f riskPercent=%.2f%%",volume,riskPercent);

   if(!gRisk.HasSufficientMargin(signal.direction,volume,signal.entryPrice))
   {
      if(EnableChartAnnotations)
         AnnotateChart("Margin check failed",clrTomato);
      if(DebugMode)
         Print("ENTRY DEBUG: Margin check failed -> entry skipped");
      else
         Print("Margin check failed -> entry skipped");
      return;
   }

   double tp = 0.0;
   if(UseHardFinalTP)
   {
      tp = signal.entryPrice + signal.direction*FinalTP_R*stopPoints*point;
   }
   if(!gBroker.OpenPosition(signal.direction,volume,signal.entryPrice,signal.stopLoss,tp))
   {
      if(DebugMode)
         PrintFormat("ENTRY DEBUG: gBroker.OpenPosition() failed dir=%d",signal.direction);
      else
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
      if(DebugMode)
         PrintFormat("ENTRY DEBUG: Opened position volume=%.2f direction=%d",volume,signal.direction);
      RecordEntryTime(TimeCurrent(),signal.fallbackRelaxed);
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

void RecordEntryTime(const datetime entryTime,const bool fallbackTrade)
{
   CleanupEntryHistory(entryTime);
   int size = ArraySize(gEntryHistory);
   ArrayResize(gEntryHistory,size+1);
   gEntryHistory[size] = entryTime;
   if(fallbackTrade)
      gFallbackUsedThisWeek = true;
}

void CleanupEntryHistory(const datetime reference)
{
   int size = ArraySize(gEntryHistory);
   if(size<=0)
      return;
   datetime cutoff = reference - 7*24*3600;
   int writeIndex = 0;
   for(int i=0;i<size;i++)
   {
      if(gEntryHistory[i]>=cutoff)
         gEntryHistory[writeIndex++] = gEntryHistory[i];
   }
   if(writeIndex!=size)
      ArrayResize(gEntryHistory,writeIndex);
}

int EntriesLastSevenDays(const datetime reference)
{
   CleanupEntryHistory(reference);
   return ArraySize(gEntryHistory);
}

int ComputeWeekId(const datetime time)
{
   if(time<=0)
      return -1;
   MqlDateTime dt;
   TimeToStruct(time,dt);
   int week = (int)MathFloor((double)dt.day_of_year/7.0);
   return dt.year*100 + week;
}

bool ShouldUseFallbackEntry(const datetime signalTime,const int recentEntries)
{
   if(!EnableFallbackEntry)
      return false;
   if(signalTime<=0)
      return false;
   if(gFallbackUsedThisWeek)
      return false;
   MqlDateTime dt;
   TimeToStruct(signalTime,dt);
   if(!EnableWeekdayFallback)
   {
      if(recentEntries>=2)
         return false;
      if(dt.day_of_week!=5)
         return false;
      if(dt.hour<12)
         return false;
   }
   else
   {
      if(dt.day_of_week==0 || dt.day_of_week==6)
         return false;
      if(dt.hour<FallbackMinHour)
         return false;
      if(FallbackMaxPer7D>0 && recentEntries>=FallbackMaxPer7D)
         return false;
   }
   return true;
}

void ResetRecentPnL()
{
   for(int i=0;i<RECENT_TRADE_WINDOW;i++)
      gRecentTradePnL[i] = 0.0;
   gRecentTradeCount = 0;
}

void RecordClosedTradePnL(const double profit)
{
   if(RECENT_TRADE_WINDOW<=0)
      return;
   if(gRecentTradeCount<RECENT_TRADE_WINDOW)
   {
      gRecentTradePnL[gRecentTradeCount++] = profit;
   }
   else
   {
      for(int i=1;i<RECENT_TRADE_WINDOW;i++)
         gRecentTradePnL[i-1] = gRecentTradePnL[i];
      gRecentTradePnL[RECENT_TRADE_WINDOW-1] = profit;
   }
}

bool RecentPnLPositive()
{
   // Used to temporarily relax quality thresholds when the last trades netted profit.
   double sum = 0.0;
   for(int i=0;i<gRecentTradeCount;i++)
      sum += gRecentTradePnL[i];
   return (gRecentTradeCount>0 && sum>0.0);
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
         bool positionStillOpen = PositionSelectByTicket(positionId);
         double riskRemoved = 0.0;
         if(!positionStillOpen)
            riskRemoved = gExit.OnPositionClosed(positionId);
         if(!positionStillOpen)
         {
            gRisk.OnTradeClosed(profit,riskRemoved);
            RecordClosedTradePnL(profit);
         }
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
