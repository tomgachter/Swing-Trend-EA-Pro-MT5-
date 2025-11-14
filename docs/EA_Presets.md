# XAU Swing Trend EA Presets

The EA now derives its configuration from three levers:

* **Aggressiveness** input (`0` Defensive, `1` Neutral, `2` Aggressive)
* **Market Regime** detected from the 14-day ATR on `XAUUSD` (`REG_LOW`, `REG_MID`, `REG_HIGH`)
* **Risk guard preset** (`RISK_CONSERVATIVE`, `RISK_BALANCED`, `RISK_OFFENSIVE`)

This document summarises the adaptive preset values that are applied automatically on every new bar. When legacy `.set` files provide conflicting values the preset layer below wins.

## Additional Input Controls

To raise signal cadence you can now adjust these exposed inputs (suggested ranges in brackets):

* `MinVotesForBias` (1–3, default 2) – minimum EMA votes required for directional bias.
* `BiasSlopeThreshold` (0.010–0.030) – base EMA slope ratio; lower numbers admit flatter trends.
* `BiasScoreThresholdCore/Edge` (0.04–0.10) – multi-timeframe slope sum required before entries are considered.
* `BiasSlopeConfirmH1/H4/D1` (0.010–0.025) – absolute slope confirmations per timeframe before neutral/weak trends are traded.
* `PullbackBandATR` (0.20–0.60) – ATR multiple for the pullback touch band, scaled per regime.
* `PullbackMomentumATR` (0.20–0.60) – ATR multiple for the pullback candle body/momentum gate.
* `BreakoutImpulseATR` (0.25–0.60) – ATR multiple demanded from breakout bodies before entry.
* `BreakoutLookback` (4–10) – number of completed bars forming the breakout box.
* `EntryTF` (PERIOD_M15–PERIOD_H4) – chart timeframe feeding the entry engine (bias votes stay on H1/H4/D1).
* `EnableWeekdayFallback`, `FallbackMinHour`, `FallbackMaxPer7D` – weekday relaxation controls for the fallback entry cadence.
* `LateEntryCutoffHour/Minute` – optional session cap when late-day trades underperform.

### Balanced XAU H1 v2 quick preset

| Block | Parameters |
| --- | --- |
| Risk | `RiskPerTrade=0.60`, `MaxDailyRiskPercent=5`, `MaxEquityDDPercentForCloseAll=12`, `RegimeLowRiskScale=0.60`, `RegimeHighRiskScale=1.05`, `MaxNewTradesPerDay=3` |
| Bias | `BiasSlopeThH1/H4/D1=0.020/0.018/0.015`, `BiasScoreThresholdCore/Edge=0.060/0.085`, `BiasScoreRegimeLowBoost=0.015`, `BiasSlopeConfirmH1/H4/D1=0.018/0.014/0.010`, `NeutralBiasRiskScale=0.40`, `RequireStrongFallbackSetups=true` |
| Entries | `PullbackBodyATRMin=0.45`, `BreakoutImpulseATRMin=0.42`, `BreakoutRangeBars=6`, `Core/EdgeScoreThreshold=0.76/0.85`, `RegimeLow/HighQualityBoost=0.06/0.03`, `AllowAggressiveEntries=true` |
| Management | `PartialTP1_Fraction=0.40`, `BreakEven_R=0.9`, `PartialTP1_R=1.1`, `HardTP_R=2.7`, `TrailStart_R=1.8`, `TrailDistance_R=0.9`, `MaxBarsInTrade=36`, `TimeStopProtectR=0.5` |
| Discipline | `LateEntryCutoff=14:00`, `EnableFallbackEntry=true`, `EnableWeekdayFallback=true`, `MaxLosingTradesPerDay=3`, `MaxLosingTradesInARow=3`, `RiskScaleAfterLosingStreak=0.5` |
| Telemetry | `EnableTradeTelemetry=true`, prefix `xau_balanced_v2` |

The telemetry CSVs add per-trade lines with direction, entry type, realised R multiple, MFE/MAE (in R), bars held, and detected exit mechanism—ideal for post-run analytics without scraping the strategy tester report.

## Entry & Exit Map

| Aggressiveness | Regime | Trend votes | ADX Min | Donchian Bars | Breakout Buffer (ATR) | Trail ATR K | Partial | Partial Trigger | Time Stop | Take Profit |
|----------------|--------|-------------|---------|---------------|-----------------------|-------------|---------|-----------------|-----------|--------------|
| Defensive (0)  | Low    | 2           | 26      | 14–18         | 0.15–0.20             | 1.1–1.3     | 45%     | 2.0 R           | 48 h      | Enabled      |
| Defensive (0)  | Mid    | 2           | 26      | 16–18         | 0.18–0.22             | 1.3–1.5     | 45%     | 2.0 R           | Off       | Disabled     |
| Defensive (0)  | High   | 2 (drops to 1 on high ADX) | 26 | 18–20 | 0.20–0.25 | 1.4–1.6 | 45% | 2.0 R | Off | Disabled |
| Neutral (1)    | Low    | 2 (drops to 1 when ADX ≥ 23) | 23 | 8–12 | 0.05–0.10 | 1.2–1.4 | 30% | 2.2 R | 48 h (optional) | Enabled |
| Neutral (1)    | Mid    | 2 (drops to 1 on momentum) | 23 | 12–16 | 0.10–0.15 | 1.4–1.6 | 30% | 2.2 R | Off | Disabled |
| Neutral (1)    | High   | 2 (drops to 1 on momentum) | 23 | 16–20 | 0.15–0.25 | 1.6–2.0 | 30% | 2.2 R | Off | Disabled |
| Aggressive (2) | Low    | 2 (drops to 1 on momentum) | 19 | 8–10 | 0.04–0.08 | 1.4–1.8 | Optional ≤ 18% | 2.5 R | Off | Disabled |
| Aggressive (2) | Mid    | 2 (drops to 1 on momentum) | 19 | 10–12 | 0.08–0.14 | 1.6–2.0 | Optional ≤ 18% | 2.5 R | Off | Disabled |
| Aggressive (2) | High   | 1 when ADX or regime strong | 19 | 12–14 | 0.12–0.16 | 1.8–2.2 | Off | — | Off | Disabled |

*Trail ATR K* is interpolated between the listed bounds using the regime weight (`LOW = 0`, `MID = 0.5`, `HIGH = 1`). Add-on positions trail `0.2` tighter.

## Pyramiding Controls

| Aggressiveness | Regime Influence | Max Add-ons | Step (ATR) | Total Risk Cap |
|----------------|------------------|-------------|------------|----------------|
| All modes      | Regime agnostic   | 2           | 0.8        | `addonMaxTotalRiskMult` (1.6 defensive, 2.0 neutral, 2.6 aggressive) |

Add-ons require:

* Base trade MFE ≥ `1.0 R`
* Base trade MAE ≤ `0.6 R`
* ADX momentum still ≥ preset minimum (`+2` buffer for adds)
* Distance from base entry ≥ `(addon index + 1) × 0.8 ATR`

## Risk Guard Presets

| Preset | Daily Stop | Weekly Stop | Monthly Stop | Equity Filter |
|--------|------------|-------------|--------------|---------------|
| Conservative | 3% | 1% | 1.2 × weekly | Always on (base 4%) |
| Balanced | 4% | 1.5% | 1.8 × weekly | Adaptive (base 5.5%) |
| Offensive | 5% | 2% | 2.0 × weekly | Adaptive, disabled in `REG_HIGH` when aggressive |

The adaptive equity lock applies `max(base, 0.5 × |WTD loss %|)` and is ignored for aggressive trading during high-volatility regimes. Risk scaling is reduced to 40–100% whenever weekly losses deepen within the preset envelope.

