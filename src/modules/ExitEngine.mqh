#pragma once

#include "EntryEngine.mqh"
#include "RegimeFilter.mqh"
#include "BrokerUtils.mqh"
#include "Sizer.mqh"

struct TradeMetadata
{
   ulong         ticket;
   int           direction;
   double        entryPrice;
   double        atrEntry;
   double        slDistancePts;
   double        partialLevel;
   bool          partialDone;
   datetime      openTime;
   EntryFamily   family;
   RegimeBucket  regime;
   SessionWindow session;
   double        highWater;
   double        lowWater;
   double        riskPercent;
};

class ExitEngine
{
private:
   TradeMetadata m_positions[16];
   int           m_count;
   double        m_trailMultiplier;
   double        m_timeCutoffHours;

   void RemoveAt(const int index)
   {
      if(index<0 || index>=m_count)
         return;
      for(int i=index;i<m_count-1;i++)
         m_positions[i]=m_positions[i+1];
      m_count = MathMax(0,m_count-1);
   }

   void LogRegistration(const TradeMetadata &meta,const double volume)
   {
      FolderCreate("XAU_Swing_TrendEA_Pro",FILE_COMMON);
      int handle = FileOpen("XAU_Swing_TrendEA_Pro/trade_log.csv",FILE_WRITE|FILE_READ|FILE_CSV|FILE_COMMON,';');
      if(handle!=INVALID_HANDLE)
      {
         FileSeek(handle,0,SEEK_END);
         FileWrite(handle,TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),meta.ticket,volume,meta.direction,meta.family,meta.regime,meta.session,meta.atrEntry,meta.slDistancePts,meta.partialLevel,meta.riskPercent);
         FileClose(handle);
      }
   }

public:
   ExitEngine(): m_count(0), m_trailMultiplier(2.5), m_timeCutoffHours(15.0)
   {
   }

   void Configure(const double trailMultiplier,const double timeCutoffHours)
   {
     m_trailMultiplier = trailMultiplier;
     m_timeCutoffHours = timeCutoffHours;
   }

   void Register(const ulong ticket,const EntrySignal &signal,const double slPoints,const double volume,const double riskPercent)
   {
      if(m_count>=ArraySize(m_positions))
         return;
      TradeMetadata meta;
      meta.ticket = ticket;
      meta.direction = signal.direction;
      meta.entryPrice = signal.entryPrice;
      meta.atrEntry = signal.atr;
      meta.slDistancePts = slPoints;
      meta.partialLevel = signal.partialLevel;
      meta.partialDone = false;
      meta.openTime = TimeCurrent();
      meta.family = signal.family;
      meta.regime = signal.regime;
      meta.session = signal.session;
      meta.highWater = signal.entryPrice;
      meta.lowWater  = signal.entryPrice;
      meta.riskPercent = riskPercent;
      m_positions[m_count++] = meta;
      LogRegistration(meta,volume);
   }

   double OnPositionClosed(const ulong ticket)
   {
      double risk=0.0;
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

   void Manage(BrokerUtils &broker,const PositionSizer &sizer,const RegimeFilter &regime)
   {
      double ask = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      double bid = SymbolInfoDouble(_Symbol,SYMBOL_BID);
      double atr = regime.AtrH1();
      for(int i=m_count-1;i>=0;i--)
      {
         TradeMetadata &meta = m_positions[i];
         if(!PositionSelectByTicket(meta.ticket))
            continue;
         double volume = PositionGetDouble(POSITION_VOLUME);
         double currentPrice = (meta.direction>0 ? bid : ask);
         meta.highWater = (meta.direction>0 ? MathMax(meta.highWater,currentPrice) : meta.highWater);
         meta.lowWater  = (meta.direction<0 ? MathMin(meta.lowWater,currentPrice) : meta.lowWater);

         if(!meta.partialDone && volume>=2.0*sizer.Context().minLot)
         {
            if( (meta.direction>0 && currentPrice>=meta.partialLevel) || (meta.direction<0 && currentPrice<=meta.partialLevel) )
            {
               double partialVolume = sizer.NormalizeVolume(volume*0.5);
               if(partialVolume>0.0 && partialVolume<volume)
               {
                  if(broker.ClosePartial(meta.ticket,partialVolume))
                  {
                     double breakEven = meta.entryPrice;
                     broker.ModifySL(meta.ticket,breakEven);
                     meta.partialDone = true;
                  }
               }
            }
         }

         if(atr>0.0)
         {
            double extreme = (meta.direction>0 ? meta.highWater : meta.lowWater);
            double newSL = extreme - meta.direction*m_trailMultiplier*atr;
            double currentSL = PositionGetDouble(POSITION_SL);
            if(meta.direction>0)
            {
               if(newSL>currentSL && newSL<meta.entryPrice)
                  broker.ModifySL(meta.ticket,newSL);
               else if(meta.partialDone && newSL>currentSL)
                  broker.ModifySL(meta.ticket,MathMax(newSL,meta.entryPrice));
            }
            else
            {
               if(newSL<currentSL && newSL>meta.entryPrice)
                  broker.ModifySL(meta.ticket,newSL);
               else if(meta.partialDone && newSL<currentSL)
                  broker.ModifySL(meta.ticket,MathMin(newSL,meta.entryPrice));
            }
         }

         if(TimeCurrent()-meta.openTime >= (int)(m_timeCutoffHours*3600.0))
         {
            broker.ClosePosition(meta.ticket);
            continue;
         }
      }
   }
};
