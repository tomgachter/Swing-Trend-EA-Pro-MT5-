#ifndef __BIAS_ENGINE_MQH__
#define __BIAS_ENGINE_MQH__

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
   int             m_votesRequired;
   double          m_thH1Base;
   double          m_thH4Base;
   double          m_thD1Base;
   double          m_thresholdScale;
   double          m_lastSlopeH1;
   double          m_lastSlopeH4;
   double          m_lastSlopeD1;
   int             m_lastVotesUp;
   int             m_lastVotesDown;
   int             m_lastVotesNeutral;
   bool            m_debug;

   int DirectionFromSlope(const double now,const double prev,const double atr,
                          const double threshold,double &slopeOut)
   {
      slopeOut = 0.0;
      if(atr<=0.0)
         return 0;

      double slope = (now-prev)/atr;
      slopeOut = slope;
      double slopeAbs = MathAbs(slope);
      if(slopeAbs<threshold)
         return 0;

      return (slope>0.0 ? +1 : -1);
   }

public:
   BiasEngine(): m_symbol(_Symbol), m_handleH1(INVALID_HANDLE), m_handleH4(INVALID_HANDLE), m_handleD1(INVALID_HANDLE),
                 m_lastEmaH1(0.0), m_lastEmaH4(0.0), m_lastEmaD1(0.0), m_direction(0), m_votesRequired(2),
                 m_thH1Base(0.020), m_thH4Base(0.018), m_thD1Base(0.015), m_thresholdScale(1.0),
                 m_lastSlopeH1(0.0), m_lastSlopeH4(0.0), m_lastSlopeD1(0.0),
                 m_lastVotesUp(0), m_lastVotesDown(0), m_lastVotesNeutral(3),
                 m_debug(false)
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

   void ConfigureThresholds(const int votesRequired,
                            const double thH1,const double thH4,const double thD1)
   {
      m_votesRequired = MathMax(1,MathMin(3,votesRequired));
      m_thH1Base = MathMax(0.0,thH1);
      m_thH4Base = MathMax(0.0,thH4);
      m_thD1Base = MathMax(0.0,thD1);
   }

   bool Update(RegimeFilter &regime)
   {
      double e1[2];
      double e4[2];
      double eD[2];
      if(CopyBuffer(m_handleH1,0,0,2,e1)!=2)
         return false;
      if(CopyBuffer(m_handleH4,0,0,2,e4)!=2)
         return false;
      if(CopyBuffer(m_handleD1,0,0,2,eD)!=2)
         return false;

      m_lastEmaH1 = e1[0];
      m_lastEmaH4 = e4[0];
      m_lastEmaD1 = eD[0];

      double atrH1 = regime.AtrH1();
      double atrH4 = regime.AtrH4();
      double atrD1 = (regime.AtrD1()!=0.0 ? regime.AtrD1() : atrH4*2.5);

      double effThH1 = m_thH1Base*m_thresholdScale;
      double effThH4 = m_thH4Base*m_thresholdScale;
      double effThD1 = m_thD1Base*m_thresholdScale;

      m_lastSlopeH1 = 0.0;
      m_lastSlopeH4 = 0.0;
      m_lastSlopeD1 = 0.0;
      int d1 = DirectionFromSlope(e1[0],e1[1],atrH1,effThH1,m_lastSlopeH1);
      int d4 = DirectionFromSlope(e4[0],e4[1],atrH4,effThH4,m_lastSlopeH4);
      int dD = DirectionFromSlope(eD[0],eD[1],atrD1,effThD1,m_lastSlopeD1);

      m_lastVotesUp = (d1>0) + (d4>0) + (dD>0);
      m_lastVotesDown = (d1<0) + (d4<0) + (dD<0);
      m_lastVotesNeutral = 3 - m_lastVotesUp - m_lastVotesDown;

      int votes = MathMax(m_lastVotesUp,m_lastVotesDown);
      if(votes >= m_votesRequired)
         m_direction = (m_lastVotesUp>m_lastVotesDown ? +1 : -1);
      else
         m_direction = 0;

      if(m_debug)
      {
         PrintFormat("BIAS DEBUG: d1=%d d4=%d dD=%d | votes=%d required=%d -> dir=%d",
                     d1,d4,dD,votes,m_votesRequired,m_direction);
      }
      return true;
   }

   int Direction() { return m_direction; }
   double EmaH1() { return m_lastEmaH1; }
   double EmaH4() { return m_lastEmaH4; }
   double EmaD1() { return m_lastEmaD1; }

   void SetSlopeThreshold(const double multiplier)
   {
      m_thresholdScale = (multiplier>=0.0 ? multiplier : 0.0);
   }

   void SetMinVotes(const int votes)
   {
      m_votesRequired = MathMax(1,MathMin(3,votes));
   }

   int VotesUp() const { return m_lastVotesUp; }
   int VotesDown() const { return m_lastVotesDown; }
   int VotesNeutral() const { return m_lastVotesNeutral; }
   double SlopeH1() const { return m_lastSlopeH1; }
   double SlopeH4() const { return m_lastSlopeH4; }
   double SlopeD1() const { return m_lastSlopeD1; }
   double ThresholdH1() const { return m_thH1Base*m_thresholdScale; }
   double ThresholdH4() const { return m_thH4Base*m_thresholdScale; }
   double ThresholdD1() const { return m_thD1Base*m_thresholdScale; }

   void SetDebug(const bool debug)
   {
      m_debug = debug;
   }
};

#endif // __BIAS_ENGINE_MQH__
