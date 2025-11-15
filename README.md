# Swing-Trend-EA-Pro-MT5-

A swing-trend Expert Advisor for MetaTrader 5 that focuses on London-session momentum in the direction of the prevailing multi-timeframe bias. The engine combines EMA slope voting across H1/H4/D1 with pullback and breakout pattern evaluation and manages positions through R-multiple based partials, break-even, and trailing behaviour.

## Project layout

- `src/XAU_Swing_TrendEA_Pro.mq5` – main (and only) Expert Advisor wiring inputs, preset defaults, and orchestration logic.
- `src/modules/BiasEngine.mqh` – computes TrendBias with Strong/Moderate/Neutral classification using ATR-normalised EMA slopes and detailed logging.
- `src/modules/EntryEngine.mqh` – evaluates pullback/breakout opportunities, assigns quality scores, and enforces session/fallback rules.
- `src/modules/ExitEngine.mqh` – handles R-multiple management (partials, break-even, trailing, time-stop) and trade state tracking.
- `src/modules/DailyGuard.mqh` & `src/modules/RiskEngine.mqh` – enforce prop-style daily loss caps, trade limits, and losing-streak scaling.
- Additional modules provide regime detection, sizing utilities, and broker abstractions.

## Balanced XAU H1 v2 preset

The default input values in `XAU_Swing_TrendEA_Pro.mq5` now ship as **Balanced XAU H1 v2**, a trend-following profile for XAUUSD on H1 with trading limited to 07:00–14:45 server time and a hard cut-off at 14:00.

| Category | Key parameters |
| --- | --- |
| Risk | `RiskPerTrade=0.60`, `MaxDailyRiskPercent=5`, `MaxEquityDDPercentForCloseAll=12`, `MaxNewTradesPerDay=3`, `RegimeLowRiskScale=0.60`, `RegimeHighRiskScale=1.05` |
| Bias & regime gating | `BiasSlopeThH1/H4/D1=0.020/0.018/0.015`, `BiasScoreThresholdCore/Edge=0.060/0.085`, `BiasScoreRegimeLowBoost=0.015`, `BiasSlopeConfirmH1/H4/D1=0.018/0.014/0.010`, `RequireStrongFallbackSetups=true`, `NeutralBiasRiskScale=0.40` |
| Entries | `PullbackBodyATRMin=0.45`, `BreakoutImpulseATRMin=0.42`, `BreakoutRangeBars=6`, `Core/EdgeScoreThreshold=0.76/0.85`, `RegimeLow/HighQualityBoost=0.06/0.03`, `AllowAggressiveEntries=true` |
| Management | `PartialCloseFraction=0.40`, `BreakEven_R=0.9`, `PartialTP_R=1.1`, `HardTP_R=2.7`, `TrailStart_R=1.8`, `TrailDistance_R=0.9`, `UseHardFinalTP=true`, `MaxBarsInTrade=36`, `TimeStopProtectR=0.5` |
| Discipline & session | `LateEntryCutoff=14:00`, `EnableFallbackEntry=true`, `EnableWeekdayFallback=true`, `MaxLosingTradesPerDay=3`, `MaxLosingTradesInARow=3`, `RiskScaleAfterLosingStreak=0.5` |
| Telemetry | `EnableTradeTelemetry=true`, CSV prefix `xau_balanced_v2` (see below) |

Tuning tips:

* Reduce `BiasScoreThresholdCore/Edge` and `RegimeLowQualityBoost` to admit more trades in high-volatility environments.
* Relax `BiasSlopeConfirm*` if you want to capture earlier trend transitions at the expense of more false starts.
* `LateEntryCutoffHour/Minute` provides a clean toggle for pruning lower-quality late-session trades without altering the base session filter.

## v2 design highlights

* **Slope-score gating** – EMA slope votes now feed a composite score with regime-aware boosts. Neutral signals in a low-volatility regime are blocked, and fallback entries demand fully qualified pullback/breakout patterns.
* **Regime aware risk scaling** – Dynamic adjustments reduce per-trade exposure to 60% in quiet regimes while allowing a light boost (1.05×) when ATR expands.
* **Sharper entry filters** – Pullback and breakout bodies require more momentum (`0.45–0.42 ATR`), score thresholds are lifted (`0.76/0.85`), and range lookback extends to six bars to avoid noise.
* **R-multiple refinements** – Break-even engages at `0.9 R`, partials take 40% at `1.1 R`, and the trailing stop starts later (`1.8 R`) with a tighter leash (`0.9 R`) to protect outsized winners.
* **Session discipline** – A configurable late-entry cut-off prevents new trades after 14:00 even if the base session runs to 14:45, aligning with observed drawdown clusters in the attached report.

## Telemetry logging

Enable `EnableTradeTelemetry` to write two CSV files under the MetaTrader common files directory (`MQL5/Files/XAU_Swing_TrendEA_Pro` by default, or using the configured prefix):

* `*_entries.csv` captures entry-time metadata (ticket, direction, session, regime, risk percent, fallback flag).
* `*_telemetry.csv` appends one row per completed trade including entry/exit timestamps, realised R-multiple, MFE/MAE in R, bars held, detected exit mechanism, and P&L components.

The telemetry feed makes it straightforward to analyse R-distributions, exit causes, and fallback frequency in Python/R without parsing platform logs.

## Strategy Tester checklist

1. **Trade frequency** – Run a 2021–2025 tick backtest on XAUUSD H1 with the v2 preset; expect roughly 2–5 new trades per week. Use `ENTRY TRACE` to verify slope-score gating and the 14:00 cut-off are respected.
2. **Risk/Reward profile** – Cross-check the strategy report and telemetry CSVs: partials should print near `+1.1 R`, breakeven at `+0.9 R`, and trailing exits > `+1.8 R`. The telemetry MFE/MAE columns make it easy to review stop quality.
3. **Risk guards** – Stress test with widened spreads or injected slippage to verify `RISK DEBUG` blocks new trades when daily caps or losing-trade limits are hit. Confirm the overall drawdown kill switch closes open positions when exceeded and that regime risk scaling reduces volume in quiet conditions.

These steps ensure the EA respects prop-style loss constraints while maintaining the intended higher participation rate within the London session.
