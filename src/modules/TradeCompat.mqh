#ifndef __EA_TRADE_COMPAT_MQH__
#define __EA_TRADE_COMPAT_MQH__

//+------------------------------------------------------------------+
//| Lightweight trading helper used when the standard library is     |
//| unavailable.  It mirrors the subset of the CTrade API consumed   |
//| by the Expert Advisor so that the code can build in constrained  |
//| environments (for example static analysis) while still relying   |
//| on native trading functions at runtime.                          |
//+------------------------------------------------------------------+
class EA_Trade
{
private:
   int  m_deviation;
   long m_magic;

public:
   EA_Trade()
   {
      m_deviation = 0;
      m_magic     = 0;
   }

   void SetExpertMagicNumber(const long magic)
   {
      m_magic = magic;
   }

   void SetDeviationInPoints(const int points)
   {
      m_deviation = (points<0 ? 0 : points);
   }

   bool PositionOpen(const string symbol,const ENUM_ORDER_TYPE type,const double volume,
                     const double price,const double sl,const double tp,const string comment)
   {
      if(volume<=0.0)
         return false;

      MqlTradeRequest request;
      MqlTradeResult  result;
      ZeroMemory(request);
      ZeroMemory(result);

      request.action      = TRADE_ACTION_DEAL;
      request.type        = type;
      request.symbol      = symbol;
      request.volume      = volume;
      request.price       = (price>0.0 ? price : ResolvePrice(symbol,type));
      request.sl          = sl;
      request.tp          = tp;
      request.deviation   = m_deviation;
      request.magic       = m_magic;
      request.comment     = comment;
      request.type_time   = ORDER_TIME_GTC;
      request.type_filling= ResolveFilling(symbol);

      ResetLastError();
      if(!OrderSend(request,result))
         return false;

      return IsRetcodeSuccess(result.retcode);
   }

   bool PositionClose(const string symbol)
   {
      if(!PositionSelect(symbol))
         return false;

      double volume=PositionGetDouble(POSITION_VOLUME);
      if(volume<=0.0)
         return false;

      return PositionClosePartial(symbol,volume);
   }

   bool PositionClosePartial(const string symbol,const double volume)
   {
      if(volume<=0.0)
         return false;

      if(!PositionSelect(symbol))
         return false;

      long   ticket = (long)PositionGetInteger(POSITION_TICKET);
      long   type   = PositionGetInteger(POSITION_TYPE);
      double curVol = PositionGetDouble(POSITION_VOLUME);

      if(ticket<=0 || curVol<=0.0)
         return false;

      double closeVolume = MathMin(volume,curVol);
      ENUM_ORDER_TYPE orderType = (type==POSITION_TYPE_BUY ? ORDER_TYPE_SELL : ORDER_TYPE_BUY);
      double price = ResolvePrice(symbol,orderType);
      if(price<=0.0)
         return false;

      MqlTradeRequest request;
      MqlTradeResult  result;
      ZeroMemory(request);
      ZeroMemory(result);

      request.action      = TRADE_ACTION_DEAL;
      request.type        = orderType;
      request.symbol      = symbol;
      request.volume      = closeVolume;
      request.price       = price;
      request.deviation   = m_deviation;
      request.magic       = m_magic;
      request.position    = ticket;
      request.type_time   = ORDER_TIME_GTC;
      request.type_filling= ResolveFilling(symbol);

      ResetLastError();
      if(!OrderSend(request,result))
         return false;

      return IsRetcodeSuccess(result.retcode);
   }

   bool PositionModify(const string symbol,const double sl,const double tp)
   {
      if(!PositionSelect(symbol))
         return false;

      long ticket=(long)PositionGetInteger(POSITION_TICKET);
      if(ticket<=0)
         return false;

      MqlTradeRequest request;
      MqlTradeResult  result;
      ZeroMemory(request);
      ZeroMemory(result);

      request.action   = TRADE_ACTION_SLTP;
      request.symbol   = symbol;
      request.sl       = sl;
      request.tp       = tp;
      request.position = ticket;
      request.magic    = m_magic;

      ResetLastError();
      if(!OrderSend(request,result))
         return false;

      return IsRetcodeSuccess(result.retcode);
   }

private:
   ENUM_ORDER_TYPE_FILLING ResolveFilling(const string symbol) const
   {
      long mode=0;
      if(SymbolInfoInteger(symbol,SYMBOL_FILLING_MODE,mode))
      {
         switch(mode)
         {
            case SYMBOL_FILLING_FOK:    return ORDER_FILLING_FOK;
            case SYMBOL_FILLING_IOC:    return ORDER_FILLING_IOC;
            case SYMBOL_FILLING_RETURN: return ORDER_FILLING_RETURN;
         }
      }
      return ORDER_FILLING_FOK;
   }

   double ResolvePrice(const string symbol,const ENUM_ORDER_TYPE type) const
   {
      double bid=0.0,ask=0.0;
      if(!SymbolInfoDouble(symbol,SYMBOL_BID,bid))
         bid=0.0;
      if(!SymbolInfoDouble(symbol,SYMBOL_ASK,ask))
         ask=0.0;

      if(type==ORDER_TYPE_BUY)
         return ask;
      if(type==ORDER_TYPE_SELL)
         return bid;
      return 0.0;
   }

   bool IsRetcodeSuccess(const uint retcode) const
   {
      switch(retcode)
      {
         case TRADE_RETCODE_DONE:
         case TRADE_RETCODE_PLACED:
         case TRADE_RETCODE_DONE_PARTIAL:
            return true;
      }
      return false;
   }
};

#endif // __EA_TRADE_COMPAT_MQH__
