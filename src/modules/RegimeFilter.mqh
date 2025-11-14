#ifndef __REGIME_FILTER_MQH__
#define __REGIME_FILTER_MQH__

#include <Trade\Trade.mqh>

enum RegimeBucket
{
   REGIME_LOW = 0,
   REGIME_NORMAL = 1,
   REGIME_HIGH = 2
};

class RegimeFilter
{
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_tfH1;
   ENUM_TIMEFRAMES   m_tfH4;
   ENUM_TIMEFRAMES   m_tfD1;
   int               m_atrPeriod;
   int               m_handleH1;
   int               m_handleH4;
   int               m_handleD1;
   double            m_lowThreshold;
   double            m_highThreshold;
   double            m_lastAtrH1;
   double            m_lastAtrH4;
   double            m_lastAtrD1;
   RegimeBucket      m_currentBucket;
   datetime          m_lastUpdateBarTime;

   bool CalculatePercentiles()
   {
      const int lookback = 2000;
      double buffer[];
      ArrayResize(buffer,lookback);
      int copied = CopyBuffer(m_handleH1,0,0,lookback,buffer);
      if(copied <= 50)
         return false;
      ArrayResize(buffer,copied);
      ArraySort(buffer);
      int lowIndex  = (int)MathMax(0,MathFloor(0.30*(copied-1)));
      int highIndex = (int)MathMax(0,MathFloor(0.70*(copied-1)));
      m_lowThreshold  = buffer[lowIndex];
      m_highThreshold = buffer[highIndex];
      return true;
   }

public:
   RegimeFilter() : m_symbol(_Symbol), m_tfH1(PERIOD_H1), m_tfH4(PERIOD_H4), m_tfD1(PERIOD_D1), m_atrPeriod(14),
                    m_handleH1(INVALID_HANDLE), m_handleH4(INVALID_HANDLE), m_handleD1(INVALID_HANDLE), m_lowThreshold(0.0),
                    m_highThreshold(0.0), m_lastAtrH1(0.0), m_lastAtrH4(0.0), m_lastAtrD1(0.0),
                    m_currentBucket(REGIME_NORMAL), m_lastUpdateBarTime(0)
   {
   }

   bool Init(const string symbol,const int atrPeriod=14)
   {
      m_symbol    = symbol;
      m_atrPeriod = atrPeriod;
      m_handleH1  = iATR(m_symbol,m_tfH1,m_atrPeriod);
      m_handleH4  = iATR(m_symbol,m_tfH4,m_atrPeriod);
      m_handleD1  = iATR(m_symbol,m_tfD1,m_atrPeriod);
      if(m_handleH1==INVALID_HANDLE || m_handleH4==INVALID_HANDLE || m_handleD1==INVALID_HANDLE)
         return false;
      if(!CalculatePercentiles())
         return false;
      return Update(true);
   }

   void Release()
   {
      if(m_handleH1!=INVALID_HANDLE)
      {
         IndicatorRelease(m_handleH1);
         m_handleH1 = INVALID_HANDLE;
      }
      if(m_handleH4!=INVALID_HANDLE)
      {
         IndicatorRelease(m_handleH4);
         m_handleH4 = INVALID_HANDLE;
      }
      if(m_handleD1!=INVALID_HANDLE)
      {
         IndicatorRelease(m_handleD1);
         m_handleD1 = INVALID_HANDLE;
      }
   }

   bool Update(const bool force=false)
   {
      datetime barTime = iTime(m_symbol,m_tfH1,0);
      if(!force && barTime==m_lastUpdateBarTime)
         return true;

      double atrH1Buffer[];
      ArrayResize(atrH1Buffer,1);
      if(CopyBuffer(m_handleH1,0,0,1,atrH1Buffer)!=1)
         return false;
      double atrH4Buffer[];
      ArrayResize(atrH4Buffer,1);
      if(CopyBuffer(m_handleH4,0,0,1,atrH4Buffer)!=1)
         return false;
      double atrD1Buffer[];
      ArrayResize(atrD1Buffer,1);
      if(CopyBuffer(m_handleD1,0,0,1,atrD1Buffer)!=1)
         return false;

      double atrH1 = atrH1Buffer[0];
      double atrH4 = atrH4Buffer[0];
      double atrD1 = atrD1Buffer[0];
      m_lastAtrH1 = atrH1;
      m_lastAtrH4 = atrH4;
      m_lastAtrD1 = atrD1;
      m_lastUpdateBarTime = barTime;

      if(atrH1 <= m_lowThreshold)
         m_currentBucket = REGIME_LOW;
      else if(atrH1 >= m_highThreshold)
         m_currentBucket = REGIME_HIGH;
      else
         m_currentBucket = REGIME_NORMAL;
      return true;
   }

   RegimeBucket CurrentBucket() { return m_currentBucket; }

   double AtrH1() { return m_lastAtrH1; }
   double AtrH4() { return m_lastAtrH4; }
   double AtrD1() { return m_lastAtrD1; }
   double LowThreshold() { return m_lowThreshold; }
   double HighThreshold() { return m_highThreshold; }
};

#endif // __REGIME_FILTER_MQH__
