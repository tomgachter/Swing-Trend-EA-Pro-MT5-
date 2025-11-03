#pragma once

//+------------------------------------------------------------------+
//| Trade entry and management logic                                 |
//+------------------------------------------------------------------+
void EnterTrade(const ENUM_ORDER_TYPE type,const bool isAddon)
{
   if(OpenPositionsByMagic()>=InpMaxOpenPositions)
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
   double price = (type==ORDER_TYPE_BUY ? ask : bid);
   double slPts = slMult*atrPts;
   double tpPts = tpMult*atrPts;

   double sl = (type==ORDER_TYPE_BUY ? price - slPts*point : price + slPts*point);
   double tp = (type==ORDER_TYPE_BUY ? price + tpPts*point : price - tpPts*point);

   double lots = CalcRiskLots(sl,type,isAddon);
   lots = NormalizeLots(lots);
   if(lots<=0.0)
      return;

   trade.SetDeviationInPoints(30);
   const string comment = isAddon ? "XAU_Swing_ADD" : "XAU_Swing_BASE";
   if(trade.PositionOpen(InpSymbol,type,lots,price,sl,tp,comment))
   {
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
      PrintDebug(isAddon?"Addon opened":"Base opened");
   }
   else
   {
      PrintDebug(StringFormat("Enter failed err=%d",_LastError));
   }
}

double CalcRiskLots(const double slPrice,const ENUM_ORDER_TYPE type,const bool isAddon)
{
   if(InpUseFixedLots)
   {
      double base=InpFixedLots;
      return (isAddon ? base*InpAddonLotFactor : base);
   }

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmt = balance*(InpRiskPerTradePct/100.0);

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
      lots*=InpAddonLotFactor;

   return lots;
}

void ManagePosition(void)
{
   TryOpenAddonIfEligible();

   if(!PositionSelect(InpSymbol))
      return;

   if(BarsSinceOpen()<InpMinHoldBars)
      return;

   double point=0.0;
   if(!GetSymbolDouble(SYMBOL_POINT,point,"point") || point<=0.0)
      return;

   double atr=0.0;
   if(!CopyAt(hATR_H4,0,0,atr,"ATR H4 manage") || atr<=0.0)
      return;

   double atrPts=atr/point;

   long type=PositionGetInteger(POSITION_TYPE);
   double curSL=PositionGetDouble(POSITION_SL);
   double curTP=PositionGetDouble(POSITION_TP);
   double openPrice=PositionGetDouble(POSITION_PRICE_OPEN);
   double volume=PositionGetDouble(POSITION_VOLUME);

   double bid=0.0,ask=0.0;
   if(!GetBidAsk(bid,ask))
      return;
   double mid=(bid+ask)*0.5;

   double beDist=InpBreakEven_ATR*atrPts;
   if(type==POSITION_TYPE_BUY)
   {
      double progress=(mid-openPrice)/point;
      if((curSL==0.0 || curSL<openPrice) && progress>=beDist)
      {
         trade.PositionModify(InpSymbol,openPrice,curTP);
      }
   }
   else if(type==POSITION_TYPE_SELL)
   {
      double progress=(openPrice-mid)/point;
      if((curSL==0.0 || curSL>openPrice) && progress>=beDist)
      {
         trade.PositionModify(InpSymbol,openPrice,curTP);
      }
   }

   double atrD1pts=0.0;
   if(!RegimeOK(atrD1pts))
      return;

   int dummyBars=0;
   double slMult=0.0,tpMult=0.0;
   GetRegimeFactors(atrD1pts,dummyBars,slMult,tpMult);

   double riskPts = slMult*atrPts;
   if(!didPartialClose && InpPartialClose_Pct>0.0 && riskPts>0.0)
   {
      double rMultiple = (type==POSITION_TYPE_BUY ? (mid-openPrice)/(riskPts*point) : (openPrice-mid)/(riskPts*point));
      if(rMultiple>=InpPartialClose_R)
      {
         double minVol,maxVol,step;
         if(GetVolumeLimits(minVol,maxVol,step))
         {
            double closeVol = volume*(InpPartialClose_Pct/100.0);
            if(step>0.0)
               closeVol=MathFloor((closeVol+1e-12)/step)*step;
            if(closeVol>=minVol && closeVol<volume)
            {
               if(trade.PositionClosePartial(InpSymbol,closeVol))
                  didPartialClose=true;
            }
         }
      }
   }

   if(InpTrailingMode==TRAIL_ATR)
   {
      double trailDist=InpATR_Trail_mult*atrPts*point;
      if(type==POSITION_TYPE_BUY)
      {
         double proposed=bid-trailDist;
         double newSL=(curSL==0.0?proposed:MathMax(curSL,proposed));
         if(newSL>curSL)
            trade.PositionModify(InpSymbol,newSL,curTP);
      }
      else if(type==POSITION_TYPE_SELL)
      {
         double proposed=ask+trailDist;
         double newSL=(curSL==0.0?proposed:MathMin(curSL,proposed));
         if(newSL<curSL || curSL==0.0)
            trade.PositionModify(InpSymbol,newSL,curTP);
      }
   }
   else if(InpTrailingMode==TRAIL_FRACTAL)
   {
      double up[],dn[];
      ArraySetAsSeries(up,true);
      ArraySetAsSeries(dn,true);
      if(CopyBuffer(hFractals,0,2+InpFractal_ShiftBars,1,up)==1 &&
         CopyBuffer(hFractals,1,2+InpFractal_ShiftBars,1,dn)==1)
      {
         if(type==POSITION_TYPE_BUY && dn[0]>0.0)
         {
            double newSL=(curSL==0.0?dn[0]:MathMax(curSL,dn[0]));
            if(newSL>curSL)
               trade.PositionModify(InpSymbol,newSL,curTP);
         }
         if(type==POSITION_TYPE_SELL && up[0]>0.0)
         {
            double newSL=(curSL==0.0?up[0]:MathMin(curSL,up[0]));
            if(newSL<curSL || curSL==0.0)
               trade.PositionModify(InpSymbol,newSL,curTP);
         }
      }
   }
}

void TryOpenAddonIfEligible(void)
{
   if(!InpUsePyramiding)
      return;
   if(addonsOpened>=InpMaxAddonsPerBase)
      return;
   if(OpenPositionsByMagic()>=InpMaxOpenPositions)
      return;

   if(!PositionSelect(InpSymbol))
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

   double stepDist = InpAddonStep_ATR*atrPts*point;

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

