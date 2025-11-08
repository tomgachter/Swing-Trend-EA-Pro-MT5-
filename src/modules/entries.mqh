#ifndef __EA_ENTRIES_MQH__
#define __EA_ENTRIES_MQH__

#include "EAGlobals.mqh"
#include "MarketUtils.mqh"
#include "presets.mqh"
#include "utils.mqh"

struct EntrySignal
{
   int    direction;
   double adxValue;
   double atrEntryPts;
   double breakoutLevel;
};

bool ComputeTrendVotes(int &dir,int &votesUp,int &votesDown)
{
   int shift = gConfig.useClosedBarTrend?1:0;
   double ma1,ma2,ma3,p1,p2,p3;
   if(!CopyAt(hEMA_T1,0,shift,ma1,"EMA trend1")) return false;
   if(!CopyAt(hEMA_T2,0,shift,ma2,"EMA trend2")) return false;
   if(!CopyAt(hEMA_T3,0,shift,ma3,"EMA trend3")) return false;
   if(!CopyCloseAt(gConfig.symbol,gConfig.tfTrend1,shift,p1,"Close trend1")) return false;
   if(!CopyCloseAt(gConfig.symbol,gConfig.tfTrend2,shift,p2,"Close trend2")) return false;
   if(!CopyCloseAt(gConfig.symbol,gConfig.tfTrend3,shift,p3,"Close trend3")) return false;

   votesUp=0;
   votesDown=0;
   if(p1>ma1) votesUp++; else if(p1<ma1) votesDown++;
   if(p2>ma2) votesUp++; else if(p2<ma2) votesDown++;
   if(p3>ma3) votesUp++; else if(p3<ma3) votesDown++;

   if(votesUp>votesDown) dir=+1;
   else if(votesDown>votesUp) dir=-1;
   else dir=0;
   return true;
}

bool BuildEntrySignal(EntrySignal &signal)
{
   signal.direction=0;
   signal.adxValue=0.0;
   signal.atrEntryPts=0.0;
   signal.breakoutLevel=0.0;

   if(OpenPositionsByMagic()>=gConfig.maxOpenPositions)
      return false;

   double adx=0.0;
   if(!CopyAt(hADX_H4,0,1,adx,"ADX entry"))
      return false;
   signal.adxValue=adx;

   int votesUp=0,votesDown=0,dir=0;
   if(!ComputeTrendVotes(dir,votesUp,votesDown))
      return false;

   int required=gPreset.votesRequired;
   if(adx>=gPreset.adxMin || gRegime==REG_HIGH)
   {
      int reduced=MathMax(1,required-1);
      if(reduced!=required)
         PrintDebug(StringFormat("Votes reduced %d->%d adx=%.1f regime=%s",required,reduced,adx,EnumToString(gRegime)));
      required=reduced;
   }

   bool upOk = (votesUp>=required && votesDown<required);
   bool dnOk = (votesDown>=required && votesUp<required);
   if(!upOk && !dnOk)
      return false;

   signal.direction = upOk?+1:-1;

   double atrEntry=0.0;
   if(CopyAt(hATR_Entry,0,1,atrEntry,"ATR entry") && atrEntry>0.0)
      signal.atrEntryPts = atrEntry/SafePoint();

   int donBars = PresetDonchianBars(gPreset,gRegime);
   double hi,lo;
   if(!DonchianHL(gConfig.symbol,gConfig.tfEntry,MathMax(2,donBars),hi,lo))
      return false;

   double bufferAtr = PresetBufferATR(gPreset,gRegime);
   double atrBasis = signal.atrEntryPts>0.0?signal.atrEntryPts:lastKnownAtrEntryPoints;
   if(atrBasis<=0.0)
      atrBasis=1.0;
   double bufferPts = bufferAtr*atrBasis;
   double point = SafePoint();
   double bid=0.0,ask=0.0;
   if(!GetBidAsk(bid,ask))
      return false;

   double buyTrig = hi + bufferPts*point;
   double sellTrig = lo - bufferPts*point;

   if(signal.direction>0)
   {
      if(ask<buyTrig)
         return false;
      signal.breakoutLevel = buyTrig;
   }
   else
   {
      if(bid>sellTrig)
         return false;
      signal.breakoutLevel = sellTrig;
   }

   return true;
}

#endif // __EA_ENTRIES_MQH__
