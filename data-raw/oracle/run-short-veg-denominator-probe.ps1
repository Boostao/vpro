param(
  [string]$SourceDirectory = 'C:\Users\BrunoTremblay\Work\VPRO_ACCESS\VPro64'
)

$ErrorActionPreference = 'Stop'
$source = Join-Path $SourceDirectory 'VPro64.accdb'
$before = (Get-FileHash $source -Algorithm SHA256).Hash
$root = Join-Path $env:LOCALAPPDATA ('Temp\vpro-short-veg-denominator-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Path $root -Force | Out-Null
Copy-Item -Path (Join-Path $SourceDirectory '*') -Destination $root -Recurse -Force
$frontEnd = Join-Path $root 'VPro64.accdb'
$copyHash = (Get-FileHash $frontEnd -Algorithm SHA256).Hash
if ($before -ne $copyHash) { throw 'Disposable front-end copy hash mismatch' }

$result = [ordered]@{ OracleRoot = $root; SourceHashBefore = $before; InitialCopyHash = $copyHash; Cases = @() }
$access = $null
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
  $db.Execute('CREATE TABLE zOracleSVMember (PlotNumber TEXT(20), SiteUnit TEXT(20))', 128)
  $db.Execute('CREATE TABLE zOracleSVVeg (PlotNumber TEXT(20), Species TEXT(20), Cover DOUBLE)', 128)
  $db.Execute('CREATE TABLE zOracleSVTemp (PlotNumber TEXT(20), Species TEXT(20), Cover DOUBLE)', 128)
  $db.Execute("INSERT INTO zOracleSVVeg VALUES ('P1', 'SP', 10)", 128)
  $db.Execute("INSERT INTO zOracleSVVeg VALUES ('P1', 'SP', 15)", 128)
  $db.Execute("INSERT INTO zOracleSVVeg VALUES ('P2', 'SP', 5)", 128)
  foreach ($case in @('baseline', 'duplicate', 'cross_unit')) {
    $db.Execute('DELETE FROM zOracleSVMember', 128)
    foreach ($pair in @(@('P1','U'), @('P2','U'), @('P3','U'))) {
      $db.Execute("INSERT INTO zOracleSVMember VALUES ('$($pair[0])', '$($pair[1])')", 128)
    }
    if ($case -eq 'duplicate') { $db.Execute("INSERT INTO zOracleSVMember VALUES ('P1', 'U')", 128) }
    if ($case -eq 'cross_unit') {
      $db.Execute("INSERT INTO zOracleSVMember VALUES ('P1', 'V')", 128)
      $db.Execute("INSERT INTO zOracleSVMember VALUES ('P3', 'V')", 128)
    }
    $db.Execute('DELETE FROM zOracleSVTemp', 128)
    # CreateTempVeg: join with membership, then maximize each field by plot/species.
    $db.Execute('INSERT INTO zOracleSVTemp (PlotNumber, Species, Cover) SELECT v.PlotNumber, v.Species, Max(v.Cover) AS MaxCover FROM zOracleSVVeg AS v INNER JOIN zOracleSVMember AS m ON v.PlotNumber = m.PlotNumber GROUP BY v.PlotNumber, v.Species', 128)
    $sql = 'SELECT m.SiteUnit, Count(m.PlotNumber) AS nPlots FROM zOracleSVMember AS m INNER JOIN (SELECT DISTINCT m2.SiteUnit FROM zOracleSVMember AS m2 INNER JOIN zOracleSVVeg AS v ON m2.PlotNumber = v.PlotNumber WHERE m2.SiteUnit IS NOT NULL) AS SnTable ON m.SiteUnit = SnTable.SiteUnit GROUP BY m.SiteUnit'
    $unitRows = $db.OpenRecordset($sql, 4)
    while (-not $unitRows.EOF) {
      $unit = [string]$unitRows.Fields('SiteUnit').Value
      $nPlots = [int]$unitRows.Fields('nPlots').Value
      # SV2's EntryDat_Veg x SU join supplies Count(Cover), Sum(Cover), Avg(Cover).
      $aggregates = $db.OpenRecordset("SELECT Count(t.Cover) AS coverRecords, Sum(t.Cover) AS sumCover, Avg(t.Cover) AS avgCover FROM zOracleSVTemp AS t INNER JOIN zOracleSVMember AS m ON t.PlotNumber = m.PlotNumber WHERE m.SiteUnit = '$unit'", 4)
      $result.Cases += [pscustomobject]@{
        Case = $case; SiteUnit = $unit; nPlots = $nPlots
        CoverRecords = [int]$aggregates.Fields('coverRecords').Value
        SumCover = [double]$aggregates.Fields('sumCover').Value
        Characteristic = [double]$aggregates.Fields('avgCover').Value
        PresenceRatio = [double]$aggregates.Fields('coverRecords').Value / $nPlots
        ByNPlots = [double]$aggregates.Fields('sumCover').Value / $nPlots
      }
      $aggregates.Close()
      $unitRows.MoveNext()
    }
    $unitRows.Close()
  }
} catch {
  $result.ProbeError = $_.Exception.Message
} finally {
  if ($access) {
    try { $access.CloseCurrentDatabase() } catch {}
    $access.Quit()
    [Runtime.InteropServices.Marshal]::FinalReleaseComObject($access) | Out-Null
  }
  $result.SourceHashAfter = (Get-FileHash $source -Algorithm SHA256).Hash
  try { $result.CopyHashAfter = (Get-FileHash $frontEnd -Algorithm SHA256).Hash } catch { $result.CopyHashAfter = 'locked after shutdown' }
}
[pscustomobject]$result | ConvertTo-Json -Depth 6
if ($result.ProbeError -or $result.SourceHashAfter -ne $before) { exit 3 }
