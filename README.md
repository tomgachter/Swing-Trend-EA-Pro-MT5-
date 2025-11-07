# Swing-Trend-EA-Pro-MT5-

A simple Trend Following EA for MetaTrader 5.

The default presets are tuned for higher participation: the hybrid entry mode can trigger on both Donchian breakouts and EMA pullbacks, trend confirmation requires fewer votes with a gentler slope and ADX threshold, and the cooldown/session/extension guards are relaxed so the EA reacts faster when momentum returns.

## Files

- `src/XAU_Swing_TrendEA_Pro.mq5`: Primary Expert Advisor source.
- `src/modules/`: Shared utility modules used by the EA.
