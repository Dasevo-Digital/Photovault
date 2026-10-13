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

Die Suche nach Bildinhalt bettet den Suchtext auf dem Server ein
(`POST /api/v1/suche/text`); die Rangfolge rechnet das Telefon mit den
abgeglichenen Einbettungen, wie der Desktop. Hat der Server kein Modell,
sucht die App im Text.

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
