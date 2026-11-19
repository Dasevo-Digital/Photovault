# Zeitbezug der Erinnerungsfilter

Das gespeicherte Format 2 enthält je Zeitraum die angezeigten Kalendertage
`von` und `bis` sowie die UTC-Zeitpunkte `vonUtc` und `bisUtc`. Der Beginn
gehört zum Ausschluss, das Ende ist exklusiv. Beim Anlegen entsteht der
Beginn aus der lokalen Mitternacht des ersten Tages, das Ende aus der
lokalen Mitternacht nach dem letzten Tag. Jeder Endpunkt wird getrennt
umgerechnet, damit ein Sommerzeitwechsel berücksichtigt wird.

Beispiel: Der 02.01.2020 in Europe/Berlin reicht von
`2020-01-01T23:00:00Z` einschließlich bis `2020-01-02T23:00:00Z`
ausschließlich. Datenbankabfragen und direkte Filter vergleichen diese
Zeitpunkte. Die Zeitzone des auswertenden Servers verändert sie nicht.
Auch Bearbeiten, Synchronisieren und Wiederherstellen bewahren vorhandene
UTC-Grenzen.

Format 1 enthielt keinen Zeitbezug. Seine Personen, Alben und Kalendertage
bleiben lesbar und erhalten. Bei alten Zeiträumen bleiben automatische
Rückblicke bis zur Bestätigung gesperrt. Abbrechen verändert nichts;
ausdrückliches Speichern im Filterdialog bestätigt die alten Zeiträume
anhand der Zeitzone des bearbeitenden Geräts. Wiederherstellung darf diese
Bestätigung nicht stillschweigend vorwegnehmen.

Neue Befehle mit Zeiträumen ohne UTC-Grenzen werden abgewiesen. Für den
verbundenen Betrieb benötigen alle Beteiligten Unterstützung für Format 2;
ältere Programme können solche Filter nicht bearbeiten. Das Datenbankschema
bleibt unverändert, da der Filter bereits als versionierter JSON-Text
gespeichert wird.

Die Regressionen prüfen Erzeugen und Lesen in getrennten Prozessen unter
Europe/Berlin und UTC, die Mitternachtsgrenzen, Sommerzeit und Jahreswechsel,
die Bestätigung alter Filter und den Erhalt beim Bearbeiten und Zusammenführen.
Unter Windows werden vorgegebene UTC-Grenzen geprüft, da die Auswertung der
Unix-Variablen `TZ` dort keine verlässliche Zeitzonenumschaltung bietet.
