param(
  [string]$SourceDirectory = 'C:\Users\BrunoTremblay\Work\VPRO_ACCESS\VPro64'
)

$ErrorActionPreference = 'Stop'
$source = Join-Path $SourceDirectory 'VPro64.accdb'
$before = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
$root = Join-Path $env:LOCALAPPDATA ('Temp\vpro-short-veg-layer-strata-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root -ErrorAction Stop | Out-Null
Copy-Item -Path (Join-Path $SourceDirectory '*') -Destination $root -Recurse -Force -ErrorAction Stop
$frontEnd = Join-Path $root 'VPro64.accdb'
$copyHash = (Get-FileHash -LiteralPath $frontEnd -Algorithm SHA256).Hash
if ($before -ne $copyHash) { throw 'Disposable front-end copy hash mismatch' }

$result = [ordered]@{
  Method = 'Hidden Access DAO on full-directory disposable copy; scratch SELECT DISTINCTROW / INSERT / UPDATE stages reconstructed from ConvertProVeg2V2 and BuildStrataTable; not VBA function or full report invocation'
  Limitations = @('No CurrPlotlist/CurrProject, DoCmd.CopyObject, report aggregation, or lumping invocation', 'Consolidation is First per plot/species; this fixture has one source row per key', 'Actual LayerCode queried read-only; linked mapping, if present, is not modified')
  OracleRoot = $root; SourceHashBefore = $before; InitialCopyHash = $copyHash
  Fixture = @('N: all null', 'Z: Cover1/5a/6/7 = 0', 'P: Cover1=10, Cover2=20, Cover5a/b/c=5/6/7, Cover6=2, Cover7=3', 'CAP: Cover1/2=60/50, Cover4/5/5a=50/40/20', 'AUTH: Cover1/2=60/50, TotalA=120, Cover4/5=60/50, TotalB=0', 'AUTHB: Cover1=10, TotalA=0, Cover4/5=60/50, TotalB=123')
  LayerCode = @(); Converted = @(); Strata = @(); Joins = @(); Checks = @()
}
$access = $null
$db = $null
function Exec([string]$sql) { $db.Execute($sql, 128) }
function ReadRows([string]$sql, [string[]]$names) {
  $rows = @()
  $rs = $db.OpenRecordset($sql, 4)
  try {
    while (-not $rs.EOF) {
      $row = [ordered]@{}
      foreach ($name in $names) {
        $v = $rs.Fields($name).Value
        $row[$name] = if ($null -eq $v -or $v -is [DBNull]) { $null } else { $v }
      }
      $rows += [pscustomobject]$row
      $rs.MoveNext()
    }
  } finally { $rs.Close() }
  return $rows
}
function Check([string]$name, [bool]$ok) {
  $result.Checks += [pscustomobject]@{ Name = $name; Pass = $ok }
}
try {
  $access = New-Object -ComObject Access.Application
  $access.Visible = $false
  $access.AutomationSecurity = 1
  $access.OpenCurrentDatabase($frontEnd, $false)
  Start-Sleep -Seconds 2
  foreach ($form in @($access.CurrentProject.AllForms | Where-Object { $_.IsLoaded } | ForEach-Object { $_.Name })) {
    try { $access.DoCmd.Close(2, $form, 2) } catch {}
  }
  $db = $access.CurrentDb()
  # The mapping is the copied database's actual LayerCode, not a hand-written surrogate.
  $result.LayerCode = @(ReadRows 'SELECT LayerCode, Layer1234567, LayerText, Strata FROM LayerCode WHERE LayerText Is Not Null ORDER BY LayerText' @('LayerCode','Layer1234567','LayerText','Strata'))
  $layers = @($result.LayerCode | ForEach-Object { [string]$_.LayerText })
  foreach ($layer in $layers) {
    if ($layer -notmatch '^[0-9]+[a-cA-C]?$') { throw "Unexpected LayerText $layer" }
  }
  $columns = @($layers | ForEach-Object { '[Cover' + $_ + '] DOUBLE' })
  Exec ('CREATE TABLE zOracleLSWide (PlotNumber TEXT(20), Species TEXT(20), TotalA DOUBLE, TotalB DOUBLE, ' + ($columns -join ', ') + ')')
  Exec 'CREATE TABLE zOracleLSConverted (PlotNumber TEXT(20), Species TEXT(20), Cover DOUBLE, Layer TEXT(3), ProjectID TEXT(20))'
  Exec 'CREATE TABLE zOracleLSConsolidate (PlotNumber TEXT(20), Species TEXT(20), C1 DOUBLE, C2 DOUBLE, C3 DOUBLE, C4 DOUBLE, C5 DOUBLE, C5a DOUBLE, C5b DOUBLE, C5c DOUBLE, C6 DOUBLE, C7 DOUBLE, TA DOUBLE, TB DOUBLE)'
  Exec 'CREATE TABLE zOracleLSStrata (PlotNumber TEXT(20), Layer TEXT(3), Species TEXT(20), Cover DOUBLE)'
  # Only disposable scratch tables are written. Separate keys make First deterministic.
  foreach ($key in @('N','Z','P','CAP','AUTH','AUTHB')) { Exec "INSERT INTO zOracleLSWide (PlotNumber, Species) VALUES ('$key', 'SP')" }
  Exec "UPDATE zOracleLSWide SET Cover1=0, Cover5a=0, Cover6=0, Cover7=0 WHERE PlotNumber='Z'"
  Exec "UPDATE zOracleLSWide SET Cover1=10, Cover2=20, Cover5a=5, Cover5b=6, Cover5c=7, Cover6=2, Cover7=3 WHERE PlotNumber='P'"
  Exec "UPDATE zOracleLSWide SET Cover1=60, Cover2=50, Cover4=50, Cover5=40, Cover5a=20 WHERE PlotNumber='CAP'"
  Exec "UPDATE zOracleLSWide SET Cover1=60, Cover2=50, TotalA=120, Cover4=60, Cover5=50, TotalB=0 WHERE PlotNumber='AUTH'"
  Exec "UPDATE zOracleLSWide SET Cover1=10, TotalA=0, Cover4=60, Cover5=50, TotalB=123 WHERE PlotNumber='AUTHB'"

  # ConvertProVeg2V2: one INSERT DISTINCTROW and one null-Layer UPDATE per actual LayerText.
  foreach ($layer in $layers) {
    Exec "INSERT INTO zOracleLSConverted (PlotNumber, Species, Cover) SELECT DISTINCTROW PlotNumber, Species, [Cover$layer] FROM zOracleLSWide WHERE [Cover$layer] Is Not Null"
    Exec "UPDATE DISTINCTROW zOracleLSConverted SET ProjectID='ORACLE', Layer='$layer' WHERE Layer Is Null"
  }
  $result.Converted = @(ReadRows 'SELECT PlotNumber, Layer, Cover, ProjectID FROM zOracleLSConverted ORDER BY PlotNumber, Layer' @('PlotNumber','Layer','Cover','ProjectID'))

  # BuildStrataTable: TempVegConsolidate First() group and the four original predicates.
  $firsts = @('Cover1','Cover2','Cover3','Cover4','Cover5','Cover5a','Cover5b','Cover5c','Cover6','Cover7','TotalA','TotalB')
  $aliases = @('C1','C2','C3','C4','C5','C5a','C5b','C5c','C6','C7','TA','TB')
  $parts = for ($i=0; $i -lt $firsts.Count; $i++) { 'First([' + $firsts[$i] + ']) AS [' + $aliases[$i] + ']' }
  Exec ('INSERT INTO zOracleLSConsolidate (PlotNumber, Species, ' + ($aliases -join ',') + ') SELECT PlotNumber, Species, ' + ($parts -join ', ') + ' FROM zOracleLSWide GROUP BY PlotNumber, Species')
  $a = 'Val(IIf(IsNull([TA]),IIf((Nz([C1])+Nz([C2])+Nz([C3]))>99,99,(Nz([C1])+Nz([C2])+Nz([C3]))),[TA]))'
  $b = 'Val(IIf(IsNull([TB]),IIf((Nz([C4])+Nz([C5])+Nz([C5a])+Nz([C5b])+Nz([C5c]))>99,99,(Nz([C4])+Nz([C5])+Nz([C5a])+Nz([C5b])+Nz([C5c]))),[TB]))'
  Exec "INSERT INTO zOracleLSStrata (PlotNumber, Layer, Species, Cover) SELECT DISTINCTROW PlotNumber, '1', Species, $a FROM zOracleLSConsolidate WHERE $a>0"
  Exec "INSERT INTO zOracleLSStrata (PlotNumber, Layer, Species, Cover) SELECT DISTINCTROW PlotNumber, '4', Species, $b FROM zOracleLSConsolidate WHERE $b>0"
  foreach ($n in @(6,7)) {
    Exec "INSERT INTO zOracleLSStrata (PlotNumber, Layer, Species, Cover) SELECT DISTINCTROW PlotNumber, '$n', Species, C$n FROM zOracleLSConsolidate WHERE C$n Is Not Null"
  }
  $result.Strata = @(ReadRows 'SELECT PlotNumber, Layer, Cover FROM zOracleLSStrata ORDER BY PlotNumber, Layer' @('PlotNumber','Layer','Cover'))
  # Short-veg report uses Layer1234567 except the lifeform branch, which uses LayerCode.
  foreach ($stage in @('zOracleLSConverted','zOracleLSStrata')) {
    foreach ($branch in @('layer_strata','lifeform')) {
      $key = if ($branch -eq 'lifeform') { 'LayerCode' } else { 'Layer1234567' }
      $join = "SELECT v.PlotNumber, v.Layer, v.Cover, m.LayerCode AS MatchedCode, m.Strata AS MatchedStrata FROM $stage AS v LEFT JOIN LayerCode AS m ON v.Layer = m.$key ORDER BY v.PlotNumber, v.Layer"
      foreach ($r in @(ReadRows $join @('PlotNumber','Layer','Cover','MatchedCode','MatchedStrata'))) {
        $result.Joins += [pscustomobject]@{ Stage = $stage; Branch = $branch; PlotNumber = $r.PlotNumber; Layer = $r.Layer; Cover = $r.Cover; MatchedCode = $r.MatchedCode; MatchedStrata = $r.MatchedStrata }
      }
    }
  }
  $conversionExpected = @('Z/1/0','Z/5a/0','Z/6/0','Z/7/0','P/1/10','P/2/20','P/5a/5','P/5b/6','P/5c/7','P/6/2','P/7/3','CAP/1/60','CAP/2/50','CAP/4/50','CAP/5/40','CAP/5a/20','AUTH/1/60','AUTH/2/50','AUTH/4/60','AUTH/5/50','AUTHB/1/10','AUTHB/4/60','AUTHB/5/50')
  $strataExpected = @('Z/6/0','Z/7/0','P/1/30','P/4/18','P/6/2','P/7/3','CAP/1/99','CAP/4/99','AUTH/1/120','AUTHB/4/123')
  $actualConverted = @($result.Converted | ForEach-Object { '{0}/{1}/{2}' -f $_.PlotNumber,$_.Layer,([double]$_.Cover).ToString('G',[cultureinfo]::InvariantCulture) })
  $actualStrata = @($result.Strata | ForEach-Object { '{0}/{1}/{2}' -f $_.PlotNumber,$_.Layer,([double]$_.Cover).ToString('G',[cultureinfo]::InvariantCulture) })
  Check 'conversion rows including non-null zero and 5a-c, excluding null' ((@(Compare-Object $conversionExpected $actualConverted).Count -eq 0))
  Check 'conversion UPDATE assigned project to all rows' (@($result.Converted | Where-Object { $_.ProjectID -ne 'ORACLE' }).Count -eq 0)
  Check 'strata fallback cap, authoritative totals, zero C/D, suppressed zero A/B' ((@(Compare-Object $strataExpected $actualStrata).Count -eq 0))
  Check 'actual LayerCode contains 1/4/5a/5b/5c/6/7' (@(@('1','4','5a','5b','5c','6','7') | Where-Object { $layers -notcontains $_ }).Count -eq 0)
  $layerJoins = @($result.Joins | Where-Object { $_.Branch -eq 'layer_strata' })
  Check 'Layer1234567 resolves all observed layer and strata rows' (@($layerJoins | Where-Object { $null -eq $_.MatchedCode }).Count -eq 0)
  $lifeJoins = @($result.Joins | Where-Object { $_.Branch -eq 'lifeform' })
  Check 'LayerCode lifeform key leaves all fixture layer/strata values unmatched' ($lifeJoins.Count -eq $layerJoins.Count -and @($lifeJoins | Where-Object { $null -ne $_.MatchedCode }).Count -eq 0)
} catch {
  $result.ProbeError = $_.Exception.ToString()
} finally {
  if ($db) { try { [Runtime.InteropServices.Marshal]::FinalReleaseComObject($db) | Out-Null } catch {} }
  if ($access) {
    try { $access.CloseCurrentDatabase() } catch {}
    try { $access.Quit() } catch {}
    try { [Runtime.InteropServices.Marshal]::FinalReleaseComObject($access) | Out-Null } catch {}
  }
  $result.SourceHashAfter = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
  try { $result.CopyHashAfter = (Get-FileHash -LiteralPath $frontEnd -Algorithm SHA256).Hash } catch { $result.CopyHashAfter = 'locked after shutdown' }
}
Check 'source front-end unchanged' ($result.SourceHashBefore -eq $result.SourceHashAfter -and $result.InitialCopyHash -eq $before)
[pscustomobject]$result | ConvertTo-Json -Depth 8 -Compress
if ($result.ProbeError -or @($result.Checks | Where-Object { -not $_.Pass }).Count -gt 0) { exit 3 }
