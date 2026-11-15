$ErrorActionPreference = 'Stop'
$source = 'C:\Users\BrunoTremblay\Work\VPRO_ACCESS\VPro64\VPro64.accdb'
$access = New-Object -ComObject Access.Application
$db = $null
try {
  $db = $access.DBEngine.Workspaces(0).OpenDatabase($source, $false, $true)
  $wanted = @('Diagnostic', 'DiagnosticGroup', 'USysBreakTable', 'USysSuTableDynamic_SU', 'Sample_Veg', 'MyRS4')
  foreach ($name in $wanted) {
    try {
      $td = $db.TableDefs($name)
      $rs = $db.OpenRecordset('SELECT Count(*) AS n FROM [' + $name + ']')
      [pscustomobject]@{ Name=$name; Connect=$td.Connect; Source=$td.SourceTableName; Rows=$rs.Fields('n').Value }
      $rs.Close()
    } catch {
      [pscustomobject]@{ Name=$name; Error=$_.Exception.Message }
    }
  }
  foreach ($name in @('MyRS5', 'USysVeg')) {
    try {
      $q = $db.QueryDefs($name)
      [pscustomobject]@{ Name=$name; SQL=$q.SQL }
    } catch { [pscustomobject]@{ Name=$name; Error=$_.Exception.Message } }
  }
  $sample = $db.OpenRecordset('SELECT TOP 8 [Reference], BreakCode, PlotNumber FROM USysBreakTable')
  while (-not $sample.EOF) {
    [pscustomobject]@{ BreakReference=$sample.Fields('Reference').Value; BreakCode=$sample.Fields('BreakCode').Value; PlotNumber=$sample.Fields('PlotNumber').Value }
    $sample.MoveNext()
  }
  $sample.Close()
} finally {
  if ($db) { $db.Close() }
  $access.Quit()
  [Runtime.InteropServices.Marshal]::FinalReleaseComObject($access) | Out-Null
}
