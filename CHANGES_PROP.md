# Prop-Firm Compliance Changes

## Neue Schutzmechanismen
- Tagesverlustlimit basiert nun auf Equity-Ankern mit Global-Variable-Persistenz und Zeitoffset (`PropFirmDayStartHour`).
- Statischer Gesamt-Drawdown-Stop basierend auf Initial-Equity (`UseStaticOverallDD`).
- Pre-Trade Budget berücksichtigt Worst-Case-Slippage (`SlippageBudgetPoints`).
- Spread-Filter verhindert Orders bei zu hohem Spread (`MaxSpreadPoints`).
- Order-Retry/Backoff bei Requotes/OFF_QUOTES/PRICE_CHANGED implementiert.
- Flatten erfolgt automatisch bei Tageslimit- oder Gesamt-DD-Verletzung.

## Neue/angepasste Inputs
- `PropFirmDayStartHour`
- `UseStaticOverallDD`
- `SlippageBudgetPoints`
- `MaxSpreadPoints`
- `MaxEquityDDPercentForCloseAll` Default auf 10 % reduziert

## Persistenz
- Equity-Anker (`_ANCHOR`), Tages-Serial (`_SERIAL`) und Initial-Equity (`_INIT`) werden unter dem Key `STEA:<SYMBOL>:<MAGIC>` gesichert.

## Hygiene
- Spread-Filter-Logging und Hinweis zum Freigeben von Indikator-Handles in `OnDeinit`.
