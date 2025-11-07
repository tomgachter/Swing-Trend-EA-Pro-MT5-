#ifndef __EA_MARKET_UTILS_MQH__
#define __EA_MARKET_UTILS_MQH__

#include "EAGlobals.mqh"

void PrintDebug(const string text)
{
   if(gConfig.debug)
      Print(text);
}

bool GetSymbolDouble(const ENUM_SYMBOL_INFO_DOUBLE prop,double &value,const string tag)
{
   if(SymbolInfoDouble(gConfig.symbol,prop,value))
      return true;
   if(gConfig.debug)
      PrintFormat("SymbolInfoDouble failed [%s] prop=%d err=%d",tag,(int)prop,_LastError);
   return false;
}

bool GetSymbolInteger(const ENUM_SYMBOL_INFO_INTEGER prop,long &value,const string tag)
{
   if(SymbolInfoInteger(gConfig.symbol,prop,value))
      return true;
   if(gConfig.debug)
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

bool IsNewBar(const ENUM_TIMEFRAMES tf)
{
   MqlRates rates[];
   ArraySetAsSeries(rates,true);
   if(CopyRates(gConfig.symbol,tf,0,2,rates)<2)
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
      if(gConfig.debug)
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
      if(gConfig.debug)
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
   long isFloat=0;
   GetSymbolInteger(SYMBOL_SPREAD_FLOAT,isFloat,"spread_float");
   spread=(int)raw;
   if(isFloat!=0)
   {
      double bid=0.0,ask=0.0,point=0.0;
      if(GetBidAsk(bid,ask) && GetSymbolDouble(SYMBOL_POINT,point,"point"))
      {
         double floatSpread=(ask-bid)/point;
         spread=(int)MathRound(floatSpread);
      }
   }
   return (spread<=gConfig.maxSpreadPoints);
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

   if(dayLoss>=gConfig.dailyLossStopPct)
      return false;
   if(dd>=gConfig.maxDrawdownPct)
      return false;
   return true;
}

bool RegimeOK(double &atrD1pts)
{
   double point=0.0;
   if(!GetSymbolDouble(SYMBOL_POINT,point,"point") || point<=0.0)
      return false;

   double atr=0.0;
   if(!CopyAt(hATR_D1,0,0,atr,"ATR D1") || atr<=0.0)
      return false;

   double currentAtrD1pts = atr/point;
   if(currentAtrD1pts<gConfig.atrD1MinPts || currentAtrD1pts>gConfig.atrD1MaxPts)
      return false;

   atrD1pts = currentAtrD1pts;
   // Persist the last valid regime reading for downstream management fallbacks.
   lastValidAtrD1Pts = atrD1pts;

   return true;
}

bool ADX_OK(double &adxOut)
{
   adxOut=0.0;
   if(!CopyAt(hADX_H4,0,1,adxOut,"ADX"))
      return false;
   return (adxOut>=gConfig.minAdxH4);
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
      if(gConfig.debug)
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
   int shift=gConfig.useClosedBarTrend?1:0;
   double ma1,ma2,ma3,p1,p2,p3;
   if(!CopyAt(hEMA_T1,0,shift,ma1,"EMA trend1")) return 0;
   if(!CopyAt(hEMA_T2,0,shift,ma2,"EMA trend2")) return 0;
   if(!CopyAt(hEMA_T3,0,shift,ma3,"EMA trend3")) return 0;
    if(!CopyCloseAt(gConfig.symbol,gConfig.tfTrend1,shift,p1,"Close trend1")) return 0;
    if(!CopyCloseAt(gConfig.symbol,gConfig.tfTrend2,shift,p2,"Close trend2")) return 0;
    if(!CopyCloseAt(gConfig.symbol,gConfig.tfTrend3,shift,p3,"Close trend3")) return 0;

   int up=0,down=0;
   if(p1>ma1) up++; else if(p1<ma1) down++;
   if(p2>ma2) up++; else if(p2<ma2) down++;
   if(p3>ma3) up++; else if(p3<ma3) down++;

   int need=MathMax(1,MathMin(3,gConfig.trendVotesRequired));
   if(up>=need && down<need)
      return +1;
   if(down>=need && up<need)
      return -1;
   return 0;
}

bool SlopeOkRelaxed(const int handle,const int shift,const int dir,const double adxH4)
{
   if(!gConfig.useSlopeFilter)
      return true;

   double emaNow,emaPrev;
   if(!CopyAt(handle,0,shift,emaNow,"Slope a") || !CopyAt(handle,0,shift+1,emaPrev,"Slope b"))
      return false;

   double point=0.0,atr=0.0;
   if(!GetSymbolDouble(SYMBOL_POINT,point,"point") || point<=0.0)
      return true;
   if(!CopyAt(hATR_Entry,0,shift,atr,"Slope ATR") || atr<=0.0)
      return true;

   double slopeNorm = (emaNow-emaPrev)/(atr);
   if(dir>0 && slopeNorm<gConfig.slopeMin)
      return (adxH4>=gConfig.minAdxH4+5.0);
   if(dir<0 && -slopeNorm<gConfig.slopeMin)
      return (adxH4>=gConfig.minAdxH4+5.0);
   return true;
}

bool ExtensionOk(double &distATR)
{
   distATR=0.0;
   double ema=0.0,close=0.0;
   if(!CopyAt(hEMA_E,0,1,ema,"EMA extension") || !CopyCloseAt(gConfig.symbol,gConfig.tfEntry,1,close,"Close extension"))
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
   return (distATR<=gConfig.maxExtensionAtr);
}

bool CooldownOk(void)
{
   if(gConfig.cooldownBars<=0 || lastEntryBarTime==0)
      return true;

   int shift=iBarShift(gConfig.symbol,gConfig.tfEntry,lastEntryBarTime,true);
   if(shift<0)
      return true;

   return (shift>=gConfig.cooldownBars);
}

bool SessionOk(void)
{
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(),timeStruct);
   int hour=AdjustedHour(timeStruct);
   bool s1=(hour>=gConfig.sess1StartHour && hour<gConfig.sess1EndHour);
   bool s2=(hour>=gConfig.sess2StartHour && hour<gConfig.sess2EndHour);
   return (s1||s2);
}

int AdjustedHour(const MqlDateTime &t)
{
   int hour=(t.hour+gConfig.tzOffsetHours)%24;
   if(hour<0)
      hour+=24;
   return hour;
}

bool EquityFilterOk(void)
{
   if(!gConfig.useEquityFilter)
      return true;

   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double limit = eqEMA*(1.0-gConfig.eqUnderwaterPct/100.0);
   return (equity>=limit);
}

void GetRegimeFactors(const double atrD1pts,int &donchianBars,double &slMult,double &tpMult)
{
   double pivot = MathMax(1.0,gConfig.atrD1Pivot);
   double factor = atrD1pts/pivot;
   factor = MathMin(gConfig.regimeMaxFactor,MathMax(gConfig.regimeMinFactor,factor));

   double base = gConfig.donchianBarsBase;
   double lower = MathMax(10.0,base-gConfig.donchianBarsMinMax);
   double upper = MathMax(lower,MathMin(30.0,base + gConfig.donchianBarsMinMax));
   double scaled = base*factor;
   scaled = MathMax(lower,MathMin(upper,scaled));
   donchianBars = (int)MathRound(scaled);

   slMult = gConfig.atrSlMultBase * factor;
   tpMult = gConfig.atrTpMultBase * factor;
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
      if(PositionGetString(POSITION_SYMBOL)!=gConfig.symbol)
         continue;
      if((int)PositionGetInteger(POSITION_MAGIC)!=gConfig.magic)
         continue;
      count++;
   }
   return count;
}

bool HTFConfirmOk(const int dir)
{
   if(!gConfig.useHTFConfirm || dir==0)
      return true;

   double emaNow,emaPrev;
   if(!CopyAt(hEMA_T1,0,0,emaNow,"HTF ema now") || !CopyAt(hEMA_T1,0,1,emaPrev,"HTF ema prev"))
      return false;

   double slope=emaNow-emaPrev;
   if(dir>0)
      return (slope>0.0);
   if(dir<0)
      return (slope<0.0);
   return true;
}

bool NewsFilterOk(void)
{
   // The FTMO swing setup operates without the MetaTrader economic
   // calendar feed.  To keep behaviour predictable we simply disable the
   // calendar-based block and allow trading to continue.
   return true;
}

bool FridayFlatWindow(void)
{
   if(!gConfig.flatOnFriday)
      return false;

   datetime now=TimeCurrent();
   MqlDateTime t;
   TimeToStruct(now,t);
   if(t.day_of_week!=5)
      return false;

   int minutes=t.hour*60+t.min;
   return (minutes>=gConfig.fridayFlatMinutes);
}


#endif // __EA_MARKET_UTILS_MQH__

