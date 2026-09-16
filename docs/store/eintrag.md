# Photo Vault im Microsoft Store

Alles, was für die Einreichung gebraucht wird — und die Trennung
zwischen dem, was hier vorbereitet ist, und dem, was nur der
Kontoinhaber selbst tun kann.

## Warum überhaupt

Smart App Control weist unsignierte Programme ohne Ruf ab; auf dem
Windows-Prüfrechner startet 3.2.0 und 3.3.0 deshalb gar nicht
(CodeIntegrity 3077/3118, Richtlinie
`{0283ac0f-fff1-49ae-ada1-8a933130cad6}`). Aus dem Store bezogene
Pakete umgeht Smart App Control **vollständig** — Microsoft signiert sie
neu. Ein gekauftes Zertifikat gäbe dagegen nur Grundvertrauen, und der
Ruf müsste sich über Downloadzahlen aufbauen, die eine App mit drei
Installationen nie erreicht.

Das Zip zum Auspacken bleibt daneben bestehen.

## Was nur du tun kannst

1. **Konto anlegen.** Über `https://storedeveloper.microsoft.com`,
   „Get started for free", **Individual developer**. Seit Juni 2025
   ohne Gebühr, in fast 200 Märkten. Es braucht einen amtlichen Ausweis
   und ein Selfie; danach geht es direkt ins Partner Center.
   *Der geprüfte Name erscheint öffentlich als Herausgeber.*
2. **Namen reservieren.** Im Partner Center einen App-Namen reservieren
   (z.B. „Photo Vault"). Daraus ergeben sich zwei Werte, die das Paket
   zeichengenau tragen muss — sie stehen unter **Produktidentität**:
   - **Package/Identity/Name** (etwa `12345Name.PhotoVault`)
   - **Package/Identity/Publisher** (etwa `CN=ABCDEF12-3456-…`)
3. **Datenschutz-Adresse.** `docs/datenschutz.md` und `docs/privacy.md`
   sind geschrieben, aber der verantwortliche Name und die
   Kontaktadresse fehlen — die einzutragen ist deine Entscheidung, weil
   sie damit öffentlich werden. Danach brauchen sie eine erreichbare
   URL (der öffentliche Spiegel genügt).
4. **Altersfreigabe.** Der IARC-Fragebogen im Partner Center. Die App
   zeigt eigene Fotos und hat keine Käufe, keine Werbung und keinen
   Austausch mit anderen Nutzern.
5. **Sichtbarkeit wählen.** Für ein privates Werkzeug passt „verfügbar,
   aber nicht auffindbar" (Installation nur über den Direktlink). Die
   Zertifizierung läuft trotzdem vollständig.

## Was hier fertig ist

**Das Paket bauen** — erst das Verzeichnis, dann das MSIX:

    tool\windows_bauen.ps1 -Pruefen
    tool\windows_msix.ps1 -Store `
        -IdentitaetsName "12345Name.PhotoVault" `
        -HerausgeberId "CN=ABCDEF12-3456-…" `
        -HerausgeberAnzeige "Dein geprüfter Name"

Signiert wird dabei **nicht**: Microsoft signiert beim Einreichen neu,
und genau daher kommt der Ruf. Eine eigene Signatur würde verworfen.

**Bildschirmfotos.** Im öffentlichen Spiegel unter
`docs/screenshots/`: `timeline.png`, `karte.png`, `personen.png`,
`entwickeln.png`, dazu drei Stammbaum-Ansichten. Sie zeigen
ausschliesslich frei lizenzierte Beispielbilder — die Regel steht in
`docs/screenshots/README.md` und gilt hier genauso: Aus einer echten
Bibliothek darf nichts in den Store.

## Texte für die Ladenseite

### Kurzbeschreibung (deutsch)

> Fotoverwaltung für den eigenen Rechner: Gesichter, Orte, Suche nach
> Bildinhalt, RAW-Entwicklung und Stammbaum — ohne Konto, ohne Cloud,
> ohne Nutzungsmessung.

### Short description (English)

> A photo manager for your own computer: faces, places, search by image
> content, RAW development and a family tree — no account, no cloud, no
> telemetry.

### Beschreibung (deutsch)

> Photo Vault verwaltet Ihre Fotos und Videos dort, wo sie hingehören:
> auf Ihrem Rechner. Es gibt kein Benutzerkonto, keinen Serverdienst und
> keine Nutzungsmessung.
>
> Die Bilderkennung läuft vollständig lokal. Gesichter werden erkannt
> und zu Personen gruppiert, Schlagwörter und Bildbeschreibungen
> entstehen auf dem eigenen Gerät, und die Suche versteht, was auf einem
> Bild zu sehen ist — „Sonnenuntergang am Meer" findet den Sonnenuntergang
> am Meer, auch ohne dass jemand ihn beschriftet hat. Kein Bild verlässt
> dafür den Rechner.
>
> Aus den Aufnahmeorten entstehen Karten, Reisen und Aktivitäten. Der
> Stammbaum verbindet die Personen aus Ihren Fotos zu Haushalten und
> Generationen und lässt sich als Zierbaum drucken. RAW-Dateien lassen
> sich entwickeln — Belichtung, Kurven, Farbmischer, Masken —, und jeder
> Schritt bleibt umkehrbar.
>
> Einzelne Fotos lassen sich sperren. Sie werden dann mit AES-256-GCM
> verschlüsselt; der Schlüssel entsteht aus Ihrem Kennwort und verlässt
> den Rechner nicht.
>
> Photo Vault gibt es ebenso für macOS und Linux. Die Bibliothek ist auf
> allen drei Systemen dieselbe.

### Description (English)

> Photo Vault keeps your photos and videos where they belong: on your
> own computer. No account, no server, no telemetry.
>
> Image recognition runs entirely on your machine. Faces are detected
> and grouped into people, tags and captions are produced on the device,
> and search understands what a picture shows — "sunset at the sea"
> finds the sunset at the sea even though nobody labelled it. No image
> leaves the computer for any of this.
>
> Capture locations become maps, trips and activities. The family tree
> connects the people from your photos into households and generations
> and prints as an ornamental chart. RAW files can be developed —
> exposure, curves, colour mixer, masks — and every step stays
> reversible.
>
> Individual photos can be locked. They are then encrypted with
> AES-256-GCM; the key is derived from your password and never leaves
> the machine.
>
> Photo Vault is also available for macOS and Linux, with the same
> library on all three.

### Merkmale / Features

- Gesichtserkennung und Personen, vollständig lokal — Face recognition and people, entirely local
- Suche nach Bildinhalt statt nach Dateinamen — Search by image content, not by file name
- Karten, Reisen und Aktivitäten aus den Aufnahmeorten — Maps, trips and activities from capture locations
- Stammbaum mit Zierbaum-Druck — Family tree with an ornamental printed chart
- RAW entwickeln, jeder Schritt umkehrbar — Develop RAW, every step reversible
- Einzelne Fotos mit AES-256-GCM sperren — Lock individual photos with AES-256-GCM
- Kein Konto, keine Cloud, keine Nutzungsmessung — No account, no cloud, no telemetry

### Suchbegriffe

`Fotoverwaltung`, `photo manager`, `RAW`, `Gesichtserkennung`,
`Stammbaum`, `offline`, `Privatsphäre`

### Kategorie

Fotos und Video → Fotobearbeitung (Photo & video → Photo editing)

## Nach der Freigabe

Die Zertifizierung dauert ein bis drei Werktage. Bei einer Ablehnung
nennt das Partner Center den Grund; die beiden wahrscheinlichsten
Stellen sind unten genannt.

## Die zwei bekannten Risiken

**LGPL-ffmpeg.** Das Paket liefert einen LGPL-shared-Bau von BtbN mit
(`tool/windows_werkzeuge.ps1`). ffmpeg ist dabei ein eigenständiges
Kindprogramm und wird nicht gelinkt — der günstigste denkbare Fall —,
aber die Store-Bedingungen schränken die Weitergabe ein, während die
LGPL verlangt, dass Neulinken möglich bleibt. Das ist die Stelle mit der
grössten Unsicherheit.

**Eigener HEVC-Dekoder.** libheif und ffmpeg bringen HEVC mit, statt
Microsofts kostenpflichtige „HEVC Video Extensions" vorauszusetzen.
Technisch die bessere Lösung, im Store eine Patentfrage.

## Belegt, bevor eingereicht wird

In der Windows-Sandbox — einem wirklich sauberen System — mit dem
selbstsignierten MSIX gemessen:

| | |
|---|---|
| Installation | 6,4 s |
| App | volle Oberfläche, 115 MB, 94 Module |
| KI | `onnxruntime.dll` geladen |
| Werkzeuge aus `WindowsApps` | `ffmpeg` schreibt ein Bild, `heif-dec` entschlüsselt HEIC zu 1200 × 800 |
| Datenordner | wechselt in den Paketbehälter — die Paketfassung benutzt aber weiter, was am alten Ort liegt |
