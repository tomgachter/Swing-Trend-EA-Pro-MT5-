#pragma once

#include <Trade\Trade.mqh>

class BrokerUtils
{
private:
   CTrade m_trade;
   ulong  m_magic;
   string m_comment;
   double m_slippage;

public:
   BrokerUtils(): m_magic(0), m_comment(""), m_slippage(20.0)
   {
      m_trade.SetTypeFilling(ORDER_FILLING_FOK);
   }

   void Configure(const ulong magic,const string comment,const double deviationPoints)
   {
      m_magic   = magic;
      m_comment = comment;
      m_slippage = deviationPoints;
      m_trade.SetExpertMagicNumber(m_magic);
      m_trade.SetDeviationInPoints((int)m_slippage);
   }

   bool OpenPosition(const int direction,const double volume,const double price,const double sl,const double tp)
   {
      if(volume<=0.0)
         return false;
      bool result=false;
      if(direction>0)
         result = m_trade.PositionOpen(_Symbol,ORDER_TYPE_BUY,volume,price,sl,tp,m_comment);
      else if(direction<0)
         result = m_trade.PositionOpen(_Symbol,ORDER_TYPE_SELL,volume,price,sl,tp,m_comment);
      return result;
   }

   bool ModifySL(const ulong ticket,const double sl)
   {
      if(!PositionSelectByTicket(ticket))
         return false;
      double price = PositionGetDouble(POSITION_PRICE_OPEN);
      double volume = PositionGetDouble(POSITION_VOLUME);
      double tp = PositionGetDouble(POSITION_TP);
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if(type==POSITION_TYPE_BUY)
         return m_trade.PositionModify(ticket,sl,tp);
      else if(type==POSITION_TYPE_SELL)
         return m_trade.PositionModify(ticket,sl,tp);
      return false;
   }

   bool ClosePartial(const ulong ticket,const double volume)
   {
      if(volume<=0.0)
         return false;
      if(!PositionSelectByTicket(ticket))
         return false;
      return m_trade.PositionClosePartial(ticket,volume);
   }

   bool ClosePosition(const ulong ticket)
   {
      if(!PositionSelectByTicket(ticket))
         return false;
      return m_trade.PositionClose(ticket);
   }
};
