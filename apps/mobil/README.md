# Photo Vault für das Telefon

Die Bibliothek eines Photo Vault Servers auf dem Telefon: Zeitleiste,
Betrachter (Fotos und Videos), Suche nach Bildinhalt und Text, Alben,
Personen, Karte und Teilen.

Das Telefon hält wie der verbundene Desktop eine Kopie der Bibliothek
(`packages/kern`, `Abgleich`). Listen, Alben, Karte und die Textsuche
laufen deshalb auch ohne Verbindung. Bilder kommen erst vom Server, wenn
sie gebraucht werden, und bleiben danach auf dem Telefon. Änderungen
(Favorit, Papierkorb) gehen als Befehle zum Server; ohne Verbindung warten
sie und gehen später nach.

Der Betrachter zeigt jedes Foto in voller Auflösung: zuerst die Vorschau,
darüber das Original, sobald es da ist, beim Zoomen ungekürzt dekodiert.
HEIC, RAW und DNG liest das Telefon nicht selbst; der Server wandelt sie
dafür in ein JPEG in Originalgrösse (`GET /api/v1/aufnahmen/<id>/voll`).
Die Fassung liegt danach im Zwischenspeicher unter `previews/voll/` und
gehört bei angehefteten Alben zu dem, was offline bereitsteht.

Die Suche nach Bildinhalt bettet den Suchtext auf dem Server ein
(`POST /api/v1/suche/text`); die Rangfolge rechnet das Telefon mit den
abgeglichenen Einbettungen, wie der Desktop. Hat der Server kein Modell,
sucht die App im Text.

## Kamerarolle sichern

Unter „Konto → Kamerarolle sichern“. Gesichert wird das Original jedes
Fotos und Videos (bei Live Photos Bild und Video unter demselben
Namensstamm, damit der Server sie paart), der neueste Eintrag zuerst.
Ein in der Fotos-App bearbeitetes Foto (iOS) bringt zusätzlich seine
bearbeitete Fassung mit; der Server legt sie wie eine Bearbeitung am
Rechner über das Original, das als Variante dahinter bleibt (#271).

- Vor dem Hochladen fragt die App den Server nach den Prüfsummen
  (`POST /api/v1/pruefsummen`); was er schon hat, etwa nach einem Umzug
  vom Rechner, geht nicht noch einmal über das Netz.
- Was einmal sicher ist, merkt sich die App in `sicherung.sqlite` neben der
  Kopie der Bibliothek. Am Server gelöschte Fotos kommen deshalb nicht
  wieder; erst eine Bearbeitung am Telefon lässt einen Eintrag noch einmal
  prüfen.
- Ein abgebrochener Upload geht beim nächsten Lauf an der Stelle weiter,
  die der Server hat – auch nach einem Neustart.
- Was der Server beim Import ablehnt, bleibt liegen, bis „Erneut
  versuchen“ gedrückt wird; andere Fehler pausieren nach drei Versuchen für
  zwölf Stunden.

Im Hintergrund: unter Android eine periodische Aufgabe von WorkManager
(alle 15 Minuten, mit WLAN und Laden als Bedingung, wenn eingestellt);
verlässt man die App mit offener Arbeit, lädt ein Vordergrunddienst
(`dataSync`) mit Benachrichtigung weiter. Unter iOS eine
Verarbeitungsaufgabe (`BGProcessingTask`), die das System meist nachts am
Ladekabel laufen lässt.

Für ein gerade aufgenommenes Foto ist das zu selten. Deshalb gibt es
zusätzlich die Zeile „Sofort im Hintergrund“ (`lib/sicherung/sofort.dart`):

- **Android:** `Fotowaechter.kt` wartet auf neue Einträge im MediaStore und
  startet einen Lauf. Das Foto ist nach Sekunden auf dem Server, auch wenn der
  Prozess der App beendet ist. Eine selten geöffnete App hält Android
  zurück, laut seinen Einstellungen bis zu rund 31 Minuten. „Nicht
  zurückhalten“ nimmt sie von der Akku-Optimierung aus; der Nutzer bestätigt
  das im Dialog des Systems.
- **iOS:** die Erweiterung `ios/Sofortsicherung` (ab iOS 26.5). Das System
  startet sie, wenn Netz und Akku passen, und lädt die Originale selbst mit
  `PUT /api/v1/sofort` hoch, auch im gesperrten Telefon. **Wann, bestimmt
  iOS.** Sie braucht Zugriff auf alle Fotos und bleibt mit „Im Hintergrund
  nur beim Laden“ aus. `BackgroundUploadURLBase` in ihrer Info.plist dient
  dem System nur als Prüfung, ob das Netz da ist: Die Adresse muss erreichbar
  sein, ist aber nicht die des eigenen Servers. Was die Erweiterung nicht
  schafft, holt die App beim nächsten Lauf nach; eine doppelt geschickte
  Datei erkennt der Server an der Prüfsumme.

Die Erweiterung läuft nicht im Simulator. Was sie aufgibt, prüft
`ios/RunnerTests/SofortauswahlTests.swift` dort trotzdem gegen die echte
Mediathek. Auf dem Gerät hilft Einstellungen → Entwickler → Resource Upload
Test Mode.

## Kennungen

| Variante | Android | iOS | Name |
|---|---|---|---|
| Debug, Profile | `de.dasevo.photovault.test` | `de.dasevo.photovault.test` | Photo Vault (Test) |
| Release | `de.dasevo.photovault` | `de.dasevo.photovault` | Photo Vault |

Die Telefon-Bauten des Desktop-Projekts heissen
`de.dasevo.photovault.desktop`, damit sie der App nicht in die Quere
kommen.

## Bauen und prüfen

```bash
flutter test                        # startet einen Server aus packages/server
flutter build apk --debug
flutter build ios --simulator --debug
```

Ein Android-Release braucht `android/keystore.properties` (siehe
`android/keystore.properties.example`); ohne sie bricht der Bau ab, statt
mit dem Debug-Schlüssel zu signieren.

## Verbindung ohne TLS

`http://` ist nur zu Adressen im eigenen Netz erlaubt (Namen ohne Punkt,
`.local`, private, Loopback- und VPN-Bereiche; `ohneTlsErlaubt` im Kern).
Alles andere braucht `https://`. Android lässt Klartext deshalb im
Manifest zu, iOS über `NSAllowsLocalNetworking`.
