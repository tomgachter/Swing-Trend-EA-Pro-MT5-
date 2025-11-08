#ifndef __EA_TRADE_MANAGEMENT_MQH__
#define __EA_TRADE_MANAGEMENT_MQH__

#include "EAGlobals.mqh"

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

void EnterTrade(const ENUM_ORDER_TYPE type,const bool isAddon)
{
   if(OpenPositionsByMagic()>=gConfig.maxOpenPositions)
      return;

   double point=0.0;
   if(!GetSymbolDouble(SYMBOL_POINT,point,"point") || point<=0.0)
      return;

   double bid=0.0,ask=0.0;
   if(!GetBidAsk(bid,ask))
      return;

   double atrD1pts=0.0;
   if(!RegimeOK(atrD1pts))
   {
      PrintDebug("Enter: regime not ready");
      return;
   }

   int donBars=0;
   double slMult=0.0,tpMult=0.0;
   GetRegimeFactors(atrD1pts,donBars,slMult,tpMult);

   double atr=0.0;
   if(!CopyAt(hATR_H4,0,0,atr,"ATR H4") || atr<=0.0)
   {
      PrintDebug("Enter: ATR(H4) not ready");
      return;
   }

   double atrPts=atr/point;
   lastKnownAtrEntryPoints=atrPts;

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
      double riskPts=MathAbs(openPrice-curSL)/point;
      if(riskPts<=0.0)
         riskPts=slPts;
      long posType=PositionGetInteger(POSITION_TYPE);
      int memoDir = (posType==POSITION_TYPE_BUY ? 1 : -1);
      UpsertMemo(ticket,riskPts,atrPts,lastBarTime,isAddon,openPrice,memoDir);
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
      double cap = (lastBaseLots>0.0 ? lastBaseLots*0.5 : lots);
      lots=MathMin(lots,cap);
   }

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
      UpsertMemo(ticket,MathAbs(openPrice-curSL)/point,atrPts,lastBarTime,false,openPrice,(type==POSITION_TYPE_BUY?1:-1));

   memoIndex=FindMemoIndex(ticket);
   double initialRiskPts = (memoIndex>=0 ? positionMemos[memoIndex].initialRiskPoints : MathAbs(openPrice-curSL)/point);
   if(initialRiskPts<=0.0)
      initialRiskPts=MathAbs(openPrice-curSL)/point;
   if(memoIndex>=0 && positionMemos[memoIndex].direction==0)
      positionMemos[memoIndex].direction=(type==POSITION_TYPE_BUY?1:-1);

   double bid=0.0,ask=0.0;
   if(!GetBidAsk(bid,ask))
      return;
   double mid=(bid+ask)*0.5;

   double adx=0.0;
   bool adxPass = ADX_OK(adx);
   bool adxAvailable = (adxPass || adx>0.0);
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
      double rMultiple = progressPts/initialRiskPts;
      if(rMultiple>=gConfig.partialCloseR)
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
                  didPartialClose=true;
            }
         }
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
         double trailDist=gConfig.atrTrailMult*atrPts*point;
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

   int trendDir=TrendDirection();
   if(trendDir==0)
      return;

   double adxOut=0.0;
   if(!ADX_OK(adxOut))
      return;

   int baseDir = (type==POSITION_TYPE_BUY ? +1 : -1);
   if(trendDir!=baseDir)
      return;

   double stepDist = gConfig.addonStepAtr*atrPts*point;

   if(type==POSITION_TYPE_BUY)
   {
      if((ask-lastBaseOpenPrice) >= (addonsOpened+1)*stepDist)
         EnterTrade(ORDER_TYPE_BUY,true);
   }
   else if(type==POSITION_TYPE_SELL)
   {
      if((lastBaseOpenPrice-bid) >= (addonsOpened+1)*stepDist)
         EnterTrade(ORDER_TYPE_SELL,true);
   }
}

#endif // __EA_TRADE_MANAGEMENT_MQH__

