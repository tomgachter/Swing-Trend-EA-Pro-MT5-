# Changelog

## [Unreleased]
### Added
- Preset management via `InpPreset` with default `XAUUSD_H1_Default`, including a secondary `XAUUSD_M30_Conservative` profile and centralised application through `ApplyPreset`.
- Expanded risk governance: daily loss stop at 3%, equity drawdown gate, session and news filters, Friday flatten, spread guard, and minimum stop distance buffer.
- Advanced trade management features: ATR/Chandelier trailing, R-based break-even, partial close at 1.5R, time-based exit with winner exemption, and additive pyramiding that respects risk caps.
- Robust MFE/MAE analytics with regression logging via `ReportTradeCorrelations`, plus trade memo tracking for excursion statistics.
- News and session resilience, including equity-underwater pause, slippage retries, and Donchian mapping tied to D1 ATR regime.

### Changed
- Updated all default inputs directly in code to match the requested optimisation values and comments documenting `XAUUSD H1` defaults.
- Refactored parameter access to flow through `EAConfig` for preset-aware runtime configuration.
- Revised tester score in `OnTester` to use `ProfitFactor * Sharpe / (1 + MaxDD%)` with trade-count guard.
- Enhanced slope filter to use ATR-normalised EMA gradients with configurable minimum slope.

### Fixed
- Ensured position handling and memo lifecycle stay consistent even under external closes (SL/TP), preserving statistics and risk state.
