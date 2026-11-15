param(
  [Parameter(Mandatory = $true)] [string]$SourceDirectory
)
$ErrorActionPreference = "Stop"
$root = Join-Path $env:LOCALAPPDATA ("Temp\vpro-restore-sql-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
New-Item -ItemType Directory -Path $root -Force | Out-Null
Copy-Item -Path (Join-Path $SourceDirectory "*") -Destination $root -Recurse -Force
$frontEnd = Join-Path $root "VPro64.accdb"
$a = New-Object -ComObject Access.Application
$result = [ordered]@{ OracleRoot = $root; SourceHash = (Get-FileHash (Join-Path $SourceDirectory "VPro64.accdb") -Algorithm SHA256).Hash }
try {
  $db = $a.DBEngine.Workspaces(0).OpenDatabase($frontEnd, $false, $false)
  $rs = $db.OpenRecordset("SELECT TOP 1 PlotNumber FROM Sample_Env ORDER BY PlotNumber", 2)
  $plot = [string]$rs.Fields.Item(0).Value
  $rs.Close()
  $result.PlotNumber = $plot
  $cases = [ordered]@{
    EnvLocation = "SELECT * FROM [Sample_Env] WHERE (((PlotNumber)='$plot'));"
    AdminFieldMislabeledEnv = "SELECT * FROM [Sample_Env] WHERE (((PlotNumber)='$plot'));"
    AdminSuffix = ""
  }
  $outcomes = [ordered]@{}
  foreach ($name in $cases.Keys) {
    try {
      $sql = $cases[$name]
      $r = $db.OpenRecordset($sql, 2)
      $field = if ($name -eq "EnvLocation") { "Location" } else { "PlotType" }
      $fieldExists = $false
      foreach ($f in $r.Fields) { if ($f.Name -eq $field) { $fieldExists = $true } }
      $outcomes[$name] = [pscustomobject]@{ Sql = $sql; Opened = $true; Field = $field; FieldExists = $fieldExists; ErrorNumber = $null; Error = $null }
      $r.Close()
    } catch {
      $outcomes[$name] = [pscustomobject]@{ Sql = $cases[$name]; Opened = $false; Field = if ($name -eq "EnvLocation") { "Location" } else { "PlotType" }; FieldExists = $false; ErrorNumber = $_.Exception.ErrorCode; Error = $_.Exception.Message }
    }
  }
  $result.Outcomes = $outcomes
  $db.Close()
  $result | ConvertTo-Json -Depth 6
} finally {
  if ($db) { try { $db.Close() } catch {} }
  $a.Quit()
  [Runtime.InteropServices.Marshal]::FinalReleaseComObject($a) | Out-Null
}
