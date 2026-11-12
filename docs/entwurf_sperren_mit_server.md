# Entwurf: Sperren mit Server (#360)

Ohne Server verschlüsselt der Rechner gesperrte Fotos an Ort und Stelle
(`VaultCrypto`: AES-256-GCM, ein zufälliger Hauptschlüssel, mit dem PIN
über Argon2id verpackt). Mit Server geht Sperren bisher nicht (#302): Die
Dateien liegen dort im Klartext, und der Server rechnet mit ihnen. Dieses
Dokument beschreibt, wie es gehen soll, bevor Code entsteht.

## Ziel und Grenzen

- Gesperrte Fotos liegen auf dem Server nur verschlüsselt. Der Schlüssel
  verlässt die Geräte nie im Klartext; der Server sieht weder Bild noch
  Schlüssel.
- Rechner und Handy desselben Kontos entsperren mit derselben Passphrase.
- **Schutz vor:** jemandem mit Zugriff auf Platte, Datenbank oder
  Sicherungen des Servers, die *nach* dem Sperren entstanden sind.
- **Kein Schutz vor:** älteren Sicherungen und Schnappschüssen (darin liegt
  der Klartext von vorher, bis sie ablaufen), einem Server, der bösartigen
  Code an den Browser ausliefert (deshalb entsperrt der Browser nicht,
  siehe unten), einem entsperrten Gerät.

## Schlüssel

- **Ein Hauptschlüssel je Bibliothek** (256 Bit, zufällig), erzeugt auf dem
  Gerät, das zum ersten Mal sperrt. Mit der Passphrase verpackt wie heute
  mit dem PIN (`VaultCrypto.wrapMasterKey`, Argon2id 64 MiB, 3 Durchgänge).
- Der **verpackte** Schlüssel liegt als undurchsichtiger Wert in einer
  abgeglichenen Einstellung der Bibliothek. So holt ihn jedes Gerät, und
  ein PIN-Wechsel verpackt nur neu, statt Dateien neu zu verschlüsseln.
- **Passphrase statt PIN, mindestens 10 Zeichen.** Der Server könnte das
  Verpackte offline durchprobieren; ein Versuch kostet etwa eine halbe
  Sekunde, eine sechsstellige PIN fiele so in Stunden bis Tagen. Damit
  das Eintippen selten bleibt, hält das Gerät den Schlüssel nach dem
  ersten Entsperren im Schlüsselbund (Face ID, Touch ID, Windows Hello).
  Eine Bibliothek ohne Server, die schon einen PIN hat, verlangt beim
  Verbinden einmal eine Passphrase und verpackt den Schlüssel damit neu.
- **Wiederherstellungsschlüssel:** Beim Einrichten wird der Hauptschlüssel
  zusätzlich mit einem zufälligen 128-Bit-Code verpackt, den man
  ausdruckt (als Wortliste oder in Gruppen, mit Prüfziffer). Auch er liegt
  nur verpackt am Server. Ohne Passphrase und ohne diesen Code sind die
  Fotos verloren.

## Sperren

Verschlüsselt wird auf dem Gerät, nicht auf dem Server:

1. Das Gerät holt alle Dateien der Aufnahme (`dateienDerAufnahme`:
   Original, Miniatur, Vorschau, Entwicklung, Schnitt, Masken,
   Gesichtsausschnitte).
2. Es verschlüsselt jede mit dem Hauptschlüssel im heutigen Format (PVB1)
   und bindet Aufnahme und Rolle der Datei als AAD, damit sich zwei
   Dateien nicht vertauschen lassen. Die privaten Angaben (Beschreibung,
   Bildbeschreibung, erkannter Text, Transkript, Ort, Schlagwörter)
   gehen als ein verschlüsselter Datensatz mit, wie heute am Rechner.
3. Es lädt die Chiffrate wie beim Hochladen in den Zwischenbereich des
   Servers (vorhandener Upload-Weg, fortsetzbar).
4. Ein Befehl **„Sperren abschliessen“** nennt je Rolle das Hochgeladene.
   Der Server prüft Grösse und Kennung (PVB1) und tauscht in einer
   Transaktion: Dateien ersetzen, `is_locked` setzen, die Klartextspalten
   leeren. Ausserdem entfernt er Einbettungen, Gesichter und Treffer der
   Suche zu dieser Aufnahme. Erst nach dem Abschluss löscht er den
   Klartext von der Platte.
5. Scheitert etwas vor Schritt 4, bleibt alles, wie es war; der
   Zwischenbereich räumt sich nach Ablauf selbst auf.

Gesperrte Aufnahmen nimmt der Server aus allen Auswertungen, Freigaben,
geteilten Alben, Erinnerungen, der Partner-Zeitleiste und der
Duplikatsuche. Viele dieser Filter gibt es dank `is_locked` schon; zu
prüfen ist jede Auswertungsstufe und jeder Endpunkt, der Dateien
ausliefert.

## Ansehen und Entsperren

- **Ansehen:** Der Server liefert dem eigenen Konto die Chiffrate unter
  einer eigenen Art (etwa `tresor/<rolle>`). Das Gerät entschlüsselt im
  Speicher oder in einem Zwischenordner, den „Sperren“ und das Beenden
  leeren (wie `sperreTresor` heute).
- **Entsperren** ist der Weg zurück: entschlüsseln, Klartext hochladen,
  Befehl „Entsperren abschliessen“. Danach wertet der Server die Aufnahme
  wieder aus.
- **Browser:** Er zeigt gesperrte Fotos nicht und entsperrt nicht.
  Schlüsselarbeit im Browser hiesse, dem Server bei jedem Laden des
  Skripts zu vertrauen, und genau davor soll das Sperren schützen.

## Bestehende Daten und gemischte Fassungen

- Eine Bibliothek ohne Server, die schon Gesperrtes hat, bringt beim
  Verbinden ihren Hauptschlüssel als verpackten Wert mit. Die Dateien
  sind schon im richtigen Format und gehen unverändert hoch.
- Ältere Geräte kennen die neuen Befehle nicht. Der Server meldet die
  Fähigkeit in `/api/v1/zustand` (etwa `'tresor': 1`); ein älteres Gerät
  zeigt gesperrte Aufnahmen wie heute gar nicht.
- **Sicherungen:** Die Serversicherung und die Sicherung ausser Haus
  enthalten nach dem Sperren nur noch Chiffrat. Ältere Stände behalten
  den Klartext bis zu ihrem Ablauf. Die Oberfläche sagt das beim ersten
  Sperren.

## Schritte

1. Kern und Server: Einstellung für den verpackten Schlüssel, die Befehle
   „Sperren/Entsperren abschliessen“ mit Tausch in einer Transaktion,
   Auslieferung der Chiffrate, Ausschluss aus Auswertungen und Freigaben.
   Tests für Tausch, Abbruch und jeden Ausschluss.
2. Rechner verbunden: die vorhandenen Abläufe (`VaultCrypto`, Sperren,
   Entsperren, Ansehen) auf den neuen Weg umstellen.
3. Wiederherstellungsschlüssel zum Ausdrucken und Schlüsselbund am
   Rechner.
4. Handy: Passphrase oder Face ID, dann gesperrte Fotos ansehen und
   teilen (Argon2id in reinem Dart braucht auf einem aktuellen iPhone etwa
   eine bis zwei Sekunden, danach hält der Schlüsselbund den Schlüssel).
5. Später: Sperren und Entsperren auch am Handy.

Jeder Schritt ist für sich nutzbar und lässt sich prüfen. Aufwand: gross,
mehrere Runden.

## Entschieden (12.11.2026)

- Passphrase mit mindestens 10 Zeichen statt PIN.
- Wiederherstellungsschlüssel zum Ausdrucken: ja.
- Handy zuerst nur ansehen und teilen; Sperren und Entsperren dort
  später.
