#pragma once

//+------------------------------------------------------------------+
//| Utility and market helper functions                              |
//+------------------------------------------------------------------+
void PrintDebug(const string text)
{
   if(InpDebug)
      Print(text);
}

bool GetSymbolDouble(const ENUM_SYMBOL_INFO_DOUBLE prop,double &value,const string tag)
{
   if(SymbolInfoDouble(InpSymbol,prop,value))
      return true;
   if(InpDebug)
      PrintFormat("SymbolInfoDouble failed [%s] prop=%d err=%d",tag,(int)prop,_LastError);
   return false;
}

bool GetSymbolInteger(const ENUM_SYMBOL_INFO_INTEGER prop,long &value,const string tag)
{
   if(SymbolInfoInteger(InpSymbol,prop,value))
      return true;
   if(InpDebug)
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
   if(CopyRates(InpSymbol,tf,0,2,rates)<2)
   {
      PrintDebug("CopyRates failed in IsNewBar");
      return false;
   }

   if(lastBarTime==rates[0].time)
      return false;

   lastBarTime=rates[0].time;
   return true;
}

bool CopyAt(const int handle,const int buffer,const int shift,double &value,const string tag="")
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
      if(InpDebug)
         PrintFormat("CopyBuffer failed [%s] handle=%d buf=%d shift=%d err=%d",tag,handle,buffer,shift,_LastError);
      return false;
   }

   value=data[0];
   return true;
}

bool CopyCloseAt(const string symbol,const ENUM_TIMEFRAMES tf,const int shift,double &value,const string tag="")
{
   value=0.0;
   double closes[];
   int copied=CopyClose(symbol,tf,shift,1,closes);
   if(copied!=1)
   {
      if(InpDebug)
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
   spread=(int)raw;
   return (spread<=InpMaxSpreadPoints);
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

   if(dayLoss>=InpMaxDailyLossPct)
      return false;
   if(dd>=InpMaxDrawdownPct)
      return false;
   return true;
}

bool RegimeOK(double &atrD1pts)
{
   atrD1pts=0.0;
   double point=0.0;
   if(!GetSymbolDouble(SYMBOL_POINT,point,"point") || point<=0.0)
      return false;

   double atr=0.0;
   if(!CopyAt(hATR_D1,0,0,atr,"ATR D1") || atr<=0.0)
      return false;

   atrD1pts = atr/point;
   if(atrD1pts<InpATR_D1_MinPts || atrD1pts>InpATR_D1_MaxPts)
      return false;

   return true;
}

bool ADX_OK(double &adxOut)
{
   adxOut=0.0;
   if(!CopyAt(hADX_H4,0,1,adxOut,"ADX"))
      return false;
   return (adxOut>=InpMinADX_H4);
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
      if(InpDebug)
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
   int shift=InpUseClosedBarTrend?1:0;
   double ma1,ma2,ma3,p1,p2,p3;
   if(!CopyAt(hEMA_T1,0,shift,ma1,"EMA trend1")) return 0;
   if(!CopyAt(hEMA_T2,0,shift,ma2,"EMA trend2")) return 0;
   if(!CopyAt(hEMA_T3,0,shift,ma3,"EMA trend3")) return 0;
   if(!CopyCloseAt(InpSymbol,InpTF_Trend1,shift,p1,"Close trend1")) return 0;
   if(!CopyCloseAt(InpSymbol,InpTF_Trend2,shift,p2,"Close trend2")) return 0;
   if(!CopyCloseAt(InpSymbol,InpTF_Trend3,shift,p3,"Close trend3")) return 0;

   int up=0,down=0;
   if(p1>ma1) up++; else if(p1<ma1) down++;
   if(p2>ma2) up++; else if(p2<ma2) down++;
   if(p3>ma3) up++; else if(p3<ma3) down++;

   int need=MathMax(1,MathMin(3,InpTrendVotesRequired));
   if(up>=need && down<need)
      return +1;
   if(down>=need && up<need)
      return -1;
   return 0;
}

bool SlopeOkRelaxed(const int handle,const int shift,const int dir,const double adxH4)
{
   if(!InpUseSlopeFilter)
      return true;

   double a,b;
   if(!CopyAt(handle,0,shift,a,"Slope a") || !CopyAt(handle,0,shift+1,b,"Slope b"))
      return false;

   double slope=a-b;
   if(dir>0 && slope<=0.0)
      return (adxH4>=25.0);
   if(dir<0 && slope>=0.0)
      return (adxH4>=25.0);
   return true;
}

bool ExtensionOk(double &distATR)
{
   distATR=0.0;
   double ema=0.0,close=0.0;
   if(!CopyAt(hEMA_E,0,1,ema,"EMA extension") || !CopyCloseAt(InpSymbol,InpTF_Entry,1,close,"Close extension"))
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
   return (distATR<=InpMaxExtension_ATR);
}

bool CooldownOk(void)
{
   if(InpCooldownBars<=0 || lastEntryBarTime==0)
      return true;

   int shift=iBarShift(InpSymbol,InpTF_Entry,lastEntryBarTime,true);
   if(shift<0)
      return true;

   return (shift>=InpCooldownBars);
}

int OpenPositionsByMagic(void)
{
   int count=0;
   for(int i=PositionsTotal()-1;i>=0;--i)
   {
      ulong ticket=PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL)!=InpSymbol)
         continue;
      if((int)PositionGetInteger(POSITION_MAGIC)!=InpMagic)
         continue;
      count++;
   }
   return count;
}

int BarsSinceOpen(void)
{
   if(!PositionSelect(InpSymbol))
      return 9999;
   datetime openTime=(datetime)PositionGetInteger(POSITION_TIME);
   int shift=iBarShift(InpSymbol,InpTF_Entry,openTime,true);
   return (shift<0?9999:shift);
}

void ResetDailyAnchors(void)
{
   daySerialAnchor = (int)(TimeCurrent()/86400);
   dayStartEquity  = AccountInfoDouble(ACCOUNT_EQUITY);
}

bool SessionOk(void)
{
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(),timeStruct);
   int hour=AdjustedHour(timeStruct);
   bool s1=(hour>=InpSess1_StartHour && hour<InpSess1_EndHour);
   bool s2=(hour>=InpSess2_StartHour && hour<InpSess2_EndHour);
   return (s1||s2);
}

int AdjustedHour(const MqlDateTime &t)
{
   int hour=(t.hour+InpTZ_OffsetHours)%24;
   if(hour<0)
      hour+=24;
   return hour;
}

bool EquityFilterOk(void)
{
   if(!InpUseEquityFilter)
      return true;

   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double limit = eqEMA*(1.0-InpEqUnderwaterPct/100.0);
   return (equity>=limit);
}

void GetRegimeFactors(const double atrD1pts,int &donchianBars,double &slMult,double &tpMult)
{
   double pivot = MathMax(1.0,InpATR_D1_Pivot);
   double factor = atrD1pts/pivot;
   factor = MathMin(InpRegimeMaxFactor,MathMax(InpRegimeMinFactor,factor));

   double base = InpDonchianBars_Base;
   double lower = MathMax(2.0,base-InpDonchianBars_MinMax);
   double upper = base + InpDonchianBars_MinMax;
   double scaled = base*factor;
   scaled = MathMax(lower,MathMin(upper,scaled));
   donchianBars = (int)MathRound(scaled);

   slMult = InpATR_SL_mult_Base * factor;
   tpMult = InpATR_TP_mult_Base * factor;
}
