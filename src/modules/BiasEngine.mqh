#ifndef __BIAS_ENGINE_MQH__
#define __BIAS_ENGINE_MQH__

#include "RegimeFilter.mqh"

enum BiasStrength
{
   BIAS_NEUTRAL = 0,
   BIAS_MODERATE = 1,
   BIAS_STRONG = 2
};

struct TrendBias
{
   int          direction;     // +1 long, -1 short, 0 neutral
   BiasStrength strength;      // qualitative confidence bucket
   double       score;         // aggregated slope score (sign adjusted)
   int          votesStrongLong;
   int          votesStrongShort;
   int          votesModerateLong;
   int          votesModerateShort;
   int          votesNearLong;
   int          votesNearShort;
   int          signH1;
   int          signH4;
   int          signD1;
   double       slopeH1;
   double       slopeH4;
   double       slopeD1;
   double       emaH1;
   double       emaH4;
   double       emaD1;
   double       thresholdH1;
   double       thresholdH4;
   double       thresholdD1;
   bool         relaxedApplied;
   bool         fallbackApplied;

   TrendBias()
   {
      direction = 0;
      strength = BIAS_NEUTRAL;
      score = 0.0;
      votesStrongLong = votesStrongShort = 0;
      votesModerateLong = votesModerateShort = 0;
      votesNearLong = votesNearShort = 0;
      signH1 = signH4 = signD1 = 0;
      slopeH1 = slopeH4 = slopeD1 = 0.0;
      emaH1 = emaH4 = emaD1 = 0.0;
      thresholdH1 = thresholdH4 = thresholdD1 = 0.0;
      relaxedApplied = false;
      fallbackApplied = false;
   }
};

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
   double          m_thH1Base;
   double          m_thH4Base;
   double          m_thD1Base;
   double          m_thresholdScale;
   double          m_lastSlopeH1;
   double          m_lastSlopeH4;
   double          m_lastSlopeD1;
   bool            m_debug;
   int             m_legacyVotesRequired;
   TrendBias       m_lastBias;

   double NormalizedSlope(const double now,const double prev,const double atr) const
   {
      if(atr<=0.0)
         return 0.0;
      return (now-prev)/atr;
   }

public:
   BiasEngine(): m_symbol(_Symbol), m_handleH1(INVALID_HANDLE), m_handleH4(INVALID_HANDLE), m_handleD1(INVALID_HANDLE),
                 m_lastEmaH1(0.0), m_lastEmaH4(0.0), m_lastEmaD1(0.0),
                 m_thH1Base(0.020), m_thH4Base(0.018), m_thD1Base(0.015), m_thresholdScale(1.0),
                 m_lastSlopeH1(0.0), m_lastSlopeH4(0.0), m_lastSlopeD1(0.0),
                 m_debug(false),
                 m_legacyVotesRequired(0)
   {
      m_lastBias = TrendBias();
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
      m_legacyVotesRequired = votesRequired; // legacy input kept for preset compatibility
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

      m_lastSlopeH1 = 0.0;
      m_lastSlopeH4 = 0.0;
      m_lastSlopeD1 = 0.0;
      m_lastSlopeH1 = NormalizedSlope(e1[0],e1[1],atrH1);
      m_lastSlopeH4 = NormalizedSlope(e4[0],e4[1],atrH4);
      m_lastSlopeD1 = NormalizedSlope(eD[0],eD[1],atrD1);

      m_lastBias = TrendBias();
      return true;
   }

   double EmaH1() { return m_lastEmaH1; }
   double EmaH4() { return m_lastEmaH4; }
   double EmaD1() { return m_lastEmaD1; }

   void SetSlopeThreshold(const double multiplier)
   {
      m_thresholdScale = (multiplier>=0.0 ? multiplier : 0.0);
   }

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

   bool ComputeTrendBias(TrendBias &bias,const bool relaxedMode,const bool fallbackMode)
   {
      // Multi-timeframe classification: normalised EMA slopes (ATR-adjusted) vote per TF.
      // STRONG if >=2 TFs exceed their threshold in the same direction, MODERATE if exactly
      // one TF clears the threshold or several sit in the 0.5x-1.0x buffer, otherwise NEUTRAL.
      double scale = m_thresholdScale;
      double relaxedAdj = (relaxedMode ? 0.90 : 1.0);
      double fallbackAdj = (fallbackMode ? 0.75 : 1.0);
      double effH1 = m_thH1Base*scale*relaxedAdj*fallbackAdj;
      double effH4 = m_thH4Base*scale*relaxedAdj*fallbackAdj;
      double effD1 = m_thD1Base*scale*relaxedAdj*fallbackAdj;
      double nearH1 = effH1*0.5;
      double nearH4 = effH4*0.5;
      double nearD1 = effD1*0.5;

      bias = TrendBias();
      bias.slopeH1 = m_lastSlopeH1;
      bias.slopeH4 = m_lastSlopeH4;
      bias.slopeD1 = m_lastSlopeD1;
      bias.emaH1 = m_lastEmaH1;
      bias.emaH4 = m_lastEmaH4;
      bias.emaD1 = m_lastEmaD1;
      bias.thresholdH1 = effH1;
      bias.thresholdH4 = effH4;
      bias.thresholdD1 = effD1;
      bias.relaxedApplied = relaxedMode;
      bias.fallbackApplied = fallbackMode;

      double slopes[3] = {m_lastSlopeH1,m_lastSlopeH4,m_lastSlopeD1};
      double strongTh[3] = {effH1,effH4,effD1};
      double moderateTh[3] = {nearH1,nearH4,nearD1};

      int signs[3] = {0,0,0};
      int strongLong=0,strongShort=0;
      int moderateLong=0,moderateShort=0;
      int nearLong=0,nearShort=0;
      double posSum=0.0,negSum=0.0;

      for(int i=0;i<3;i++)
      {
         double slope = slopes[i];
         double absSlope = MathAbs(slope);
         if(absSlope < 1e-6)
         {
            signs[i] = 0;
            continue;
         }
         int sign = (slope>0.0 ? +1 : -1);
         signs[i] = sign;
         bool strong = (absSlope >= strongTh[i] && strongTh[i]>0.0);
         bool moderate = (absSlope >= moderateTh[i] && moderateTh[i]>0.0);
         if(sign>0)
         {
            if(strong) strongLong++;
            if(moderate) moderateLong++;
            if(moderate && !strong) nearLong++;
            posSum += slope;
         }
         else if(sign<0)
         {
            if(strong) strongShort++;
            if(moderate) moderateShort++;
            if(moderate && !strong) nearShort++;
            negSum += MathAbs(slope);
         }
      }

      bias.signH1 = signs[0];
      bias.signH4 = signs[1];
      bias.signD1 = signs[2];
      bias.votesStrongLong = strongLong;
      bias.votesStrongShort = strongShort;
      bias.votesModerateLong = moderateLong;
      bias.votesModerateShort = moderateShort;
      bias.votesNearLong = nearLong;
      bias.votesNearShort = nearShort;

      if(strongLong>=2 || strongShort>=2)
      {
         bias.strength = BIAS_STRONG;
         if(strongLong>strongShort)
            bias.direction = +1;
         else if(strongShort>strongLong)
            bias.direction = -1;
         else
            bias.direction = (posSum>=negSum ? +1 : -1);
      }
      else
      {
         bool longModerate=false;
         bool shortModerate=false;

         if(strongLong==1 && strongShort==0)
            longModerate = true;
         if(strongShort==1 && strongLong==0)
            shortModerate = true;
         if(!longModerate && strongLong==0 && strongShort==0 && nearLong>=2 && moderateLong>=2)
            longModerate = true;
         if(!shortModerate && strongLong==0 && strongShort==0 && nearShort>=2 && moderateShort>=2)
            shortModerate = true;

         if(longModerate && !shortModerate)
         {
            bias.direction = +1;
            bias.strength = BIAS_MODERATE;
         }
         else if(shortModerate && !longModerate)
         {
            bias.direction = -1;
            bias.strength = BIAS_MODERATE;
         }
         else
         {
            bias.direction = 0;
            bias.strength = BIAS_NEUTRAL;
         }
      }

      if(bias.direction>0)
         bias.score = posSum;
      else if(bias.direction<0)
         bias.score = -negSum;
      else
         bias.score = 0.0;

      m_lastBias = bias;

      if(m_debug)
      {
         PrintFormat("BIAS DEBUG: slopes=H1 %.4f H4 %.4f D1 %.4f | strongVotes L%d/S%d moderateVotes L%d/S%d nearVotes L%d/S%d -> dir=%d strength=%d score=%.4f relaxed=%s fallback=%s",
                     m_lastSlopeH1,m_lastSlopeH4,m_lastSlopeD1,
                     strongLong,strongShort,
                     moderateLong,moderateShort,
                     nearLong,nearShort,
                     bias.direction,(int)bias.strength,bias.score,
                     relaxedMode?"true":"false",
                     fallbackMode?"true":"false");
      }
      return true;
   }

   TrendBias LastBias() const
   {
      return m_lastBias;
   }
};

#endif // __BIAS_ENGINE_MQH__
