#pragma once

#include "RegimeFilter.mqh"

class BiasEngine
{
private:
   string          m_symbol;
   int             m_handleH1;
   int             m_handleH4;
   int             m_handleD1;
   double          m_lastEmaH1;
   double          m_lastEmaH4;
   double          m_lastEmaD1;
   int             m_direction;

   double Slope(const int handle,const ENUM_TIMEFRAMES tf,const double atr) const
   {
      double buffer[2];
      if(CopyBuffer(handle,0,1,2,buffer)!=2)
         return 0.0;
      double delta = buffer[0]-buffer[1];
      double normalizer = atr;
      if(normalizer<=0.0)
         normalizer = MathAbs(buffer[1])*0.001;
      if(normalizer<=0.0)
         normalizer = 1.0;
      return delta/normalizer;
   }

public:
   BiasEngine(): m_symbol(_Symbol), m_handleH1(INVALID_HANDLE), m_handleH4(INVALID_HANDLE), m_handleD1(INVALID_HANDLE),
                 m_lastEmaH1(0.0), m_lastEmaH4(0.0), m_lastEmaD1(0.0), m_direction(0)
   {
   }

   bool Init(const string symbol)
   {
      m_symbol   = symbol;
      m_handleH1 = iMA(symbol,PERIOD_H1,20,0,MODE_EMA,PRICE_CLOSE);
      m_handleH4 = iMA(symbol,PERIOD_H4,34,0,MODE_EMA,PRICE_CLOSE);
      m_handleD1 = iMA(symbol,PERIOD_D1,50,0,MODE_EMA,PRICE_CLOSE);
      return (m_handleH1!=INVALID_HANDLE && m_handleH4!=INVALID_HANDLE && m_handleD1!=INVALID_HANDLE);
   }

   bool Update(const RegimeFilter &regime)
   {
      double emaH1=0.0, emaH4=0.0, emaD1=0.0;
      if(CopyBuffer(m_handleH1,0,1,1,&emaH1)!=1)
         return false;
      if(CopyBuffer(m_handleH4,0,1,1,&emaH4)!=1)
         return false;
      if(CopyBuffer(m_handleD1,0,1,1,&emaD1)!=1)
         return false;
      m_lastEmaH1 = emaH1;
      m_lastEmaH4 = emaH4;
      m_lastEmaD1 = emaD1;

      int votesLong = 0;
      int votesShort = 0;
      MqlRates rates[];
      if(CopyRates(m_symbol,PERIOD_H1,1,1,rates)==1)
      {
         double closePrice = rates[0].close;
         if(closePrice>emaH1) votesLong++; else votesShort++;
      }
      if(CopyRates(m_symbol,PERIOD_H4,1,1,rates)==1)
      {
         double closePrice = rates[0].close;
         if(closePrice>emaH4) votesLong++; else votesShort++;
      }
      if(CopyRates(m_symbol,PERIOD_D1,1,1,rates)==1)
      {
         double closePrice = rates[0].close;
         if(closePrice>emaD1) votesLong++; else votesShort++;
      }

      double slopeH1 = Slope(m_handleH1,PERIOD_H1,regime.AtrH1());
      double slopeH4 = Slope(m_handleH4,PERIOD_H4,regime.AtrH4());
      double slopeD1 = Slope(m_handleD1,PERIOD_D1,regime.AtrH4());
      const double slopeThreshold = 0.05;

      if(votesLong>=2 && slopeH1>-slopeThreshold && slopeH4>-slopeThreshold && slopeD1>-slopeThreshold)
         m_direction = 1;
      else if(votesShort>=2 && slopeH1<slopeThreshold && slopeH4<slopeThreshold && slopeD1<slopeThreshold)
         m_direction = -1;
      else
         m_direction = 0;
      return true;
   }

   int Direction() const { return m_direction; }
   double EmaH1() const { return m_lastEmaH1; }
};
