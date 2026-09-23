$ErrorActionPreference = 'Stop'
$sourceDirectory = 'C:\Users\BrunoTremblay\Work\VPRO_ACCESS\VPro64'
$source = Join-Path $sourceDirectory 'VPro64.accdb'
$before = (Get-FileHash $source -Algorithm SHA256).Hash
$root = Join-Path $env:LOCALAPPDATA ('Temp\vpro-quick-summary-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Path $root | Out-Null
Copy-Item -Path (Join-Path $sourceDirectory '*') -Destination $root -Recurse -Force
$frontEnd = Join-Path $root 'VPro64.accdb'
$copyHash = (Get-FileHash $frontEnd -Algorithm SHA256).Hash
if ($copyHash -ne $before) { throw 'Disposable front-end copy hash mismatch' }
$access = $null
$result = [ordered]@{ OracleRoot = $root; SourceHashBefore = $before; InitialCopyHash = $copyHash }
try {
  $access = New-Object -ComObject Access.Application
  $access.Visible = $false
  $access.AutomationSecurity = 1
  $access.OpenCurrentDatabase($frontEnd, $false)
  Start-Sleep -Seconds 2
  foreach ($form in @($access.CurrentProject.AllForms | Where-Object { $_.IsLoaded } | ForEach-Object Name)) {
    try { $access.DoCmd.Close(2, $form, 2) } catch {}
  }
  $db = $access.CurrentDb()
  $envFields = @($db.TableDefs('Sample_Env').Fields | ForEach-Object Name)
  $adminFields = @($db.TableDefs('Sample_Admin').Fields | ForEach-Object Name)
  $result.EnvHasAssignedSiteUnit = [bool]($envFields -contains 'AssignedSiteUnit')
  $result.AdminHasUserSiteUnit = [bool]($adminFields -contains 'UserSiteUnit')
  $result.AllVegQueryExists = [bool]($db.QueryDefs('USysAllVeg') -ne $null)
  $result.LegacyDqySourceExists = Test-Path (Join-Path $root 'VPro97.mdb')
  $sql = 'SELECT Sample_Env.PlotNumber, Sample_Env.AssignedSiteUnit, USysAllVeg.MyLayer, USysAllVeg.Species, USysAllVeg.Cover FROM Sample_Env INNER JOIN USysAllVeg ON Sample_Env.PlotNumber = USysAllVeg.PlotNumber'
  try {
    $rs = $db.OpenRecordset($sql, 4)
    $result.OriginalQueryStatus = 'opened'
    $result.OriginalQueryRows = $rs.RecordCount
    $rs.Close()
  } catch {
    $result.OriginalQueryStatus = 'failed'
    $result.OriginalQueryError = $_.Exception.Message
  }
  $sql = 'SELECT Sample_Env.PlotNumber, Sample_Admin.UserSiteUnit AS AssignedSiteUnit, USysAllVeg.MyLayer, USysAllVeg.Species, USysAllVeg.Cover FROM (Sample_Env INNER JOIN Sample_Admin ON Sample_Env.PlotNumber = Sample_Admin.Plot) INNER JOIN USysAllVeg ON Sample_Env.PlotNumber = USysAllVeg.PlotNumber'
  try {
    $rs = $db.OpenRecordset($sql, 4)
    $result.RewriteQueryStatus = 'opened'
    if (-not $rs.EOF) { $rs.MoveLast(); $result.RewriteQueryRows = $rs.RecordCount; $rs.MoveFirst() } else { $result.RewriteQueryRows = 0 }
    $rows = @()
    for ($i = 0; $i -lt 5 -and -not $rs.EOF; $i++) {
      $rows += [pscustomobject]@{ PlotNumber = [string]$rs.Fields('PlotNumber').Value; AssignedSiteUnit = [string]$rs.Fields('AssignedSiteUnit').Value; MyLayer = [string]$rs.Fields('MyLayer').Value; Species = [string]$rs.Fields('Species').Value; Cover = $rs.Fields('Cover').Value }
      $rs.MoveNext()
    }
    $result.RewriteSample = $rows
    $rs.Close()
  } catch {
    $result.RewriteQueryStatus = 'failed'
    $result.RewriteQueryError = $_.Exception.Message
  }
  $sql = 'SELECT Sample_Env.PlotNumber, Sample_Admin.UserSiteUnit AS AssignedSiteUnit, USysAllVeg.MyLayer, USysAllVeg.Species, USysAllVeg.Cover FROM (Sample_Env INNER JOIN USysAllVeg ON Sample_Env.PlotNumber = USysAllVeg.PlotNumber) LEFT JOIN Sample_Admin ON Sample_Env.PlotNumber = Sample_Admin.Plot'
  try {
    $rs = $db.OpenRecordset($sql, 4)
    $result.LeftJoinQueryStatus = 'opened'
    if (-not $rs.EOF) { $rs.MoveLast(); $result.LeftJoinQueryRows = $rs.RecordCount } else { $result.LeftJoinQueryRows = 0 }
    $rs.Close()
  } catch {
    $result.LeftJoinQueryStatus = 'failed'
    $result.LeftJoinQueryError = $_.Exception.Message
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
  try { $result.CopyHashAfter = (Get-FileHash $frontEnd -Algorithm SHA256).Hash } catch { $result.CopyHashAfter = 'locked at shutdown' }
}
[pscustomobject]$result | ConvertTo-Json -Depth 6
if ($result.ProbeError -or $result.SourceHashAfter -ne $before) { exit 3 }
