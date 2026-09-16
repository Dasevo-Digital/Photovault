# Wo die mitgelieferten Kommandozeilenwerkzeuge liegen.
#
# Von zwei Skripten gebraucht: windows_werkzeuge.ps1 legt sie an,
# windows_bauen.ps1 packt sie ein. Deshalb steht der Ort hier und nicht
# zweimal - zwei Kopien laufen frueher oder spaeter auseinander.
#
# NICHT unter build\. Dort lagen sie bis zum 10.09.2026, und `flutter
# clean` loescht build\ vollstaendig: 139,6 MB in 22 Dateien, darunter das
# selbst gebaute libheif. Das waeren Stunden Arbeit fuer einen Befehl, den
# man aus Gewohnheit tippt. Dass es nie passiert ist, heisst nur, dass
# niemand aufgeraeumt hat.
#
# LOCALAPPDATA statt eines Ordners neben dem Baum: Damit ueberlebt der
# Bestand auch ein neues Klonen des Projekts.

function Werkzeugort {
  if ($env:PV_WERKZEUGE) { return [System.IO.Path]::GetFullPath($env:PV_WERKZEUGE) }
  return [System.IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'PhotoVault\werkzeuge'))
}

# Holt einen Bestand vom alten Ort herueber - einmalig, ohne Rueckfrage.
# Wer aus einem aelteren Stand kommt, soll libheif nicht neu bauen
# muessen. Gibt zurueck, ob umgezogen wurde.
function WerkzeugeUmziehen([string]$Wurzel, [string]$Ziel) {
  $alt = Join-Path $Wurzel 'build\windows\werkzeuge'
  if ((Test-Path (Join-Path $alt 'heif-dec.exe')) -and
      -not (Test-Path (Join-Path $Ziel 'heif-dec.exe'))) {
    New-Item -ItemType Directory -Force (Split-Path $Ziel) | Out-Null
    Move-Item $alt $Ziel -Force
    return $true
  }
  return $false
}
