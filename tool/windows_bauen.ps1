# Baut Photo Vault als Windows-Paket.
#
#   tool\windows_bauen.ps1 [-Pruefen] [-Zip]
#
#
#   FUER EINE AUSLIEFERUNG IMMER -Pruefen MIT ANGEBEN.
#   Am 03.09.2026 ist ein Paket entstanden, in dem heif-dec.exe drei DLLs
#   fehlten und mit 0xC0000135 gar nicht startete - HEIC und AVIF waeren
#   unlesbar gewesen. Die Pruefung unten haette genau das gemeldet
#   ("keine Ausgabe, Rueckgabewert"); sie lief nur nicht, weil der Bau
#   mit -Zip allein gestartet wurde. Aufgefallen ist es erst beim
#   Vergleich der Dateiliste mit der Vorgaengerfassung.
#
#     -Pruefen  Nach dem Bau nachsehen, ob die mitgelieferten Werkzeuge
#               wirklich da sind und koennen, was sie sollen - und zwar
#               OHNE den PATH dieses Rechners.
#     -Zip      Das fertige Verzeichnis einpacken.
#
# Hier entsteht ein Verzeichnis zum Auspacken - das entspricht dem, was
# das Flatpak unter Linux leistet: alles dabei, nichts nachzuinstallieren.
# Das bleibt die Auslieferung fuer alle, die direkt herunterladen.
#
# Fuer den Microsoft Store braucht es ein MSIX, und nur der Store loest
# Smart App Control: Aus dem Store bezogene Pakete werden von Microsoft
# neu signiert und dort gar nicht erst geprueft. Das MSIX baut
# tool\windows_msix.ps1 AUS dem Ergebnis dieses Skripts - erst hier
# bauen, dann dort verpacken.
[CmdletBinding()]
param([switch]$Pruefen, [switch]$Zip)

$ErrorActionPreference = 'Stop'

# PowerShell 5.1 wertet unter ErrorActionPreference=Stop jede Ausgabe eines
# fremden Programms auf stderr als abbrechenden Fehler - auch eine blosse
# Warnung. `flutter build` schreibt dorthin. Bisher ging es gut, aber nur
# zufaellig; in windows_werkzeuge.ps1 hat genau das einen Lauf still
# beendet, mit Rueckgabewert 0 und halbem Ergebnis.
function Fremd {
  param([string]$Programm, [string[]]$Argumente)
  $alt = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    & $Programm @Argumente 2>&1 | ForEach-Object { Write-Host "  $_" }
    return $LASTEXITCODE
  } finally { $ErrorActionPreference = $alt }
}

# Liest die Importtabelle einer PE-Datei. Ohne dumpbin, das ist nur mit
# Visual Studio da - und genau darauf soll sich diese Pruefung nicht
# verlassen: Ein Baurechner mit Visual Studio hat die Laufzeit ohnehin,
# der Rechner des Nutzers nicht.
function Importe($pfad) {
  try {
    $b = [IO.File]::ReadAllBytes($pfad)
    if ($b.Length -lt 0x40 -or $b[0] -ne 0x4D -or $b[1] -ne 0x5A) { return @() }
    $pe = [BitConverter]::ToInt32($b, 0x3C)
    if ($pe -le 0 -or $pe + 120 -ge $b.Length) { return @() }
    $opt = $pe + 24
    $magic = [BitConverter]::ToUInt16($b, $opt)
    $dirOff = if ($magic -eq 0x20b) { $opt + 112 } else { $opt + 96 }
    $impRva = [BitConverter]::ToUInt32($b, $dirOff + 8)
    if ($impRva -eq 0) { return @() }
    $nSec = [BitConverter]::ToUInt16($b, $pe + 6)
    $secOff = $opt + [BitConverter]::ToUInt16($b, $pe + 20)
    $sec = @()
    for ($i = 0; $i -lt $nSec; $i++) {
      $o = $secOff + $i * 40
      $sec += [pscustomobject]@{
        VA  = [BitConverter]::ToUInt32($b, $o + 12)
        Sz  = [BitConverter]::ToUInt32($b, $o + 16)
        Raw = [BitConverter]::ToUInt32($b, $o + 20) }
    }
    $r2o = { param($rva) foreach ($s in $sec) {
      if ($rva -ge $s.VA -and $rva -lt $s.VA + $s.Sz) { return $s.Raw + ($rva - $s.VA) } }; return 0 }
    $o = & $r2o $impRva
    if ($o -eq 0) { return @() }
    $aus = @()
    while ($o + 20 -lt $b.Length) {
      $nameRva = [BitConverter]::ToUInt32($b, $o + 12)
      if ($nameRva -eq 0) { break }
      $no = & $r2o $nameRva
      if ($no -eq 0) { break }
      $n = ''
      while ($no -lt $b.Length -and $b[$no] -ne 0) { $n += [char]$b[$no]; $no++ }
      $aus += $n
      $o += 20
    }
    return $aus
  } catch { return @() }
}

$Wurzel = [System.IO.Path]::GetFullPath("$PSScriptRoot\..")
$Bundle = "$Wurzel\build\windows\x64\runner\Release"
. (Join-Path $PSScriptRoot 'windows_werkzeugort.ps1')
$Werkzeuge = Werkzeugort
$Paket = "$Wurzel\build\windows\paket\PhotoVault"

function Titel($t) { Write-Host ""; Write-Host $t; Write-Host ('-' * $t.Length) }
function Gut($t)   { Write-Host "  [ok] $t" -ForegroundColor Green }
function Schlecht($t) { Write-Host "  [!!] $t" -ForegroundColor Red; $script:Fehler++ }
$script:Fehler = 0

Titel "Voraussetzungen"
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) { Schlecht "flutter fehlt"; exit 1 }
Gut "flutter"
if (WerkzeugeUmziehen $Wurzel $Werkzeuge) {
  Gut "Werkzeuge aus build\windows\werkzeuge herausgeholt (siehe windows_werkzeugort.ps1)"
}
if (-not (Test-Path "$Werkzeuge\heif-dec.exe")) {
  Schlecht "Werkzeuge fehlen unter $Werkzeuge - erst tool\windows_werkzeuge.ps1 laufen lassen"
  exit 1
}
Gut "Werkzeuge liegen bereit: $Werkzeuge"

Titel "Flutter-Bundle bauen"
Push-Location $Wurzel
$rc = Fremd 'flutter' @('build', 'windows', '--release')
Pop-Location
if ($rc -ne 0) { Schlecht "flutter build fehlgeschlagen"; exit 1 }
if (-not (Test-Path "$Bundle\photo_vault.exe")) { Schlecht "keine photo_vault.exe"; exit 1 }
Gut "photo_vault.exe"

Titel "Paket zusammenstellen"
Remove-Item -Recurse -Force $Paket -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $Paket | Out-Null
Copy-Item "$Bundle\*" $Paket -Recurse -Force
# Die Werkzeuge in einen Unterordner "tools". Genau dort sucht
# DesktopImageTools zuerst, noch vor dem PATH - siehe suchpfade() dort.
Copy-Item $Werkzeuge "$Paket\tools" -Recurse -Force

# Die Visual-C++-Laufzeit gehoert INS Paket. Auf einem frischen Windows
# fehlt sie, und dann startet die App nicht mit einer eigenen Meldung,
# sondern mit einem Systemfehler "MSVCP140.dll wurde nicht gefunden" -
# noch bevor eine Zeile Dart laeuft. Auf dem Baurechner faellt das nie
# auf, weil Visual Studio sie mitbringt. In der Windows-Sandbox, also auf
# einem wirklich sauberen System, ist genau das passiert.
#
# Elf Dateien im Paket verlangen sie, darunter onnxruntime.dll - also
# saemtliche KI-Funktionen - und libraw.dll fuer RAW.
$Laufzeit = 'msvcp140.dll', 'msvcp140_1.dll', 'vcruntime140.dll', 'vcruntime140_1.dll'
# Der weitergebbare Satz von Visual Studio ist die richtige Quelle. Fehlt
# er, tun es die installierten Fassungen in System32: dieselben Dateien.
$RedistOrdner = Get-ChildItem "${env:ProgramFiles}\Microsoft Visual Studio", "${env:ProgramFiles(x86)}\Microsoft Visual Studio" `
    -Recurse -Directory -Filter 'Microsoft.VC*.CRT' -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -match '\\x64\\' } | Sort-Object FullName | Select-Object -Last 1
foreach ($dll in $Laufzeit) {
  $quelle = if ($RedistOrdner -and (Test-Path (Join-Path $RedistOrdner.FullName $dll))) {
    Join-Path $RedistOrdner.FullName $dll
  } else { "$env:SystemRoot\System32\$dll" }
  if (-not (Test-Path $quelle)) { Schlecht "$dll nicht zu finden - Paket waere unbrauchbar"; exit 1 }
  Copy-Item $quelle $Paket -Force
}
Gut ("Visual-C++-Laufzeit beigelegt ({0})" -f ($Laufzeit -join ', '))

# zlib.dll kommt aus dem ANGLE-Vorrat, den Flutter ins Release-Verzeichnis
# legt, und ist ein DEBUG-Bau: Sie verlangt vcruntime140d.dll und
# ucrtbased.dll. Beide sind nicht weitergebbar und liegen auf keinem
# Nutzerrechner - die Datei koennte dort also gar nicht geladen werden.
#
# Sie muss es auch nicht: Kein einziges PE im Paket importiert sie
# (libpng16-16.dll braucht zlib1.dll, eine andere Datei in tools\), und in
# der Windows-Sandbox - ohne jede Debug-Laufzeit - lief die App mit voller
# Oberflaeche und 94 geladenen Modulen, zlib.dll nicht darunter.
#
# Sie bleibt draussen, weil die Laufzeitpruefung unten sie sonst zu Recht
# beanstandet: Eine Debug-DLL gehoert nicht in eine Auslieferung.
Remove-Item "$Paket\zlib.dll" -Force -ErrorAction SilentlyContinue
Gut "zlib.dll entfernt (Debug-Bau aus ANGLE, von niemandem gebraucht)"

# Beilagen: Der Ordner IST das Programm, und das steht nirgends sonst.
# Ohne LIESMICH.txt bleibt offen, wo die eigenen Daten liegen und was beim
# Loeschen des Ordners passiert; ohne die .cmd taucht die App nie unter
# "Programme" auf, weil ein Ordner zum Auspacken sich nirgends eintraegt.
$Beilagen = "$Wurzel\packaging\windows"
foreach ($datei in 'LIESMICH.txt', 'Verknuepfung-anlegen.cmd') {
  if (-not (Test-Path "$Beilagen\$datei")) {
    Schlecht "$datei fehlt unter packaging\windows"
    exit 1
  }
  Copy-Item "$Beilagen\$datei" "$Paket\$datei" -Force
}
Gut "LIESMICH.txt und Verknuepfung-anlegen.cmd beigelegt"

$mb = ((Get-ChildItem $Paket -Recurse -File | Measure-Object Length -Sum).Sum / 1MB)
Gut ("{0:N0} MB unter {1}" -f $mb, $Paket)

Titel "Was die App selbst mitbringen muss"
# Das Flatpak lud ONNX Runtime einmal klaglos aus dem Bauverzeichnis; im
# Buendel fehlte sie. Auf jedem anderen Rechner waeren damit saemtliche
# KI-Funktionen ausgefallen, ohne dass es hier aufgefallen waere.
foreach ($dll in 'onnxruntime.dll', 'libmpv-2.dll', 'flutter_windows.dll') {
  if (Test-Path "$Paket\$dll") {
    Gut ("{0} ({1:N0} MB)" -f $dll, ((Get-Item "$Paket\$dll").Length / 1MB))
  } else {
    Schlecht "$dll fehlt im Paket"
  }
}

# Und die Laufzeit, auf der all das aufsitzt. Statt einer festen Liste
# wird gefragt, was die Dateien im Paket wirklich verlangen: Dann faellt
# eine neu hinzugekommene Abhaengigkeit HIER auf und nicht auf dem
# Rechner eines Nutzers - dort naemlich als Systemfehler vor dem ersten
# Fenster, ohne jeden Hinweis auf die Ursache.
$verlangt = @{}
foreach ($d in (Get-ChildItem $Paket -Recurse -File -Include *.exe, *.dll)) {
  foreach ($i in (Importe $d.FullName)) {
    if ($i -match '^(msvcp|vcruntime|concrt|vcomp|mfc)\d') {
      $k = $i.ToLower()
      if (-not $verlangt.ContainsKey($k)) { $verlangt[$k] = @() }
      $verlangt[$k] += $d.Name
    }
  }
}
foreach ($k in ($verlangt.Keys | Sort-Object)) {
  $wer = ($verlangt[$k] | Sort-Object -Unique)
  if ($k -match 'd\.dll$') {
    # Die Debug-Laufzeit darf nicht weitergegeben werden und liegt auf
    # keinem Nutzerrechner. Wer sie verlangt, ist selbst ein Debug-Bau
    # und gehoert nicht in eine Auslieferung.
    Schlecht ("{0} ist die DEBUG-Laufzeit - verlangt von: {1}" -f $k, ($wer -join ', '))
  } elseif (Test-Path (Join-Path $Paket $k)) {
    Gut ("{0} liegt bei ({1} Datei(en) brauchen sie)" -f $k, $wer.Count)
  } else {
    Schlecht ("{0} FEHLT im Paket - verlangt von: {1}" -f $k, ($wer -join ', '))
  }
}

# Der Ortungshelfer liegt NEBEN photo_vault.exe, nicht in tools\ - dort
# sucht DesktopImageTools zuerst. Geprueft wird, dass er startet und eine
# Zeile JSON ausgibt, nicht dass diese Maschine gerade eine Position hat:
# Ohne WLAN oder mit abgeschalteter Ortung ist {"fehler":...} die richtige
# Antwort, und das ist keine Frage der Paketierung.
if (Test-Path "$Paket\pv_standort.exe") {
  try {
    $ortAus = & "$Paket\pv_standort.exe" 2>&1 | Out-String
    if ($ortAus -match '^\s*\{.*\}\s*$') {
      $quelle = if ($ortAus -match '"quelle":"([^"]+)"') { $Matches[1] } else { 'kein Ort' }
      Gut ("pv_standort.exe laeuft ({0})" -f $quelle)
    } else {
      Schlecht ("pv_standort.exe: unerwartete Ausgabe: {0}" -f ($ortAus -split "`n")[0])
    }
  } catch {
    if ("$_" -match 'Anwendungssteuerungsrichtlinie|application control policy') {
      Write-Host "  [--] pv_standort.exe: Smart App Control verhindert den Test auf diesem Rechner" -ForegroundColor Yellow
    } else {
      Schlecht ("pv_standort.exe liess sich nicht pruefen: {0}" -f $_)
    }
  }
} else {
  Schlecht "pv_standort.exe fehlt im Paket (Standortknopf faellt aus)"
}

if ($Pruefen) {
  Titel "Werkzeuge - ohne den PATH dieses Rechners"
  # Der wichtigste Handgriff dieser Pruefung. Mit dem eigenen PATH faende
  # sich heif-dec.exe auch dann, wenn es im Paket fehlte: Es liegt hier
  # unter C:\msys64. Auf einer fremden Maschine gaebe es das nicht.
  $sauber = "$env:SystemRoot\System32;$env:SystemRoot"
  function ImPaket($exe, $argumente) {
    $alt = $env:PATH
    try {
      $env:PATH = $sauber
      $aus = & "$Paket\tools\$exe" @argumente 2>&1 | Out-String
      return @{ rc = $LASTEXITCODE; aus = $aus }
    } catch {
      return @{ rc = -1; aus = "$_" }
    } finally { $env:PATH = $alt }
  }

  # Vorhandensein genuegt nicht - aufrufen. Unter Linux lag einmal ein
  # libtool-Huellskript statt des Programms an der Stelle, und `which` war
  # damit zufrieden.
  foreach ($w in @(
      @{ n = 'heif-dec.exe';   a = @('--version') }
      @{ n = 'dcraw_emu.exe';  a = @() }
      # Ohne raw-identify bleiben Kamera, Objektiv und Aufnahmedatum von
      # CR3-Dateien leer - dem Format, das die uebliche EXIF-Bibliothek
      # gar nicht lesen kann. Ohne Argument gibt es seine Hilfe aus.
      @{ n = 'raw-identify.exe'; a = @() }
      @{ n = 'ffmpeg.exe';     a = @('-hide_banner', '-version') }
      @{ n = 'ffprobe.exe';    a = @('-hide_banner', '-version') })) {
    $e = ImPaket $w.n $w.a
    if ($e.aus -match 'nicht gefunden|not found|0xc000007b|kann nicht gefunden') {
      Schlecht ("{0}: {1}" -f $w.n, ($e.aus -split "`n")[0])
    } elseif ([string]::IsNullOrWhiteSpace($e.aus)) {
      # Der Umweg ueber Int64 ist noetig: Ein negativer Int laesst sich
      # nicht direkt nach UInt32 wandeln ("Wert war zu gross oder zu
      # klein"), und als NTSTATUS gelesen werden will er trotzdem.
      $roh = [uint32]([int64]$e.rc -band 0xFFFFFFFFL)
      Schlecht ("{0}: keine Ausgabe, Rueckgabewert {1} (0x{2:X8})" -f $w.n, $e.rc, $roh)
      # 0xC0E90002 ist keine Aussage ueber das Paket, sondern ueber diesen
      # Rechner: Smart App Control hat den Start unterbunden. Nachweisbar
      # im Ereignisprotokoll Microsoft-Windows-CodeIntegrity/Operational,
      # Id 3033/3077, mit der Richtlinien-Kennung
      # {0283ac0f-fff1-49ae-ada1-8a933130cad6}. Ohne diesen Hinweis sucht
      # man den Fehler im Bau, wo keiner ist - dieselben Dateien liefen in
      # der Windows-Sandbox einwandfrei.
      # Dezimal und nicht 0xC0E90002: PowerShell 5.1 liest ein Hex-Literal
      # dieser Groesse als Int32 und macht daraus -1058471934. Der
      # Vergleich mit einem UInt32 ist dann immer falsch, und der Hinweis
      # bliebe stumm - gemessen, nicht vermutet.
      if ($roh -eq 3236495362) {
        Write-Host "       ^ Das war Smart App Control auf DIESEM Rechner, nicht das Paket." -ForegroundColor Yellow
        Write-Host "         Beleg: Get-WinEvent -LogName Microsoft-Windows-CodeIntegrity/Operational" -ForegroundColor Yellow
      }
    } else {
      Gut "$($w.n) laeuft"
    }
  }

  # Das eigentliche Versprechen: Vorhandensein genuegt nicht, libheif muss
  # den Bildinhalt auch auspacken koennen. Genau daran ist unter Linux der
  # erste Versuch gescheitert - Ubuntu liefert libheif ohne HEVC-Dekoder.
  $dek = ImPaket 'heif-dec.exe' @('--list-decoders')
  if ($dek.aus -match '(?s)HEIC decoders:\s*\r?\n\s*-') {
    Gut "libheif hat einen HEVC-Dekoder"
  } else {
    Schlecht "libheif ohne HEVC-Dekoder - HEIC-Fotos blieben unsichtbar"
  }
  if ($dek.aus -match '(?s)AVIF decoders:\s*\r?\n\s*-') {
    Gut "libheif hat einen AVIF-Dekoder"
  } else {
    Schlecht "libheif ohne AVIF-Dekoder"
  }
  $ffd = ImPaket 'ffmpeg.exe' @('-hide_banner', '-decoders')
  if ($ffd.aus -match '(?m)^\s*V[.A-Z]*\s+hevc\s') {
    Gut "ffmpeg kann HEVC lesen"
  } else {
    Schlecht "ffmpeg ohne HEVC - Videovorschauen blieben leer"
  }
  # Vorschaubilder werden als JPEG geschrieben. Der Dekoder allein genuegt
  # dafuer nicht - es braucht auch den mjpeg-Kodierer. Ein H.264-Kodierer
  # dagegen fehlt der LGPL-Fassung, und das ist in Ordnung: Geschnitten
  # wird mit -c copy.
  $ffe = ImPaket 'ffmpeg.exe' @('-hide_banner', '-encoders')
  if ($ffe.aus -match '(?m)^\s*V[.A-Z]*\s+mjpeg\s') {
    Gut "ffmpeg kann JPEG schreiben (Vorschaubilder)"
  } else {
    Schlecht "ffmpeg ohne mjpeg-Kodierer - Videovorschauen blieben leer"
  }

  # Und einmal richtig: eine echte HEIC-Datei auspacken.
  $probe = "$Wurzel\test\fixtures\werkzeuge\probe.heic"
  if (Test-Path $probe) {
    $raus = Join-Path $env:TEMP 'pv_paketprobe.jpg'
    Remove-Item $raus -Force -ErrorAction SilentlyContinue
    $u = ImPaket 'heif-dec.exe' @($probe, $raus)
    if ((Test-Path $raus) -and (Get-Item $raus).Length -gt 1000) {
      Gut ("HEIC ausgepackt ({0:N0} Bytes JPEG)" -f (Get-Item $raus).Length)
    } else {
      Schlecht "HEIC liess sich nicht auspacken: $($u.aus)"
    }
  }
}

if ($Zip) {
  Titel "Einpacken"
  # Nicht $zip: PowerShell unterscheidet keine Gross- und Kleinschreibung,
  # die Zuweisung landete sonst im Schalter $Zip - und der Versuch, eine
  # Zeichenkette in einen Schalter zu schreiben, brach das Skript ab.
  # Mit Versionsnummer und auf dem Schreibtisch - genau dort und unter
  # genau diesem Namen sucht tool/auslieferung_einsammeln.sh danach.
  # Ohne das blieb ein Handgriff dazwischen, und beim Einsammeln von
  # 3.3.1 hat genau er gefehlt.
  $vZeile = Select-String -Path "$Wurzel\pubspec.yaml" -Pattern '^version:\s*([0-9]+\.[0-9]+\.[0-9]+)'
  if (-not $vZeile) { Schlecht "Version nicht aus pubspec.yaml zu lesen"; exit 1 }
  $v = $vZeile.Matches[0].Groups[1].Value
  $zipDatei = "$Wurzel\build\windows\PhotoVault-$v-windows-x64.zip"
  Remove-Item $zipDatei -Force -ErrorAction SilentlyContinue
  # Nicht Compress-Archive: Das scheiterte hier still an den langen Pfaden
  # unter data\flutter_assets - das Skript endete mitten im Abschnitt, mit
  # Rueckgabewert 0 und ohne Datei. ZipFile kommt damit zurecht.
  try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::CreateFromDirectory(
      $Paket, $zipDatei,
      [System.IO.Compression.CompressionLevel]::Optimal,
      $true)   # $true: den Ordner PhotoVault mit einpacken, nicht nur seinen Inhalt
    Gut ("{0:N0} MB  {1}" -f ((Get-Item $zipDatei).Length / 1MB), $zipDatei)
    $aufDenTisch = Join-Path ([Environment]::GetFolderPath('Desktop')) (Split-Path $zipDatei -Leaf)
    Copy-Item $zipDatei $aufDenTisch -Force
    Gut "auf den Schreibtisch gelegt: $aufDenTisch"
  } catch {
    Schlecht "Einpacken fehlgeschlagen: $($_.Exception.Message)"
  }
}

Write-Host ""
if ($script:Fehler -gt 0) { Write-Host "$($script:Fehler) Beanstandungen" -ForegroundColor Red; exit 1 }
