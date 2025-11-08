#ifndef __EA_TRADE_MANAGEMENT_MQH__
#define __EA_TRADE_MANAGEMENT_MQH__

#include "EAGlobals.mqh"
#include "entries.mqh"
#include "exits.mqh"

int BarsSinceEntry(const ulong ticket)
{
   if(ticket==0)
      return 9999;
   if(!PositionSelectByTicket(ticket))
      return 9999;
   datetime openTime=(datetime)PositionGetInteger(POSITION_TIME);
   int shift=iBarShift(gConfig.symbol,gConfig.tfEntry,openTime,true);
   return (shift<0?9999:shift);
}

double HoursSinceEntry(const ulong ticket)
{
   if(ticket==0)
      return 1e6;
   if(!PositionSelectByTicket(ticket))
      return 1e6;
   datetime openTime=(datetime)PositionGetInteger(POSITION_TIME);
   return (TimeCurrent()-openTime)/3600.0;
}

bool ReachedBreakEven(const ulong ticket)
{
   if(ticket==0)
      return false;
   if(!PositionSelectByTicket(ticket))
      return false;
   double openPrice=PositionGetDouble(POSITION_PRICE_OPEN);
   double curSL    =PositionGetDouble(POSITION_SL);
   long type       =PositionGetInteger(POSITION_TYPE);
   if(type==POSITION_TYPE_BUY)
      return (curSL>=openPrice && curSL!=0.0);
   if(type==POSITION_TYPE_SELL)
      return (curSL<=openPrice && curSL!=0.0);
   return false;
}

double ComputeRiskPerLotValue(const double riskPts,const double point)
{
   if(riskPts<=0.0 || point<=0.0)
      return 0.0;
   double tickValue=0.0,tickSize=0.0;
   if(!GetSymbolDouble(SYMBOL_TRADE_TICK_VALUE,tickValue,"tick_value") ||
      !GetSymbolDouble(SYMBOL_TRADE_TICK_SIZE,tickSize,"tick_size") ||
      tickSize<=0.0)
      return 0.0;
   double riskPrice=riskPts*point;
   return (riskPrice/tickSize)*tickValue;
}

double GetMAEinATR(const ulong ticket)
{
   int idx=FindMemoIndex(ticket);
   if(idx<0)
      return 0.0;
   if(positionMemos[idx].entryAtrPoints<=0.0)
      return 0.0;
   return (positionMemos[idx].worstAdversePts/positionMemos[idx].entryAtrPoints);
}

void MarkRunnerMode(const ulong ticket,const bool enable)
{
   int idx=FindMemoIndex(ticket);
   if(idx<0)
      return;
   positionMemos[idx].runnerMode = enable;
}

bool IsRunnerMode(const ulong ticket)
{
   int idx=FindMemoIndex(ticket);
   if(idx<0)
      return false;
   return positionMemos[idx].runnerMode;
}

bool SetATRTrailing(const ulong ticket,const double atrMult)
{
   if(ticket==0 || atrMult<=0.0)
      return false;
   if(!PositionSelectByTicket(ticket))
      return false;

   double point=0.0;
   if(!GetSymbolDouble(SYMBOL_POINT,point,"point") || point<=0.0)
      return false;

   double atr=0.0;
   if(!CopyAt(hATR_H4,0,0,atr,"ATR trail runner") || atr<=0.0)
      return false;

   double bid=0.0,ask=0.0;
   if(!GetBidAsk(bid,ask))
      return false;

   double curSL = PositionGetDouble(POSITION_SL);
   double curTP = PositionGetDouble(POSITION_TP);
   long   type  = PositionGetInteger(POSITION_TYPE);
   double dist  = atrMult*(atr/point)*point;

   if(type==POSITION_TYPE_BUY)
   {
      double proposed = bid - dist;
      double newSL = (curSL==0.0?proposed:MathMax(curSL,proposed));
      if(newSL>curSL)
         return trade.PositionModify(gConfig.symbol,newSL,curTP);
      return true;
   }
   else if(type==POSITION_TYPE_SELL)
   {
      double proposed = ask + dist;
      double newSL = (curSL==0.0?proposed:MathMin(curSL,proposed));
      if(newSL<curSL || curSL==0.0)
         return trade.PositionModify(gConfig.symbol,newSL,curTP);
      return true;
   }
   return false;
}

double ComputeRMultiple(const int memoIndex,const double progressPts)
{
   if(memoIndex<0 || memoIndex>=ArraySize(positionMemos))
      return 0.0;
   double initialRisk=positionMemos[memoIndex].initialRiskPoints;
   if(initialRisk<=0.0)
      return 0.0;
   return (progressPts/initialRisk);
}

int BarsSinceOpen(void)
{
   if(!PositionSelect(gConfig.symbol))
      return 9999;
   datetime openTime=(datetime)PositionGetInteger(POSITION_TIME);
   int shift=iBarShift(gConfig.symbol,gConfig.tfEntry,openTime,true);
   return (shift<0?9999:shift);
}

void RefreshPositionMemos(void)
{
   for(int i=ArraySize(positionMemos)-1;i>=0;--i)
   {
      if(!PositionSelectByTicket(positionMemos[i].ticket))
      {
         double point=0.0;
         double profitPts=0.0;
         if(GetSymbolDouble(SYMBOL_POINT,point,"point") && point>0.0)
         {
            if(HistorySelect(positionMemos[i].openTime-86400,TimeCurrent()))
            {
               for(int d=HistoryDealsTotal()-1;d>=0;--d)
               {
                  ulong dealTicket=HistoryDealGetTicket(d);
                  if((ulong)HistoryDealGetInteger(dealTicket,DEAL_POSITION_ID)!=positionMemos[i].ticket)
                     continue;
                  int entry=(int)HistoryDealGetInteger(dealTicket,DEAL_ENTRY);
                  if(entry==DEAL_ENTRY_OUT || entry==DEAL_ENTRY_INOUT)
                  {
                     double price=HistoryDealGetDouble(dealTicket,DEAL_PRICE);
                     int dir=positionMemos[i].direction;
                     if(dir==0)
                        dir=1;
                     profitPts = dir>0 ? (price-positionMemos[i].openPrice)/point : (positionMemos[i].openPrice-price)/point;
                     break;
                  }
               }
            }
         }
         UpdateMemoExcursions(i,profitPts);
         RecordCompletedTrade(positionMemos[i],profitPts);
         RemoveMemo(positionMemos[i].ticket);
      }
   }
}

void EnterTrade(const ENUM_ORDER_TYPE type,const bool isAddon,const EntrySignal &signal)
{
   if(OpenPositionsByMagic()>=gConfig.maxOpenPositions)
      return;

   double point=0.0;
   if(!GetSymbolDouble(SYMBOL_POINT,point,"point") || point<=0.0)
      return;

   double bid=0.0,ask=0.0;
   if(!GetBidAsk(bid,ask))
      return;

   double atr=0.0;
   if(!CopyAt(hATR_H4,0,0,atr,"ATR H4") || atr<=0.0)
   {
      PrintDebug("Enter: ATR(H4) not ready");
      return;
   }

   double atrPts=atr/point;
   lastKnownAtrEntryPoints=(signal.atrEntryPts>0.0?signal.atrEntryPts:atrPts);

    double regimeAdj = (gRegime==REG_HIGH?1.10:(gRegime==REG_LOW?0.9:1.0));
    double slMult = 2.2;
    if(Aggressiveness<=0)
       slMult = 2.5;
    else if(Aggressiveness>=2)
       slMult = 1.9;
    slMult *= regimeAdj;
    slMult = MathMax(1.6,MathMin(3.0,slMult));

    double tpMult = (gPreset.useTP ? slMult*1.5 : 0.0);

   double price = (type==ORDER_TYPE_BUY ? ask : bid);
   double slPts = slMult*atrPts;
   double tpPts = tpMult*atrPts;

   double sl = (type==ORDER_TYPE_BUY ? price - slPts*point : price + slPts*point);
   double tp = (type==ORDER_TYPE_BUY ? price + tpPts*point : price - tpPts*point);

   long stopLevel=0;
   if(!GetSymbolInteger(SYMBOL_TRADE_STOPS_LEVEL,stopLevel,"stop_level"))
      stopLevel=0;
   double minStopDist = MathMax(stopLevel*point,gConfig.minStopBufferAtr*atr);
   if(MathAbs(price-sl)<minStopDist)
   {
      PrintDebug("Enter: stop distance below broker minimum");
      return;
   }

   double lots = CalcRiskLots(sl,type,isAddon);
   lots = NormalizeLots(lots);
   if(lots<=0.0)
      return;

   const string comment = isAddon ? "XAU_Swing_ADD" : "XAU_Swing_BASE";
   bool placed=false;
   for(int attempt=0;attempt<3 && !placed;++attempt)
   {
      if(attempt>0)
      {
         if(!GetBidAsk(bid,ask))
            return;
         price = (type==ORDER_TYPE_BUY ? ask : bid);
         sl = (type==ORDER_TYPE_BUY ? price - slPts*point : price + slPts*point);
         tp = (type==ORDER_TYPE_BUY ? price + tpPts*point : price - tpPts*point);
      }
      trade.SetDeviationInPoints(20);
      if(trade.PositionOpen(gConfig.symbol,type,lots,price,sl,tp,comment))
      {
         placed=true;
         break;
      }
      int err=_LastError;
      if(err!=ERR_REQUOTE && err!=ERR_PRICE_CHANGED && err!=ERR_OFF_QUOTES)
      {
         PrintDebug(StringFormat("Enter failed err=%d",err));
         break;
      }
      Sleep(100);
   }

   if(!placed)
      return;

   lastEntryBarTime = lastBarTime;
   didPartialClose  = false;

   if(!isAddon)
   {
      lastBaseOpenPrice = price;
      lastBaseLots      = lots;
      addonsOpened      = 0;
   }
   else
   {
      addonsOpened++;
   }

   if(PositionSelect(gConfig.symbol))
   {
      ulong ticket=(ulong)PositionGetInteger(POSITION_TICKET);
      double openPrice=PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL=PositionGetDouble(POSITION_SL);
      double volume=PositionGetDouble(POSITION_VOLUME);
      double riskPts=MathAbs(openPrice-curSL)/point;
      if(riskPts<=0.0)
         riskPts=slPts;
      long posType=PositionGetInteger(POSITION_TYPE);
      int memoDir = (posType==POSITION_TYPE_BUY ? 1 : -1);
      double riskPerLot=ComputeRiskPerLotValue(riskPts,point);
      UpsertMemo(ticket,riskPts,atrPts,lastBarTime,isAddon,openPrice,memoDir,volume,riskPerLot);
   }

   PrintDebug(isAddon?"Addon opened":"Base opened");
}

double CalcRiskLots(const double slPrice,const ENUM_ORDER_TYPE type,const bool isAddon)
{
   if(gConfig.useFixedLots)
   {
      double base=gConfig.fixedLots;
      return (isAddon ? MathMin(base*0.5,base) : base);
   }

   double balance = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskAmt = balance*(gConfig.riskPerTradePct/100.0);

   double bid=0.0,ask=0.0;
   if(!GetBidAsk(bid,ask))
      return 0.0;

   double price = (type==ORDER_TYPE_BUY ? ask : bid);

   double tickValue=0.0,tickSize=0.0;
   if(!GetSymbolDouble(SYMBOL_TRADE_TICK_VALUE,tickValue,"tick_value") ||
      !GetSymbolDouble(SYMBOL_TRADE_TICK_SIZE,tickSize,"tick_size"))
      return 0.0;

   double distance = MathAbs(price-slPrice);
   if(distance<=0.0 || tickSize<=0.0 || tickValue<=0.0)
      return 0.0;

   double lots = riskAmt / ((distance/tickSize)*tickValue);
   if(isAddon)
   {
      double remaining = MathMax(0.0,(gPreset.addonMaxTotalRiskMult - (1.0+addonsOpened)));
      if(remaining<=0.0)
         return 0.0;
      double cap = (lastBaseLots>0.0 ? lastBaseLots*MathMax(0.2,remaining) : lots*remaining);
      lots=MathMin(lots,cap);
   }

   double scale = MathMax(0.2,MathMin(1.0,gRiskScale));
   lots *= scale;

   return lots;
}

void ManagePosition(void)
{
   RefreshPositionMemos();
   TryOpenAddonIfEligible();

   if(!PositionSelect(gConfig.symbol))
      return;

   ulong ticket=(ulong)PositionGetInteger(POSITION_TICKET);
   long type=PositionGetInteger(POSITION_TYPE);
   double openPrice=PositionGetDouble(POSITION_PRICE_OPEN);
   int memoIndex=FindMemoIndex(ticket);

   if(FridayFlatWindow())
   {
      double pointFlat=0.0;
      double progressFlat=0.0;
      if(GetSymbolDouble(SYMBOL_POINT,pointFlat,"point") && pointFlat>0.0)
      {
         double bidFlat=0.0,askFlat=0.0;
         if(GetBidAsk(bidFlat,askFlat))
         {
            double midFlat=(bidFlat+askFlat)*0.5;
            progressFlat = (type==POSITION_TYPE_BUY ? (midFlat-openPrice)/pointFlat : (openPrice-midFlat)/pointFlat);
         }
      }
      if(trade.PositionClose(gConfig.symbol))
      {
         if(memoIndex>=0)
         {
            UpdateMemoExcursions(memoIndex,progressFlat);
            RecordCompletedTrade(positionMemos[memoIndex],progressFlat);
         }
         RemoveMemo(ticket);
      }
      didPartialClose=false;
      addonsOpened=0;
      lastBaseOpenPrice=0.0;
      lastBaseLots=0.0;
      return;
   }

   if(BarsSinceOpen()<gConfig.minHoldBars)
      return;

   double point=0.0;
   if(!GetSymbolDouble(SYMBOL_POINT,point,"point") || point<=0.0)
      return;

   double atr=0.0;
   if(!CopyAt(hATR_H4,0,0,atr,"ATR H4 manage") || atr<=0.0)
      return;

   double atrPts=atr/point;

   double curSL=PositionGetDouble(POSITION_SL);
   double curTP=PositionGetDouble(POSITION_TP);
   double volume=PositionGetDouble(POSITION_VOLUME);

   if(memoIndex<0)
   {
      double riskPtsTemp=MathAbs(openPrice-curSL)/point;
      double riskPerLot=ComputeRiskPerLotValue(riskPtsTemp,point);
      UpsertMemo(ticket,riskPtsTemp,atrPts,lastBarTime,false,openPrice,(type==POSITION_TYPE_BUY?1:-1),volume,riskPerLot);
   }

   memoIndex=FindMemoIndex(ticket);
   double initialRiskPts = (memoIndex>=0 ? positionMemos[memoIndex].initialRiskPoints : MathAbs(openPrice-curSL)/point);
   if(initialRiskPts<=0.0)
      initialRiskPts=MathAbs(openPrice-curSL)/point;
   if(memoIndex>=0 && positionMemos[memoIndex].direction==0)
      positionMemos[memoIndex].direction=(type==POSITION_TYPE_BUY?1:-1);
   if(memoIndex>=0)
      positionMemos[memoIndex].lastKnownVolume = volume;

   double bid=0.0,ask=0.0;
   if(!GetBidAsk(bid,ask))
      return;
   double mid=(bid+ask)*0.5;
   double emaEntry=0.0;
   CopyAt(hEMA_E,0,1,emaEntry,"EMA manage entry");

   double adx=0.0;
   bool adxPass = ADX_OK(adx);
   bool adxAvailable = (adxPass || adx>0.0);
   double adxPrev=0.0;
   CopyAt(hADX_H4,0,2,adxPrev,"ADX prev manage");
   int trendDir = TrendDirection();
   bool confirmOk = HTFConfirmOk(trendDir);

   bool closeByTrend=false;
   if(trendDir!=0 && confirmOk)
   {
      if(type==POSITION_TYPE_BUY && trendDir<0)
         closeByTrend=true;
      else if(type==POSITION_TYPE_SELL && trendDir>0)
         closeByTrend=true;
   }

   bool closeByAdx = (adxAvailable && adx<gConfig.minAdxH4);
   double progressPts = (type==POSITION_TYPE_BUY ? (mid-openPrice)/point : (openPrice-mid)/point);
   UpdateMemoExcursions(memoIndex,progressPts);
   double rMultiple = ComputeRMultiple(memoIndex,progressPts);

   int barsSinceEntry = BarsSinceEntry(ticket);
   double maeAtr = GetMAEinATR(ticket);
   bool reachedBE = ReachedBreakEven(ticket);

   if(InpUseSoftStop && barsSinceEntry<=InpSoftStop_Bars && maeAtr>=InpSoftStop_MAE_ATR && ADXDeclining(adx,adxPrev))
   {
      PrintDebug(StringFormat("SoftStop: MAE=%.2f ATR, bars=%d",maeAtr,barsSinceEntry));
      if(trade.PositionClose(gConfig.symbol))
      {
         if(memoIndex>=0)
            RecordCompletedTrade(positionMemos[memoIndex],progressPts);
         RemoveMemo(ticket);
         didPartialClose   = false;
         addonsOpened      = 0;
         lastBaseOpenPrice = 0.0;
         lastBaseLots      = 0.0;
      }
      return;
   }

   if(InpUseTimeStop && HoursSinceEntry(ticket)>=InpTimeStop_Hours && !reachedBE)
   {
      PrintDebug(StringFormat("TimeStop: no BE after %d hours",InpTimeStop_Hours));
      if(trade.PositionClose(gConfig.symbol))
      {
         if(memoIndex>=0)
            RecordCompletedTrade(positionMemos[memoIndex],progressPts);
         RemoveMemo(ticket);
         didPartialClose   = false;
         addonsOpened      = 0;
         lastBaseOpenPrice = 0.0;
         lastBaseLots      = 0.0;
      }
      return;
   }

   if(closeByTrend || closeByAdx)
   {
      if(trade.PositionClose(gConfig.symbol))
      {
         if(memoIndex>=0)
            RecordCompletedTrade(positionMemos[memoIndex],progressPts);
         RemoveMemo(ticket);
         didPartialClose   = false;
         addonsOpened      = 0;
         lastBaseOpenPrice = 0.0;
         lastBaseLots      = 0.0;
      }
      return;
   }

   if(gConfig.breakEvenMode!=BREAK_EVEN_OFF)
   {
      double triggerPts=0.0;
      if(gConfig.breakEvenMode==BREAK_EVEN_ATR)
         triggerPts=gConfig.breakEvenAtr*atrPts;
      else if(gConfig.breakEvenMode==BREAK_EVEN_R_BASED)
         triggerPts=gConfig.breakEvenR*initialRiskPts;

      if(triggerPts>0.0 && progressPts>=triggerPts)
      {
         if(type==POSITION_TYPE_BUY && (curSL==0.0 || curSL<openPrice))
            trade.PositionModify(gConfig.symbol,openPrice,curTP);
         if(type==POSITION_TYPE_SELL && (curSL==0.0 || curSL>openPrice))
            trade.PositionModify(gConfig.symbol,openPrice,curTP);
      }
   }

   if(gConfig.partialCloseEnable && !didPartialClose && gConfig.partialClosePct>0.0 && initialRiskPts>0.0)
   {
      bool isLong = (type==POSITION_TYPE_BUY);
      if(ShouldTriggerPartial(rMultiple,adx,adxPrev,isLong,emaEntry,mid))
      {
         double minVol,maxVol,step;
         if(GetVolumeLimits(minVol,maxVol,step))
         {
            double closeVol = volume*(gConfig.partialClosePct/100.0);
            if(step>0.0)
               closeVol=MathFloor((closeVol+1e-12)/step)*step;
            if(closeVol>=minVol && closeVol<volume)
            {
               if(trade.PositionClosePartial(gConfig.symbol,closeVol))
               {
                  didPartialClose=true;
                  if(PositionSelect(gConfig.symbol) && memoIndex>=0)
                     positionMemos[memoIndex].lastKnownVolume = PositionGetDouble(POSITION_VOLUME);
                  if(memoIndex>=0)
                     MarkRunnerMode(ticket,true);
                  double bePrice = BreakEvenPlus(openPrice,initialRiskPts,(type==POSITION_TYPE_BUY?1:-1));
                  double curTP = PositionGetDouble(POSITION_TP);
                  trade.PositionModify(gConfig.symbol,bePrice,curTP);
               }
            }
         }
      }
   }

   if(InpUseRunnerTrail && memoIndex>=0 && IsRunnerMode(ticket) && rMultiple>=2.5)
   {
      if(SetATRTrailing(ticket,gConfig.atrTrailMult))
      {
         MarkRunnerMode(ticket,false);
         PrintDebug("Runner trail reverted to default");
      }
   }

   if(gConfig.maxHoldBars>0)
   {
      int bars=BarsSinceOpen();
      if(bars>=gConfig.maxHoldBars)
      {
         double atrMultiple = (atrPts>0.0 ? progressPts/atrPts : 0.0);
         if(atrMultiple<1.5)
         {
            if(trade.PositionClose(gConfig.symbol))
            {
               if(memoIndex>=0)
                  RecordCompletedTrade(positionMemos[memoIndex],progressPts);
               RemoveMemo(ticket);
               didPartialClose=false;
               addonsOpened=0;
               lastBaseLots=0.0;
               lastBaseOpenPrice=0.0;
            }
            return;
         }
      }
   }

   if(gConfig.trailingMode==TRAIL_ATR)
   {
      double trailDist=gConfig.atrTrailMult*atrPts*point;
      if(type==POSITION_TYPE_BUY)
      {
         double proposed=bid-trailDist;
         double newSL=(curSL==0.0?proposed:MathMax(curSL,proposed));
         if(newSL>curSL)
            trade.PositionModify(gConfig.symbol,newSL,curTP);
      }
      else if(type==POSITION_TYPE_SELL)
      {
         double proposed=ask+trailDist;
         double newSL=(curSL==0.0?proposed:MathMin(curSL,proposed));
         if(newSL<curSL || curSL==0.0)
            trade.PositionModify(gConfig.symbol,newSL,curTP);
      }
   }
   else if(gConfig.trailingMode==TRAIL_FRACTAL)
   {
      double up[],dn[];
      ArraySetAsSeries(up,true);
      ArraySetAsSeries(dn,true);
      if(CopyBuffer(hFractals,0,2+gConfig.fractalShiftBars,1,up)==1 &&
         CopyBuffer(hFractals,1,2+gConfig.fractalShiftBars,1,dn)==1)
      {
         if(type==POSITION_TYPE_BUY && dn[0]>0.0)
         {
            double newSL=(curSL==0.0?dn[0]:MathMax(curSL,dn[0]));
            if(newSL>curSL)
               trade.PositionModify(gConfig.symbol,newSL,curTP);
         }
         if(type==POSITION_TYPE_SELL && up[0]>0.0)
         {
            double newSL=(curSL==0.0?up[0]:MathMin(curSL,up[0]));
            if(newSL<curSL || curSL==0.0)
               trade.PositionModify(gConfig.symbol,newSL,curTP);
         }
      }
   }
   else if(gConfig.trailingMode==TRAIL_CHANDELIER)
   {
      int lookback=MathMin(200,MathMax(3,BarsSinceOpen()+1));
      double highs[],lows[];
      ArraySetAsSeries(highs,true);
      ArraySetAsSeries(lows,true);
      if(CopyHigh(gConfig.symbol,gConfig.tfEntry,1,lookback,highs)==lookback &&
         CopyLow(gConfig.symbol,gConfig.tfEntry,1,lookback,lows)==lookback)
      {
         double extremeHigh=highs[0];
         double extremeLow =lows[0];
         for(int i=1;i<lookback;++i)
         {
            if(highs[i]>extremeHigh) extremeHigh=highs[i];
            if(lows[i]<extremeLow)    extremeLow =lows[i];
         }
         bool isAddonMemo = (memoIndex>=0 && positionMemos[memoIndex].isAddon);
         double trailK = RunnerTrailK(isAddonMemo);
         double trailDist=trailK*atrPts*point;
         if(type==POSITION_TYPE_BUY)
         {
            double proposed=extremeHigh-trailDist;
            double newSL=(curSL==0.0?proposed:MathMax(curSL,proposed));
            if(newSL>curSL)
               trade.PositionModify(gConfig.symbol,newSL,curTP);
         }
         else if(type==POSITION_TYPE_SELL)
         {
            double proposed=extremeLow+trailDist;
            double newSL=(curSL==0.0?proposed:MathMin(curSL,proposed));
            if(newSL<curSL || curSL==0.0)
               trade.PositionModify(gConfig.symbol,newSL,curTP);
         }
      }
   }
}

void TryOpenAddonIfEligible(void)
{
   if(!gConfig.allowPyramiding)
      return;
   if(addonsOpened>=gConfig.maxAddonsPerBase)
      return;
   if(OpenPositionsByMagic()>=gConfig.maxOpenPositions)
      return;

   if(!PositionSelect(gConfig.symbol))
      return;

   if(lastBaseOpenPrice<=0.0 || lastBaseLots<=0.0)
      return;

   long type=PositionGetInteger(POSITION_TYPE);
   double curSL=PositionGetDouble(POSITION_SL);
   double openPrice=PositionGetDouble(POSITION_PRICE_OPEN);

   bool atBE=(type==POSITION_TYPE_BUY ? (curSL>=openPrice && curSL!=0.0) : (curSL!=0.0 && curSL<=openPrice));
   if(!atBE)
      return;

   double point=0.0;
   if(!GetSymbolDouble(SYMBOL_POINT,point,"point") || point<=0.0)
      return;

   double atr=0.0;
   if(!CopyAt(hATR_H4,0,0,atr,"ATR H4 addon") || atr<=0.0)
      return;

   double atrPts=atr/point;
   double bid=0.0,ask=0.0;
   if(!GetBidAsk(bid,ask))
      return;

   int memoIndex=FindMemoIndex((ulong)PositionGetInteger(POSITION_TICKET));
   if(memoIndex<0)
      return;

   double baseRisk = positionMemos[memoIndex].initialRiskPoints;
   if(baseRisk<=0.0)
      return;
   double mfeR = positionMemos[memoIndex].bestFavourablePts/baseRisk;
   double maeR = positionMemos[memoIndex].worstAdversePts/baseRisk;
   if(mfeR<1.0 || maeR>0.6)
      return;

   double totalRiskMult = 1.0 + addonsOpened;
   if(totalRiskMult>=gPreset.addonMaxTotalRiskMult)
      return;

   int votesUp=0,votesDown=0,dir=0;
   if(!ComputeTrendVotes(dir,votesUp,votesDown))
      return;

   double adx=0.0;
   if(!CopyAt(hADX_H4,0,1,adx,"ADX addon"))
      return;
   if(adx<gPreset.adxMin+2.0)
      return;

   int baseDir = (type==POSITION_TYPE_BUY ? +1 : -1);
   if(dir!=baseDir)
      return;

   double stepDist = gPreset.addonStepATR*atrPts*point;

   EntrySignal addonSignal;
   addonSignal.direction = baseDir;
   addonSignal.adxValue  = adx;
   addonSignal.atrEntryPts = atrPts;
   addonSignal.breakoutLevel = (baseDir>0?ask:bid);

   if(type==POSITION_TYPE_BUY)
   {
      if((ask-lastBaseOpenPrice) < (addonsOpened+1)*stepDist)
         return;
      EnterTrade(ORDER_TYPE_BUY,true,addonSignal);
   }
   else if(type==POSITION_TYPE_SELL)
   {
      if((lastBaseOpenPrice-bid) < (addonsOpened+1)*stepDist)
         return;
      EnterTrade(ORDER_TYPE_SELL,true,addonSignal);
   }
}

#endif // __EA_TRADE_MANAGEMENT_MQH__

