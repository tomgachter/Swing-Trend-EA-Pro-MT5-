# Swing-Trend-EA-Pro-MT5-

A swing-trend Expert Advisor for MetaTrader 5 that focuses on London-session momentum in the direction of the prevailing multi-timeframe bias. The engine combines EMA slope voting across H1/H4/D1 with pullback and breakout pattern evaluation and manages positions through R-multiple based partials, break-even, and trailing behaviour.

## Project layout

- `src/XAU_Swing_TrendEA_Pro.mq5` – main Expert Advisor wiring inputs, preset defaults, and orchestration logic.
- `src/modules/BiasEngine.mqh` – computes TrendBias with Strong/Moderate/Neutral classification using ATR-normalised EMA slopes and detailed logging.
- `src/modules/EntryEngine.mqh` – evaluates pullback/breakout opportunities, assigns quality scores, and enforces session/fallback rules.
- `src/modules/ExitEngine.mqh` – handles R-multiple management (partials, break-even, trailing, time-stop) and trade state tracking.
- `src/modules/DailyGuard.mqh` & `src/modules/RiskEngine.mqh` – enforce prop-style daily loss caps, trade limits, and losing-streak scaling.
- Additional modules provide regime detection, sizing utilities, and broker abstractions.

## Balanced XAU H1 preset

The default input values in `XAU_Swing_TrendEA_Pro.mq5` form the **Balanced XAU H1** configuration targeted at XAUUSD on H1 between 07:00–14:45 server time.

| Category | Key parameters |
| --- | --- |
| Risk | `RiskPerTrade=0.75`, `MaxDailyRiskPercent=5`, `MaxEquityDDPercentForCloseAll=12`, `MaxNewTradesPerDay=5` |
| Bias | `BiasSlopeThH1=0.020`, `BiasSlopeThH4=0.018`, `BiasSlopeThD1=0.015`, `AllowNeutralBiasOnEdge=true`, `NeutralBiasRiskScale=0.50` |
| Entries | `MinEntryQualityCore=0.70`, `MinEntryQualityEdge=0.80`, `AllowAggressiveEntries=true`, `BreakoutRangeBars=5` |
| Management | `PartialCloseFraction=0.50`, `BreakEven_R=1.0`, `PartialTP_R=1.2`, `FinalTP_R=2.5`, `TrailStart_R=1.5`, `TrailDistance_R=1.0`, `MaxBarsInTrade=30` |
| Discipline | `MaxLosingTradesPerDay=3`, `MaxLosingTradesInARow=3`, `RiskScaleAfterLosingStreak=0.5` |

To adapt the preset for other symbols or sessions, adjust the bias slope thresholds and session window in the main file. The entry quality thresholds provide the quickest way to increase/decrease trade frequency without disturbing risk management.

## Strategy Tester checklist

1. **Trade frequency** – Run a 2025 tick backtest on XAUUSD H1 with the balanced preset; expect roughly 3–7 new trades per week. Use the `ENTRY DEBUG` logs to confirm fallback moderation activates after the configured hour.
2. **Risk/Reward profile** – Inspect the report’s average profit vs. loss and confirm partial closes and final exits line up with the configured R-multiples (check `EXIT DEBUG` logs for break-even/partial events).
3. **Risk guards** – Stress test with widened spreads or injected slippage to verify `RISK DEBUG` blocks new trades when daily caps or losing-trade limits are hit. Confirm the overall drawdown kill switch closes open positions when exceeded.

These steps ensure the EA respects prop-style loss constraints while maintaining the intended higher participation rate within the London session.
