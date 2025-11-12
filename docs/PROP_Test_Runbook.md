# PROP Test Runbook

## Szenarienübersicht
| ID | Szenario | Setup | Erwartung |
|----|----------|-------|-----------|
| T1 | Intraday Equity Drop > 5 % | Simuliere Verlusttrades nach Tagesstart; `PropFirmDayStartHour` passend setzen | EA schließt alle Positionen, keine neuen Orders bis Tagesreset |
| T2 | Tagesreset mit Persistenz | EA stoppen >5 min, erneut starten innerhalb der Session | Tagesanker (`_ANCHOR`) bleibt erhalten, keine Reset-Lücke |
| T3 | Gesamt-DD > 10 % | Initial-Equity 10k, Verluste >1k | Sofortiges Flatten, neue Orders blockiert |
| T4 | Slippage-Budget-Test | Setze `SlippageBudgetPoints` hoch/niedrig und Stopdistanz klein | Pre-Trade-Check verweigert Trades wenn `dayLoss + riskWCS` > Limit |
| T5 | Spread-Filter | Erhöhe Spread künstlich (Tester: FixSpread) | Entry wird mit Log/Annotation verworfen |
| T6 | Order Retry | Simuliere Requotes (Delay/Mode) | Bis zu 3 Versuche mit Backoff, Erfolg oder sauberer Abbruch |

## Prüfschritte
1. Strategy Tester im `Every tick`-Modus starten, relevante Inputs setzen.
2. Für T1/T3: Equity-Kurve beobachten, Journal auf Meldungen "Daily equity loss limit breached" und "Equity drawdown kill switch triggered" prüfen.
3. Für T2: EA entfernen, erneut anhängen, Global-Variablen (`STEA:*`) prüfen (Navigator -> Global Variables).
4. Für T4: Stop-Loss stark verengen, `SlippageBudgetPoints` erhöhen -> erwarten, dass `Risk guard prevented entry` erscheint.
5. Für T5: Spread > `MaxSpreadPoints` erzwingen -> Log mit "Spread ... Entry verworfen" prüfen.
6. Für T6: Broker-Simulator mit Requotes -> Journal zeigt Retry-Versuche (Trade kontext ohne Fehlerstop).

## Erfolgskriterien
- Keine Verstöße gegen Tages-/Gesamt-Limits.
- Alle Schutzmechanismen erzeugen nachvollziehbare Log-Einträge.
- EA kompiliert ohne Warnungen/Fehler.
