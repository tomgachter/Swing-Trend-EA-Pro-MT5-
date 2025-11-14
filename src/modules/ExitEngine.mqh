#ifndef __EXIT_ENGINE_MQH__
#define __EXIT_ENGINE_MQH__

#include "EntryEngine.mqh"
#include "RegimeFilter.mqh"
#include "BrokerUtils.mqh"
#include "Sizer.mqh"

enum StopSourceTag
{
   STOP_SOURCE_INITIAL = 0,
   STOP_SOURCE_ADAPTIVE,
   STOP_SOURCE_BREAK_EVEN,
   STOP_SOURCE_TRAIL,
   STOP_SOURCE_TIME
};

enum ExitReasonTag
{
   EXIT_REASON_UNKNOWN = 0,
   EXIT_REASON_INITIAL_SL,
   EXIT_REASON_ADAPTIVE_SL,
   EXIT_REASON_BREAK_EVEN,
   EXIT_REASON_TRAIL,
   EXIT_REASON_TIME,
   EXIT_REASON_HARD_TP
};

struct TradeMetadata
{
   ulong         ticket;
   int           direction;
   double        entryPrice;
   double        initialStop;
   double        rPoints;
   bool          breakEvenDone;
   bool          partialDone;
   bool          timeStopTightened;
   datetime      openTime;
   EntryFamily   family;
   RegimeBucket  regime;
   SessionWindow session;
   double        riskPercent;
   double        highestPrice;
   double        lowestPrice;
   double        finalTpPrice;
   bool          useHardFinalTp;
   double        quality;
   BiasStrength  biasStrength;
   bool          adaptiveApplied;
   double        entryAtr;
   double        maxFavorableR;
   double        maxAdverseR;
   double        lastKnownSL;
   double        lastKnownTP;
   int           lastBarsInTrade;
   bool          fallbackTrade;
   StopSourceTag lastStopSource;
};

class ExitEngine
{
private:
   TradeMetadata m_positions[16];
   int           m_count;
   double        m_partialFraction;
   double        m_breakEvenR;
   double        m_partialTP_R;
   double        m_finalTP_R;
   double        m_trailStart_R;
   double        m_trailDistance_R;
   bool          m_useHardFinalTP;
   bool          m_useTimeStop;
   int           m_maxBarsInTrade;
   double        m_timeStopProtectR;
   bool          m_useAdaptiveSL;
   int           m_adaptiveAfterBars;
   double        m_adaptiveMultiplier;
   double        m_adaptiveMinProfitR;
   ENUM_TIMEFRAMES m_entryTimeframe;
   bool          m_verbose;
   bool          m_enableTelemetry;
   string        m_logFolder;
   string        m_entryFileName;
   string        m_summaryFileName;
   bool          m_entryHeaderWritten;
   bool          m_summaryHeaderWritten;

   void RemoveAt(const int index)
   {
      if(index<0 || index>=m_count)
         return;
      for(int i=index;i<m_count-1;i++)
         m_positions[i] = m_positions[i+1];
      m_count = MathMax(0,m_count-1);
   }

   void EnsureTelemetryFolder()
   {
      if(!m_enableTelemetry)
         return;
      string folder = (m_logFolder=="" ? "XAU_Swing_TrendEA_Pro" : m_logFolder);
      FolderCreate(folder,FILE_COMMON);
      m_logFolder = folder;
   }

   string ComposePath(const string fileName) const
   {
      if(m_logFolder=="")
         return fileName;
      return m_logFolder + "/" + fileName;
   }

   void LogRegistration(const TradeMetadata &meta,const double volume)
   {
      if(!m_enableTelemetry)
         return;
      EnsureTelemetryFolder();
      string fileName = (m_entryFileName=="" ? "trade_log.csv" : m_entryFileName);
      int handle = FileOpen(ComposePath(fileName),FILE_WRITE|FILE_READ|FILE_CSV|FILE_COMMON,';');
      if(handle!=INVALID_HANDLE)
      {
         FileSeek(handle,0,SEEK_END);
         long pos = FileTell(handle);
         if(pos==0 && !m_entryHeaderWritten)
         {
            FileWrite(handle,
                      "entry_time",
                      "ticket",
                      "volume",
                      "direction",
                      "family",
                      "regime",
                      "session",
                      "risk_points",
                      "initial_stop",
                      "final_tp",
                      "quality",
                      "bias_strength",
                      "risk_percent",
                      "fallback_mode");
            m_entryHeaderWritten = true;
         }
         else if(pos>0)
            m_entryHeaderWritten = true;
         FileWrite(handle,
                   TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),
                   meta.ticket,
                   volume,
                   meta.direction,
                   meta.family,
                   meta.regime,
                   meta.session,
                   meta.rPoints,
                   meta.initialStop,
                   meta.finalTpPrice,
                   meta.quality,
                   meta.biasStrength,
                   meta.riskPercent,
                   meta.fallbackTrade?"true":"false");
         FileClose(handle);
      }
   }

   void LogSummary(const TradeMetadata &meta,const datetime exitTime,const double exitPrice,const double profit,
                   const double finalR,const double commission,const double swap,const string &exitLabel)
   {
      if(!m_enableTelemetry)
         return;
      EnsureTelemetryFolder();
      string fileName = (m_summaryFileName=="" ? "trade_telemetry.csv" : m_summaryFileName);
      int handle = FileOpen(ComposePath(fileName),FILE_WRITE|FILE_READ|FILE_CSV|FILE_COMMON,';');
      if(handle==INVALID_HANDLE)
         return;
      FileSeek(handle,0,SEEK_END);
      long pos = FileTell(handle);
      if(pos==0 && !m_summaryHeaderWritten)
      {
         FileWrite(handle,
                   "entry_time",
                   "exit_time",
                   "ticket",
                   "direction",
                   "setup_type",
                   "risk_percent",
                   "r_exit",
                   "mfe_r",
                   "mae_r",
                   "bars_in_trade",
                   "exit_type",
                   "session",
                   "regime",
                   "quality",
                   "bias_strength",
                   "profit",
                   "commission",
                   "swap",
                   "fallback_mode",
                   "entry_price",
                   "exit_price");
         m_summaryHeaderWritten = true;
      }
      else if(pos>0)
         m_summaryHeaderWritten = true;
      string typeLabel = (meta.family==ENTRY_FAMILY_PULLBACK ? "PULLBACK" : "BREAKOUT");
      if(meta.fallbackTrade)
         typeLabel += "_FALLBACK";
      FileWrite(handle,
                TimeToString(meta.openTime,TIME_DATE|TIME_SECONDS),
                TimeToString(exitTime,TIME_DATE|TIME_SECONDS),
                meta.ticket,
                meta.direction,
                typeLabel,
                meta.riskPercent,
                finalR,
                meta.maxFavorableR,
                meta.maxAdverseR,
                meta.lastBarsInTrade,
                exitLabel,
                meta.session,
                meta.regime,
                meta.quality,
                meta.biasStrength,
                profit,
                commission,
                swap,
                meta.fallbackTrade?"true":"false",
                meta.entryPrice,
                exitPrice);
      FileClose(handle);
   }

   double PointsToPrice(const double points,const double pointSize) const
   {
      return points * pointSize;
   }

public:
   ExitEngine(): m_count(0), m_partialFraction(0.5), m_breakEvenR(1.0), m_partialTP_R(1.2), m_finalTP_R(2.5),
                 m_trailStart_R(1.5), m_trailDistance_R(1.0), m_useHardFinalTP(true), m_useTimeStop(true),
                 m_maxBarsInTrade(30), m_timeStopProtectR(0.5),
                 m_useAdaptiveSL(true), m_adaptiveAfterBars(10), m_adaptiveMultiplier(1.2), m_adaptiveMinProfitR(0.5),
                 m_entryTimeframe(PERIOD_H1), m_verbose(false),
                 m_enableTelemetry(false), m_logFolder("XAU_Swing_TrendEA_Pro"),
                 m_entryFileName("trade_log.csv"), m_summaryFileName("trade_telemetry.csv"),
                 m_entryHeaderWritten(false), m_summaryHeaderWritten(false)
   {
   }

   void ConfigureRManagement(const double partialFraction,const double breakEvenR,const double partialTP_R,
                             const double finalTP_R,const double trailStart_R,const double trailDistance_R,
                             const bool useHardFinalTP,const bool useTimeStop,const int maxBarsInTrade,
                             const double timeStopProtectR)
   {
      // All exit decisions operate in R-multiples so partials/trails/time stops scale with the
      // initial stop distance regardless of volatility regime.
      m_partialFraction = MathMax(0.0,MathMin(1.0,partialFraction));
      m_breakEvenR = MathMax(0.0,breakEvenR);
      m_partialTP_R = MathMax(0.0,partialTP_R);
      m_finalTP_R = MathMax(0.0,finalTP_R);
      m_trailStart_R = MathMax(0.0,trailStart_R);
      m_trailDistance_R = MathMax(0.0,trailDistance_R);
      m_useHardFinalTP = useHardFinalTP;
      m_useTimeStop = useTimeStop;
      m_maxBarsInTrade = MathMax(1,maxBarsInTrade);
      m_timeStopProtectR = timeStopProtectR;
   }

   void SetEntryTimeframe(const ENUM_TIMEFRAMES tf)
   {
      m_entryTimeframe = tf;
   }

   void SetVerbose(const bool verbose)
   {
      m_verbose = verbose;
   }

   void ConfigureAdaptiveSL(const bool useAdaptive,const int afterBars,const double atrMultiplier,const double minProfitR)
   {
      m_useAdaptiveSL = useAdaptive;
      m_adaptiveAfterBars = MathMax(1,afterBars);
      m_adaptiveMultiplier = MathMax(0.0,atrMultiplier);
      m_adaptiveMinProfitR = minProfitR;
   }

   void ConfigureTelemetry(const bool enable,const string folder="",const string prefix="")
   {
      m_enableTelemetry = enable;
      if(folder!="")
         m_logFolder = folder;
      string base = (prefix=="" ? "trade" : prefix);
      if(base=="trade")
      {
         m_entryFileName = "trade_log.csv";
         m_summaryFileName = "trade_telemetry.csv";
      }
      else
      {
         m_entryFileName = base + "_entries.csv";
         m_summaryFileName = base + "_telemetry.csv";
      }
      m_entryHeaderWritten = false;
      m_summaryHeaderWritten = false;
   }

   void Register(const ulong ticket,const EntrySignal &signal,const double rPoints,const double volume,const double riskPercent)
   {
      if(m_count>=ArraySize(m_positions))
         return;

      TradeMetadata meta;
      meta.ticket = ticket;
      meta.direction = signal.direction;
      meta.entryPrice = signal.entryPrice;
      meta.initialStop = signal.stopLoss;
      meta.rPoints = rPoints;
      meta.breakEvenDone = false;
      meta.partialDone = false;
      meta.timeStopTightened = false;
      meta.openTime = TimeCurrent();
      meta.family = signal.family;
      meta.regime = signal.regime;
      meta.session = signal.session;
      meta.riskPercent = riskPercent;
      meta.highestPrice = signal.entryPrice;
      meta.lowestPrice  = signal.entryPrice;
      meta.useHardFinalTp = m_useHardFinalTP;
      meta.quality = signal.quality;
      meta.biasStrength = signal.biasStrength;
      meta.finalTpPrice = (m_useHardFinalTP ? signal.entryPrice + signal.direction*m_finalTP_R*rPoints*_Point : 0.0);
      meta.adaptiveApplied = !m_useAdaptiveSL;
      meta.entryAtr = MathAbs(signal.atr);
      meta.maxFavorableR = 0.0;
      meta.maxAdverseR = 0.0;
      meta.lastKnownSL = signal.stopLoss;
      meta.lastKnownTP = meta.finalTpPrice;
      meta.lastBarsInTrade = 0;
      meta.fallbackTrade = signal.fallbackRelaxed;
      meta.lastStopSource = STOP_SOURCE_INITIAL;

      m_positions[m_count++] = meta;

      if(m_verbose)
      {
         PrintFormat("EXIT DEBUG: register ticket=%I64u dir=%d entry=%.2f rPoints=%.1f",ticket,meta.direction,meta.entryPrice,meta.rPoints);
      }
      LogRegistration(meta,volume);
   }

   ExitReasonTag DeriveExitReason(const TradeMetadata &meta,const double exitPrice,const double point) const
   {
      double tolerance = MathMax(point*2.0,point*0.5);
      if(meta.useHardFinalTp && meta.finalTpPrice>0.0 && MathAbs(exitPrice-meta.finalTpPrice)<=tolerance)
         return EXIT_REASON_HARD_TP;
      if(meta.lastKnownSL>0.0 && MathAbs(exitPrice-meta.lastKnownSL)<=tolerance)
      {
         switch(meta.lastStopSource)
         {
            case STOP_SOURCE_BREAK_EVEN: return EXIT_REASON_BREAK_EVEN;
            case STOP_SOURCE_TRAIL:      return EXIT_REASON_TRAIL;
            case STOP_SOURCE_TIME:       return EXIT_REASON_TIME;
            case STOP_SOURCE_ADAPTIVE:   return EXIT_REASON_ADAPTIVE_SL;
            default:                     return EXIT_REASON_INITIAL_SL;
         }
      }
      if(MathAbs(exitPrice-meta.initialStop)<=tolerance)
         return EXIT_REASON_INITIAL_SL;
      return EXIT_REASON_UNKNOWN;
   }

   string ExitReasonToString(const ExitReasonTag reason) const
   {
      switch(reason)
      {
         case EXIT_REASON_INITIAL_SL:   return "STOP_LOSS";
         case EXIT_REASON_ADAPTIVE_SL:  return "ADAPTIVE_SL";
         case EXIT_REASON_BREAK_EVEN:   return "BREAK_EVEN";
         case EXIT_REASON_TRAIL:        return "TRAIL";
         case EXIT_REASON_TIME:         return "TIME_STOP";
         case EXIT_REASON_HARD_TP:      return "HARD_TP";
         default:                       return "UNKNOWN";
      }
   }

   double OnPositionClosed(const ulong ticket,const double exitPrice,const datetime exitTime,const double profit,
                           const double commission,const double swap)
   {
      double risk = 0.0;
      for(int i=0;i<m_count;i++)
      {
         if(m_positions[i].ticket==ticket)
         {
            risk = m_positions[i].riskPercent;
            double point = SymbolInfoDouble(_Symbol,SYMBOL_POINT);
            if(point<=0.0)
               point = _Point;
            double finalR = 0.0;
            if(point>0.0 && m_positions[i].rPoints>0.0)
               finalR = (exitPrice - m_positions[i].entryPrice)*m_positions[i].direction/(m_positions[i].rPoints*point);
            ExitReasonTag reason = DeriveExitReason(m_positions[i],exitPrice,point);
            string reasonLabel = ExitReasonToString(reason);
            LogSummary(m_positions[i],exitTime,exitPrice,profit,finalR,commission,swap,reasonLabel);
            RemoveAt(i);
            break;
         }
      }
      return risk;
   }

   void Manage(BrokerUtils &broker,PositionSizer &sizer,RegimeFilter &regime)
   {
      double ask = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      double bid = SymbolInfoDouble(_Symbol,SYMBOL_BID);
      SymbolContext ctx = sizer.Context();
      double point = (ctx.point>0.0 ? ctx.point : _Point);
      double minStep = 10.0*point;
      int periodSeconds = PeriodSeconds(m_entryTimeframe);
      if(periodSeconds<=0)
         periodSeconds = 3600;

      for(int i=m_count-1;i>=0;i--)
      {
         if(!PositionSelectByTicket(m_positions[i].ticket))
            continue;

         double currentPrice = (m_positions[i].direction>0 ? bid : ask);
         if(m_positions[i].direction>0)
            m_positions[i].highestPrice = MathMax(m_positions[i].highestPrice,currentPrice);
         else
            m_positions[i].lowestPrice = MathMin(m_positions[i].lowestPrice,currentPrice);

         if(m_positions[i].rPoints<=0.0)
            continue;

         double rToPrice = PointsToPrice(m_positions[i].rPoints,point);
         if(rToPrice<=0.0)
            continue;

         double currentR = (currentPrice - m_positions[i].entryPrice)*m_positions[i].direction/(rToPrice);

         double currentSL = PositionGetDouble(POSITION_SL);
         double currentTP = PositionGetDouble(POSITION_TP);

         m_positions[i].maxFavorableR = MathMax(m_positions[i].maxFavorableR,currentR);
         m_positions[i].maxAdverseR = MathMin(m_positions[i].maxAdverseR,currentR);
         m_positions[i].lastKnownSL = currentSL;
         m_positions[i].lastKnownTP = currentTP;

         double elapsedSeconds = (double)(TimeCurrent() - m_positions[i].openTime);
         int barsInTrade = (int)MathFloor(elapsedSeconds/periodSeconds);
         if(barsInTrade<0)
            barsInTrade = 0;
         m_positions[i].lastBarsInTrade = barsInTrade;

         if(m_useAdaptiveSL && !m_positions[i].adaptiveApplied && m_adaptiveAfterBars>0 && barsInTrade >= m_adaptiveAfterBars)
         {
            if(currentR >= m_adaptiveMinProfitR)
            {
               m_positions[i].adaptiveApplied = true;
            }
            else
            {
               double atrBasis = (m_positions[i].entryAtr>0.0 ? m_positions[i].entryAtr : regime.AtrH1());
               double adaptiveDist = atrBasis * m_adaptiveMultiplier;
               if(adaptiveDist<=0.0)
               {
                  m_positions[i].adaptiveApplied = true;
               }
               else
               {
                  double adaptivePrice = m_positions[i].entryPrice - m_positions[i].direction*adaptiveDist;
                  bool canImprove = (m_positions[i].direction>0 ? adaptivePrice > currentSL + minStep : adaptivePrice < currentSL - minStep);
                  if(canImprove)
                  {
                     if(m_positions[i].direction>0)
                        adaptivePrice = MathMin(adaptivePrice,currentPrice - minStep);
                     else
                        adaptivePrice = MathMax(adaptivePrice,currentPrice + minStep);
                     if(broker.ModifySL(m_positions[i].ticket,adaptivePrice))
                     {
                        m_positions[i].adaptiveApplied = true;
                        m_positions[i].lastStopSource = STOP_SOURCE_ADAPTIVE;
                        m_positions[i].lastKnownSL = adaptivePrice;
                        currentSL = adaptivePrice;
                        if(m_verbose)
                           PrintFormat("EXIT DEBUG: adaptive SL tightened ticket=%I64u newSL=%.2f",m_positions[i].ticket,adaptivePrice);
                     }
                  }
                  else
                  {
                     m_positions[i].adaptiveApplied = true;
                  }
               }
            }
         }

         // Break-even management
         if(!m_positions[i].breakEvenDone && m_breakEvenR>0.0 && currentR >= m_breakEvenR)
         {
            double breakEvenPrice = m_positions[i].entryPrice;
            if((m_positions[i].direction>0 && breakEvenPrice>currentSL+minStep) || (m_positions[i].direction<0 && breakEvenPrice<currentSL-minStep))
            {
               if(broker.ModifySL(m_positions[i].ticket,breakEvenPrice))
               {
                  m_positions[i].breakEvenDone = true;
                  m_positions[i].lastStopSource = STOP_SOURCE_BREAK_EVEN;
                  m_positions[i].lastKnownSL = breakEvenPrice;
                  if(m_verbose)
                     PrintFormat("EXIT DEBUG: break-even set ticket=%I64u sl=%.2f",m_positions[i].ticket,breakEvenPrice);
               }
            }
         }

         // Partial close
         if(!m_positions[i].partialDone && m_partialFraction>0.0 && m_partialFraction<1.0 && m_partialTP_R>0.0 && currentR >= m_partialTP_R)
         {
            double volume = PositionGetDouble(POSITION_VOLUME);
            double partialVolume = sizer.NormalizeVolume(volume*m_partialFraction);
            if(partialVolume>0.0 && partialVolume<volume)
            {
               if(broker.ClosePartial(m_positions[i].ticket,partialVolume))
               {
                  m_positions[i].partialDone = true;
                  if(!m_positions[i].breakEvenDone)
                  {
                     double breakEvenPrice = m_positions[i].entryPrice;
                     if(broker.ModifySL(m_positions[i].ticket,breakEvenPrice))
                     {
                        m_positions[i].breakEvenDone = true;
                        m_positions[i].lastStopSource = STOP_SOURCE_BREAK_EVEN;
                        m_positions[i].lastKnownSL = breakEvenPrice;
                     }
                  }
                  if(m_verbose)
                     PrintFormat("EXIT DEBUG: partial closed ticket=%I64u volume=%.2f",m_positions[i].ticket,partialVolume);
               }
            }
         }

         // Trailing stop (only if no hard TP)
         if(!m_positions[i].useHardFinalTp && m_trailStart_R>0.0 && m_trailDistance_R>0.0 && currentR >= m_trailStart_R)
         {
            double extreme = (m_positions[i].direction>0 ? m_positions[i].highestPrice : m_positions[i].lowestPrice);
            double trailPrice = extreme - m_positions[i].direction*m_trailDistance_R*rToPrice;
            bool improved = false;
            if(m_positions[i].direction>0)
               improved = (trailPrice > currentSL + minStep);
            else
               improved = (trailPrice < currentSL - minStep);
            if(improved)
            {
               if(m_positions[i].direction>0)
                  trailPrice = MathMin(trailPrice,currentPrice - minStep);
               else
                  trailPrice = MathMax(trailPrice,currentPrice + minStep);
               if(broker.ModifySL(m_positions[i].ticket,trailPrice))
               {
                  m_positions[i].lastStopSource = STOP_SOURCE_TRAIL;
                  m_positions[i].lastKnownSL = trailPrice;
                  if(m_verbose)
                     PrintFormat("EXIT DEBUG: trailing stop adjusted ticket=%I64u newSL=%.2f",m_positions[i].ticket,trailPrice);
               }
            }
         }

         // Time-based exit
         if(m_useTimeStop)
         {
            if(barsInTrade >= m_maxBarsInTrade)
            {
               if(currentR <= 0.0)
               {
                  m_positions[i].lastStopSource = STOP_SOURCE_TIME;
                  m_positions[i].lastKnownSL = currentPrice;
                  if(broker.ClosePosition(m_positions[i].ticket) && m_verbose)
                     PrintFormat("EXIT DEBUG: time stop closed ticket=%I64u at R=%.2f",m_positions[i].ticket,currentR);
                  continue;
               }
               if(!m_positions[i].timeStopTightened && m_timeStopProtectR!=0.0)
               {
                  double protective = m_positions[i].entryPrice + m_positions[i].direction*m_timeStopProtectR*rToPrice;
                  bool canImprove = (m_positions[i].direction>0 ? protective > currentSL + minStep : protective < currentSL - minStep);
                  if(canImprove)
                  {
                     if(m_positions[i].direction>0)
                        protective = MathMin(protective,currentPrice - minStep);
                     else
                        protective = MathMax(protective,currentPrice + minStep);
                     if(broker.ModifySL(m_positions[i].ticket,protective))
                     {
                        m_positions[i].timeStopTightened = true;
                        m_positions[i].lastStopSource = STOP_SOURCE_TIME;
                        m_positions[i].lastKnownSL = protective;
                        if(m_verbose)
                           PrintFormat("EXIT DEBUG: time stop tightened ticket=%I64u newSL=%.2f",m_positions[i].ticket,protective);
                     }
                  }
               }
            }
         }
      }
   }
};

#endif // __EXIT_ENGINE_MQH__
