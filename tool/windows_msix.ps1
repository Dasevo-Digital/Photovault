# Packt das fertige Windows-Verzeichnis als MSIX.
#
#   tool\windows_msix.ps1 [-Quelle <Ordner>] -Selbstsigniert
#   tool\windows_msix.ps1 [-Quelle <Ordner>] -Pfx <Datei> -PfxPasswort <pw>
#   tool\windows_msix.ps1 [-Quelle <Ordner>] -Store -IdentitaetsName <Name> -HerausgeberId <CN=...>
#                          [-HerausgeberAnzeige <Name>]
#
#     -Quelle          Der Paketordner. Vorgabe: build\windows\paket\PhotoVault,
#                      also genau das, was windows_bauen.ps1 hinterlaesst.
#     -Selbstsigniert  Erzeugt ein Wegwerf-Zertifikat und signiert damit.
#                      NUR fuer den Probelauf: Ein selbstsigniertes Paket
#                      laesst sich nur auf einem Rechner installieren, der
#                      das Zertifikat vorher aufgenommen hat.
#     -Pfx             Das echte Zertifikat, wenn es eines gibt.
#     -Store           Fuer die Einreichung im Microsoft Store. Dann wird
#                      NICHT signiert - Microsoft signiert beim Einreichen
#                      neu, und daher kommt der Ruf. Identitaetsname und
#                      Herausgeber-CN stehen im Partner Center unter
#                      "Produktidentitaet" und muessen zeichengenau passen.
#
# Warum ueberhaupt MSIX, wo windows_bauen.ps1 bewusst darauf verzichtet
# hat: Smart App Control blockiert das ausgepackte Verzeichnis, und zwar
# photo_vault.exe selbst, nicht nur die Werkzeuge. Aus dem Microsoft Store
# bezogene Pakete umgeht Smart App Control dagegen vollstaendig - sie
# werden von Microsoft neu signiert. Der Store nimmt aber nur MSIX.
#
# Der Publisher im Manifest muss ZEICHENGENAU dem Subject des Zertifikats
# entsprechen, sonst verweigert die Installation die Annahme. Deshalb wird
# er hier aus dem Zertifikat gelesen und nicht danebengeschrieben.
[CmdletBinding()]
param(
  [string]$Quelle,
  [switch]$Selbstsigniert,
  [string]$Pfx,
  [string]$PfxPasswort,
  [string]$Version,
  [switch]$Store,
  [string]$IdentitaetsName,
  [string]$HerausgeberId,
  [string]$HerausgeberAnzeige
)

$ErrorActionPreference = 'Stop'

# PowerShell 5.1 macht unter ErrorActionPreference=Stop aus jeder Zeile,
# die ein fremdes Programm nach stderr schreibt, einen abbrechenden
# Fehler - auch aus einer blossen Warnung. signtool tut genau das, wenn
# die Kette bei einem unbekannten Stamm endet, und das ist bei einem
# selbstsignierten Paket der Normalfall, kein Fehler.
function Fremd {
  param([string]$Programm, [string[]]$Argumente, [switch]$Still)
  $alt = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $aus = & $Programm @Argumente 2>&1 | Out-String
    if (-not $Still) { $aus -split "`r?`n" | Where-Object { $_ } | ForEach-Object { Write-Host "  $_" } }
    return $aus
  } finally { $ErrorActionPreference = $alt }
}

$Wurzel = [System.IO.Path]::GetFullPath("$PSScriptRoot\..")
if (-not $Quelle) { $Quelle = "$Wurzel\build\windows\paket\PhotoVault" }
$Arbeit = "$Wurzel\build\windows\msix"
$Buehne = "$Arbeit\stage"

function Titel($t) { Write-Host ""; Write-Host $t; Write-Host ('-' * $t.Length) }
function Gut($t)   { Write-Host "  [ok] $t" -ForegroundColor Green }
function Schlecht($t) { Write-Host "  [!!] $t" -ForegroundColor Red; $script:Fehler++ }
$script:Fehler = 0

Titel "Voraussetzungen"
if (-not (Test-Path "$Quelle\photo_vault.exe")) {
  Schlecht "Kein Paketordner unter $Quelle - erst tool\windows_bauen.ps1 laufen lassen"
  exit 1
}
Gut "Quelle: $Quelle"

# Das neueste Windows Kit gewinnt. Ohne Sortierung nimmt Get-ChildItem
# irgendeines, und die aelteren makeappx kennen manche Manifest-Felder nicht.
$kit = 'C:\Program Files (x86)\Windows Kits\10\bin'
$makeappx = Get-ChildItem $kit -Recurse -Filter makeappx.exe -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -match '\\x64\\' } |
  Sort-Object { [version]($_.Directory.Parent.Name) } | Select-Object -Last 1
$signtool = Get-ChildItem $kit -Recurse -Filter signtool.exe -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -match '\\x64\\' } |
  Sort-Object { [version]($_.Directory.Parent.Name) } | Select-Object -Last 1
if (-not $makeappx) { Schlecht "makeappx.exe nicht gefunden - Windows SDK fehlt"; exit 1 }
Gut "makeappx: $($makeappx.FullName)"
Gut "signtool: $($signtool.FullName)"

# Die Version steht in der pubspec und nirgends sonst; ein MSIX braucht
# vier Stellen, und die letzte muss fuer den Store 0 sein.
if (-not $Version) {
  $zeile = Select-String -Path "$Wurzel\pubspec.yaml" -Pattern '^version:\s*([0-9]+\.[0-9]+\.[0-9]+)'
  if (-not $zeile) { Schlecht "Version nicht aus pubspec.yaml zu lesen"; exit 1 }
  $Version = $zeile.Matches[0].Groups[1].Value
}
$MsixVersion = "$Version.0"
Gut "Version $MsixVersion"

Titel "Zertifikat"
if ($Selbstsigniert) {
  $subject = 'CN=Photo Vault Probelauf, O=Photo Vault, C=DE'
  $vorhanden = Get-ChildItem Cert:\CurrentUser\My |
    Where-Object { $_.Subject -eq $subject -and $_.NotAfter -gt (Get-Date) } |
    Select-Object -First 1
  if ($vorhanden) {
    $zert = $vorhanden
    Gut "vorhandenes Wegwerf-Zertifikat wiederverwendet"
  } else {
    $zert = New-SelfSignedCertificate -Type Custom -Subject $subject `
      -KeyUsage DigitalSignature -FriendlyName 'Photo Vault Probelauf' `
      -CertStoreLocation 'Cert:\CurrentUser\My' `
      -TextExtension @('2.5.29.37={text}1.3.6.1.5.5.7.3.3')
    Gut "Wegwerf-Zertifikat erzeugt"
  }
  New-Item -ItemType Directory -Force $Arbeit | Out-Null
  $Pfx = "$Arbeit\probelauf.pfx"
  $PfxPasswort = 'probelauf'
  $pw = ConvertTo-SecureString -String $PfxPasswort -Force -AsPlainText
  Export-PfxCertificate -Cert $zert -FilePath $Pfx -Password $pw | Out-Null
  # Der oeffentliche Teil allein - den muss der Zielrechner aufnehmen,
  # nicht die .pfx mit dem privaten Schluessel.
  Export-Certificate -Cert $zert -FilePath "$Arbeit\probelauf.cer" | Out-Null
  Gut "probelauf.pfx und probelauf.cer unter $Arbeit"
  $Publisher = $zert.Subject
} elseif ($Pfx) {
  $pw = ConvertTo-SecureString -String $PfxPasswort -Force -AsPlainText
  $zert = Get-PfxData -FilePath $Pfx -Password $pw
  $Publisher = $zert.EndEntityCertificates[0].Subject
  Gut "Zertifikat aus $Pfx"
} elseif ($Store) {
  # Fuer den Store wird NICHT selbst signiert: Microsoft signiert das
  # Paket beim Einreichen neu, und genau daher kommt der Ruf, der Smart
  # App Control zufriedenstellt. Identitaet und Herausgeber muessen dann
  # aber zeichengenau denen aus dem Partner Center entsprechen - sie
  # stehen dort unter "Produktidentitaet".
  if (-not $IdentitaetsName -or -not $HerausgeberId) {
    Schlecht "-Store braucht -IdentitaetsName und -HerausgeberId aus dem Partner Center"
    exit 1
  }
  $Publisher = $HerausgeberId
} else {
  Schlecht "Weder -Selbstsigniert noch -Pfx noch -Store angegeben"
  exit 1
}
Gut "Publisher: $Publisher"

Titel "Buehne aufbauen"
Remove-Item -Recurse -Force $Buehne -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $Buehne | Out-Null
Copy-Item "$Quelle\*" $Buehne -Recurse -Force
# Die Beilagen des ausgepackten Ordners ergeben im Paket keinen Sinn: Die
# .cmd legt eine Verknuepfung an, das erledigt jetzt Windows selbst, und
# der Installationsordner ist ohnehin schreibgeschuetzt.
Remove-Item "$Buehne\Verknuepfung-anlegen.cmd" -Force -ErrorAction SilentlyContinue
Copy-Item "$Wurzel\packaging\msix\assets" "$Buehne\Assets" -Recurse -Force
Gut "Inhalt und Grafiken auf der Buehne"

# Ohne Store-Angaben bleibt es bei den Namen des Probelaufs.
$Identitaet = if ($IdentitaetsName) { $IdentitaetsName } else { 'PhotoVault.PhotoVault' }
$Anzeige    = if ($HerausgeberAnzeige) { $HerausgeberAnzeige } else { 'Photo Vault' }
Gut "Identitaet: $Identitaet"

$manifest = @"
<?xml version="1.0" encoding="utf-8"?>
<Package
  xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10"
  xmlns:uap="http://schemas.microsoft.com/appx/manifest/uap/windows10"
  xmlns:rescap="http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities"
  IgnorableNamespaces="uap rescap">

  <Identity Name="$Identitaet"
            Publisher="$Publisher"
            Version="$MsixVersion"
            ProcessorArchitecture="x64" />

  <Properties>
    <DisplayName>Photo Vault</DisplayName>
    <PublisherDisplayName>$Anzeige</PublisherDisplayName>
    <Logo>Assets\StoreLogo.png</Logo>
  </Properties>

  <Dependencies>
    <TargetDeviceFamily Name="Windows.Desktop" MinVersion="10.0.17763.0" MaxVersionTested="10.0.26100.0" />
  </Dependencies>

  <Resources>
    <Resource Language="de-DE" />
    <Resource Language="en-US" />
  </Resources>

  <Applications>
    <Application Id="PhotoVault" Executable="photo_vault.exe" EntryPoint="Windows.FullTrustApplication">
      <uap:VisualElements
        DisplayName="Photo Vault"
        Description="Fotoverwaltung mit Gesichtern, Orten und Suche - alles auf dem eigenen Rechner."
        BackgroundColor="transparent"
        Square150x150Logo="Assets\Square150x150Logo.png"
        Square44x44Logo="Assets\Square44x44Logo.png">
        <uap:DefaultTile
          Wide310x150Logo="Assets\Wide310x150Logo.png"
          Square71x71Logo="Assets\Square71x71Logo.png"
          Square310x310Logo="Assets\Square310x310Logo.png" />
      </uap:VisualElements>
    </Application>
  </Applications>

  <Capabilities>
    <!-- Ein verpacktes Win32-Programm laeuft mit dem vollen Token des
         Nutzers. Genau das braucht die App: Der Bibliotheksordner liegt,
         wo der Nutzer ihn hinlegt, und die Werkzeuge sind Kindprozesse.
         broadFileSystemAccess waere hier NICHT noetig - das gilt nur fuer
         Apps ohne runFullTrust. -->
    <rescap:Capability Name="runFullTrust" />
  </Capabilities>
</Package>
"@
# Ohne Stueckliste am Anfang: makeappx liest die Datei sonst als UTF-16
# und meldet einen Syntaxfehler in Zeile 1.
[System.IO.File]::WriteAllText("$Buehne\AppxManifest.xml", $manifest,
  (New-Object System.Text.UTF8Encoding($false)))
Gut "AppxManifest.xml geschrieben"

Titel "Packen"
$msix = "$Arbeit\PhotoVault-$Version-x64.msix"
Remove-Item $msix -Force -ErrorAction SilentlyContinue
# Ohne /v nennt makeappx jede einzelne Datei - bei 1300 Dateien ist die
# eigentliche Meldung danach nicht mehr zu finden.
$packAus = Fremd $makeappx.FullName @('pack', '/d', $Buehne, '/p', $msix, '/o') -Still
if ($packAus -notmatch 'succeeded') { Write-Host $packAus }
if (-not (Test-Path $msix)) { Schlecht "makeappx hat nichts erzeugt"; exit 1 }
Gut ("{0:N0} MB" -f ((Get-Item $msix).Length / 1MB))

if ($Store) {
  Titel "Nicht signieren"
  Write-Host "  Fuer den Store bleibt das Paket unsigniert - Microsoft signiert es"
  Write-Host "  beim Einreichen neu. Eine eigene Signatur wuerde dabei verworfen."
  Titel "Ergebnis"
  Write-Host "  $msix"
  Write-Host ""
  Write-Host "  Im Partner Center unter 'Pakete' hochladen."
  if ($script:Fehler -gt 0) { Write-Host ""; Schlecht "$($script:Fehler) Fehler"; exit 1 }
  exit 0
}

Titel "Signieren"
$signAus = Fremd $signtool.FullName @('sign', '/fd', 'SHA256', '/a', '/f', $Pfx, '/p', $PfxPasswort, $msix) -Still
if ($signAus -notmatch 'Successfully signed') { Write-Host $signAus; Schlecht 'Signieren fehlgeschlagen'; exit 1 }
Gut "signiert"
$pruef = Fremd $signtool.FullName @('verify', '/pa', $msix) -Still
if ($pruef -match 'Successfully verified') {
  Gut "Signatur gilt auf diesem Rechner"
} else {
  # Bei einem selbstsignierten Zertifikat ist das erwartet, solange der
  # oeffentliche Teil nicht im Stammspeicher liegt. Kein Abbruch.
  Write-Host "  [--] noch nicht vertrauenswuerdig (bei -Selbstsigniert normal)" -ForegroundColor Yellow
}

Titel "Ergebnis"
Write-Host "  $msix"
if ($Selbstsigniert) {
  Write-Host ""
  Write-Host "  Zum Einspielen auf einem Probe-Rechner (NICHT auf dem eigenen):"
  Write-Host "    Import-Certificate -FilePath probelauf.cer -CertStoreLocation Cert:\LocalMachine\Root"
  Write-Host "    Add-AppxPackage -Path PhotoVault-$Version-x64.msix"
}
if ($script:Fehler -gt 0) { Write-Host ""; Schlecht "$($script:Fehler) Fehler"; exit 1 }
