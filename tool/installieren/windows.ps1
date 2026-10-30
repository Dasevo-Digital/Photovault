[CmdletBinding(DefaultParameterSetName='Base64')]
param(
  [Parameter(Mandatory=$true)][ValidateSet('vorpruefen','vorbereiten','tauschen','nachpruefen','zuruecksetzen','aufraeumen','abschliessen')][string]$Phase,
  [Parameter(Mandatory=$true,ParameterSetName='Base64')][string]$PlanBase64,
  [Parameter(Mandatory=$true,ParameterSetName='Datei')][string]$PlanDatei
)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=New-Object Text.UTF8Encoding
$text=if($PSCmdlet.ParameterSetName -eq 'Datei'){
  Get-Content -LiteralPath $PlanDatei -Raw -Encoding UTF8
}else{
  [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($PlanBase64))
}
$plan=ConvertFrom-Json $text
function Set-Wert($name,$wert) { $plan|Add-Member -NotePropertyName $name -NotePropertyValue $wert -Force }
function Test-Geschlossen {
  $exe=Join-Path $plan.ziel 'photo_vault.exe'
  foreach($p in @(Get-Process photo_vault -ErrorAction SilentlyContinue)) {
    if($p.Path -eq $exe){throw 'Die installierte App muss zuerst geordnet beendet werden.'}
  }
}
function Test-Version($ordner,$erwartet) {
  $exe=Join-Path $ordner 'photo_vault.exe'
  if(-not(Test-Path -LiteralPath $exe) -or (Get-Item -LiteralPath $exe).VersionInfo.ProductVersion -ne $erwartet){throw 'Der Programmstand stimmt nicht.'}
}
function Test-Paket {
  if(-not(Test-Path -LiteralPath $plan.quelle -PathType Leaf)){throw 'Das Installationspaket fehlt.'}
  $manifest=Join-Path ([IO.Path]::GetDirectoryName($plan.quelle)) 'SHA256SUMS.txt'
  if(-not(Test-Path -LiteralPath $manifest)){throw 'Die Pruefsummenliste fehlt.'}
  $name=[IO.Path]::GetFileName($plan.quelle)
  $zeilen=@([IO.File]::ReadAllLines($manifest)|Where-Object {$_ -match ('^[a-f0-9]{64}\s+\*?'+[regex]::Escape($name)+'$')})
  if($zeilen.Count -ne 1){throw 'Kein eindeutiger Paketnachweis.'}
  $hash=$zeilen[0].Substring(0,64)
  if((Get-FileHash -LiteralPath $plan.quelle -Algorithm SHA256).Hash.ToLower() -ne $hash){throw 'Die Paketpruefsumme stimmt nicht.'}
  if($plan.paketHash -and $plan.paketHash -ne $hash){throw 'Das Paket hat sich geaendert.'}
  Set-Wert 'paketHash' $hash
}
function Remove-Stage {
  if($plan.stage -and (Test-Path -LiteralPath $plan.stage)){Remove-Item -LiteralPath $plan.stage -Recurse -Force}
}
try {
  switch($Phase) {
    'vorpruefen' {
      if($plan.version -notmatch '^\d+\.\d+\.\d+(?:[-+][A-Za-z0-9.-]+)?$' -or $plan.kennung -notmatch '^[a-f0-9]{32}$'){throw 'Ungueltiger Installationsplan.'}
      $desk=if($plan.desktop){[string]$plan.desktop}else{[Environment]::GetFolderPath('Desktop')}
      Set-Wert 'ziel' (Join-Path $desk 'PhotoVault')
      $name='PhotoVault-'+$plan.version+'-windows-x64.zip'
      $quelle=Join-Path $desk ('PhotoVault-Release-v'+$plan.version+'-Upload\'+$name)
      if(-not(Test-Path -LiteralPath $quelle)){$quelle=Join-Path $desk $name}
      Set-Wert 'quelle' $quelle
      Test-Paket
      Test-Geschlossen
      if(@(Get-ChildItem -LiteralPath $plan.ziel -Filter library.sqlite -Recurse -File).Count -gt 0){throw 'Bibliotheksdaten im Programmordner: Austausch abgebrochen.'}
      $alt=(Get-Item -LiteralPath (Join-Path $plan.ziel 'photo_vault.exe')).VersionInfo.ProductVersion
      if($alt -notmatch '^\d+\.\d+\.\d+(?:[-+][A-Za-z0-9.-]+)?$'){throw 'Der vorherige Versionsstand ist nicht lesbar.'}
      Set-Wert 'altVersion' $alt
      Set-Wert 'altHash' ((Get-FileHash -LiteralPath (Join-Path $plan.ziel 'photo_vault.exe')).Hash)
      Set-Wert 'stage' (Join-Path $desk ('.PhotoVault-'+$plan.kennung))
      Set-Wert 'alt' (Join-Path $desk ('PhotoVault-Vorversionen\PhotoVault-'+$alt+'-vor-'+$plan.version+'-'+$plan.kennung))
      Set-Wert 'fehlerziel' (Join-Path $desk ('.PhotoVault-'+$plan.kennung+'-fehler'))
      foreach($p in @($plan.stage,$plan.alt,$plan.fehlerziel)){if(Test-Path -LiteralPath $p){throw 'Ein Austauschpfad ist bereits belegt.'}}
    }
    'vorbereiten' {
      Test-Paket
      Expand-Archive -LiteralPath $plan.quelle -DestinationPath $plan.stage
      $neu=Join-Path $plan.stage 'PhotoVault'
      Test-Version $neu $plan.version
      $hashes=@{}
      foreach($f in @(Get-ChildItem -LiteralPath $neu -Recurse -File)){
        $hashes[$f.FullName.Substring($neu.Length+1)]=(Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash
      }
      Set-Wert 'dateien' $hashes
    }
    'tauschen' {
      Test-Geschlossen
      New-Item -ItemType Directory -Force ([IO.Path]::GetDirectoryName($plan.alt))|Out-Null
      Move-Item -LiteralPath $plan.ziel -Destination $plan.alt
      Move-Item -LiteralPath (Join-Path $plan.stage 'PhotoVault') -Destination $plan.ziel
    }
    'nachpruefen' {
      Test-Version $plan.ziel $plan.version
      $eigenschaften=@($plan.dateien.PSObject.Properties)
      if(@(Get-ChildItem -LiteralPath $plan.ziel -Recurse -File).Count -ne $eigenschaften.Count){throw 'Die installierte Dateimenge stimmt nicht.'}
      foreach($f in $eigenschaften){
        $p=Join-Path $plan.ziel $f.Name
        if(-not(Test-Path -LiteralPath $p) -or (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash -ne $f.Value){throw 'Eine installierte Datei stimmt nicht.'}
      }
    }
    'zuruecksetzen' {
      if(Test-Path -LiteralPath $plan.alt){
        if(Test-Path -LiteralPath $plan.ziel){Move-Item -LiteralPath $plan.ziel -Destination $plan.fehlerziel}
        Move-Item -LiteralPath $plan.alt -Destination $plan.ziel
        Test-Version $plan.ziel $plan.altVersion
        if((Get-FileHash -LiteralPath (Join-Path $plan.ziel 'photo_vault.exe')).Hash -ne $plan.altHash){throw 'Der Rueckfall konnte nicht verifiziert werden.'}
      }
    }
    'aufraeumen' {
      Remove-Stage
      if($plan.fehlerziel -and (Test-Path -LiteralPath $plan.fehlerziel)){Remove-Item -LiteralPath $plan.fehlerziel -Recurse -Force}
    }
    'abschliessen' { Remove-Stage }
  }
  'PV_RESULT '+($plan|ConvertTo-Json -Depth 6 -Compress)
  exit 0
} catch {
  [Console]::Error.WriteLine('PV_ERROR '+[string]$_)
  exit 1
}
