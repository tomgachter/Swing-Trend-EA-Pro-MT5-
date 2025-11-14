#ifndef __EXIT_ENGINE_MQH__
#define __EXIT_ENGINE_MQH__

#include "EntryEngine.mqh"
#include "RegimeFilter.mqh"
#include "BrokerUtils.mqh"
#include "Sizer.mqh"

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
   ENUM_TIMEFRAMES m_entryTimeframe;
   bool          m_verbose;

   void RemoveAt(const int index)
   {
      if(index<0 || index>=m_count)
         return;
      for(int i=index;i<m_count-1;i++)
         m_positions[i] = m_positions[i+1];
      m_count = MathMax(0,m_count-1);
   }

   void LogRegistration(const TradeMetadata &meta,const double volume)
   {
      FolderCreate("XAU_Swing_TrendEA_Pro",FILE_COMMON);
      int handle = FileOpen("XAU_Swing_TrendEA_Pro/trade_log.csv",FILE_WRITE|FILE_READ|FILE_CSV|FILE_COMMON,';');
      if(handle!=INVALID_HANDLE)
      {
         FileSeek(handle,0,SEEK_END);
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
                   meta.riskPercent);
         FileClose(handle);
      }
   }

   double PointsToPrice(const double points,const double pointSize) const
   {
      return points * pointSize;
   }

public:
   ExitEngine(): m_count(0), m_partialFraction(0.5), m_breakEvenR(1.0), m_partialTP_R(1.2), m_finalTP_R(2.5),
                 m_trailStart_R(1.5), m_trailDistance_R(1.0), m_useHardFinalTP(true), m_useTimeStop(true),
                 m_maxBarsInTrade(30), m_timeStopProtectR(0.5), m_entryTimeframe(PERIOD_H1), m_verbose(false)
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
      m_timeStopProtectR = MathMax(0.0,timeStopProtectR);
   }

   void SetEntryTimeframe(const ENUM_TIMEFRAMES tf)
   {
      m_entryTimeframe = tf;
   }

   void SetVerbose(const bool verbose)
   {
      m_verbose = verbose;
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

      m_positions[m_count++] = meta;

      if(m_verbose)
      {
         PrintFormat("EXIT DEBUG: register ticket=%I64u dir=%d entry=%.2f rPoints=%.1f",ticket,meta.direction,meta.entryPrice,meta.rPoints);
      }
      LogRegistration(meta,volume);
   }

   double OnPositionClosed(const ulong ticket)
   {
      double risk = 0.0;
      for(int i=0;i<m_count;i++)
      {
         if(m_positions[i].ticket==ticket)
         {
            risk = m_positions[i].riskPercent;
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
         TradeMetadata &meta = m_positions[i];
         if(!PositionSelectByTicket(meta.ticket))
            continue;

         double currentPrice = (meta.direction>0 ? bid : ask);
         if(meta.direction>0)
            meta.highestPrice = MathMax(meta.highestPrice,currentPrice);
         else
            meta.lowestPrice = MathMin(meta.lowestPrice,currentPrice);

         if(meta.rPoints<=0.0)
            continue;

         double rToPrice = PointsToPrice(meta.rPoints,point);
         if(rToPrice<=0.0)
            continue;

         double currentR = (currentPrice - meta.entryPrice)*meta.direction/(rToPrice);

         double currentSL = PositionGetDouble(POSITION_SL);

         // Break-even management
         if(!meta.breakEvenDone && m_breakEvenR>0.0 && currentR >= m_breakEvenR)
         {
            double breakEvenPrice = meta.entryPrice;
            if((meta.direction>0 && breakEvenPrice>currentSL+minStep) || (meta.direction<0 && breakEvenPrice<currentSL-minStep))
            {
               if(broker.ModifySL(meta.ticket,breakEvenPrice))
               {
                  meta.breakEvenDone = true;
                  if(m_verbose)
                     PrintFormat("EXIT DEBUG: break-even set ticket=%I64u sl=%.2f",meta.ticket,breakEvenPrice);
               }
            }
         }

         // Partial close
         if(!meta.partialDone && m_partialFraction>0.0 && m_partialFraction<1.0 && m_partialTP_R>0.0 && currentR >= m_partialTP_R)
         {
            double volume = PositionGetDouble(POSITION_VOLUME);
            double partialVolume = sizer.NormalizeVolume(volume*m_partialFraction);
            if(partialVolume>0.0 && partialVolume<volume)
            {
               if(broker.ClosePartial(meta.ticket,partialVolume))
               {
                  meta.partialDone = true;
                  if(!meta.breakEvenDone)
                  {
                     double breakEvenPrice = meta.entryPrice;
                     if(broker.ModifySL(meta.ticket,breakEvenPrice))
                     {
                        meta.breakEvenDone = true;
                     }
                  }
                  if(m_verbose)
                     PrintFormat("EXIT DEBUG: partial closed ticket=%I64u volume=%.2f",meta.ticket,partialVolume);
               }
            }
         }

         // Trailing stop (only if no hard TP)
         if(!meta.useHardFinalTp && m_trailStart_R>0.0 && m_trailDistance_R>0.0 && currentR >= m_trailStart_R)
         {
            double extreme = (meta.direction>0 ? meta.highestPrice : meta.lowestPrice);
            double trailPrice = extreme - meta.direction*m_trailDistance_R*rToPrice;
            bool improved = false;
            if(meta.direction>0)
               improved = (trailPrice > currentSL + minStep);
            else
               improved = (trailPrice < currentSL - minStep);
            if(improved)
            {
               if(meta.direction>0)
                  trailPrice = MathMin(trailPrice,currentPrice - minStep);
               else
                  trailPrice = MathMax(trailPrice,currentPrice + minStep);
               if(broker.ModifySL(meta.ticket,trailPrice) && m_verbose)
                  PrintFormat("EXIT DEBUG: trailing stop adjusted ticket=%I64u newSL=%.2f",meta.ticket,trailPrice);
            }
         }

         // Time-based exit
         if(m_useTimeStop)
         {
            double elapsedSeconds = (double)(TimeCurrent() - meta.openTime);
            int barsInTrade = (int)MathFloor(elapsedSeconds/periodSeconds);
            if(barsInTrade >= m_maxBarsInTrade)
            {
               if(currentR <= 0.0)
               {
                  if(broker.ClosePosition(meta.ticket) && m_verbose)
                     PrintFormat("EXIT DEBUG: time stop closed ticket=%I64u at R=%.2f",meta.ticket,currentR);
                  continue;
               }
               if(!meta.timeStopTightened && m_timeStopProtectR>0.0)
               {
                  double protective = meta.entryPrice + meta.direction*m_timeStopProtectR*rToPrice;
                  bool canImprove = (meta.direction>0 ? protective > currentSL + minStep : protective < currentSL - minStep);
                  if(canImprove)
                  {
                     if(meta.direction>0)
                        protective = MathMin(protective,currentPrice - minStep);
                     else
                        protective = MathMax(protective,currentPrice + minStep);
                     if(broker.ModifySL(meta.ticket,protective))
                     {
                        meta.timeStopTightened = true;
                        if(m_verbose)
                           PrintFormat("EXIT DEBUG: time stop tightened ticket=%I64u newSL=%.2f",meta.ticket,protective);
                     }
                  }
               }
            }
         }
      }
   }
};

#endif // __EXIT_ENGINE_MQH__
