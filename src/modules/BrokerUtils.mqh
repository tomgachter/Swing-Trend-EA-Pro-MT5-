#ifndef __BROKER_UTILS_MQH__
#define __BROKER_UTILS_MQH__

#include <Trade\Trade.mqh>

#ifndef ERR_REQUOTE
   #define ERR_REQUOTE 138
#endif

#ifndef ERR_OFF_QUOTES
   #define ERR_OFF_QUOTES 136
#endif

#ifndef ERR_PRICE_CHANGED
   #define ERR_PRICE_CHANGED 135
#endif

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
      m_trade.SetAsyncMode(false);
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
      ENUM_ORDER_TYPE type;
      if(direction>0)
         type = ORDER_TYPE_BUY;
      else if(direction<0)
         type = ORDER_TYPE_SELL;
      else
         return false;
      for(int attempt=0; attempt<3; ++attempt)
      {
         ResetLastError();
         bool ok = m_trade.PositionOpen(_Symbol,type,volume,price,sl,tp,m_comment);
         if(ok)
            return true;
         int err = GetLastError();
         if(err==ERR_REQUOTE || err==ERR_OFF_QUOTES || err==ERR_PRICE_CHANGED)
         {
            Sleep(200*(attempt+1));
            MqlTick tick;
            SymbolInfoTick(_Symbol,tick);
            continue;
         }
         break;
      }
      return false;
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

#endif // __BROKER_UTILS_MQH__
