$ErrorActionPreference = "Stop"
$source = "C:\Users\BrunoTremblay\Work\VPRO_ACCESS\VPro64"
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$oracleRoot = Join-Path $env:LOCALAPPDATA "Temp\vpro-crud-oracle-$stamp"
New-Item -ItemType Directory -Path $oracleRoot -Force | Out-Null
Copy-Item -Path (Join-Path $source "*") -Destination $oracleRoot -Recurse -Force
$frontEnd = Join-Path $oracleRoot "VPro64.accdb"
$access = New-Object -ComObject Access.Application
try {
  $db = $access.DBEngine.Workspaces(0).OpenDatabase($frontEnd, $false, $true)
  $tables = foreach ($td in $db.TableDefs) {
    if (-not $td.Name.StartsWith("MSys")) {
      [pscustomobject]@{
        Name = $td.Name
        Connect = $td.Connect
        SourceTableName = $td.SourceTableName
        Attributes = $td.Attributes
      }
    }
  }
  $db.Close()
  [pscustomobject]@{
    OracleRoot = $oracleRoot
    FrontEnd = $frontEnd
    FrontEndHash = (Get-FileHash $frontEnd -Algorithm SHA256).Hash
    SourceHash = (Get-FileHash (Join-Path $source "VPro64.accdb") -Algorithm SHA256).Hash
    Tables = $tables
  } | ConvertTo-Json -Depth 5
} finally {
  if ($db) { try { $db.Close() } catch {} }
  $access.Quit()
  [Runtime.InteropServices.Marshal]::FinalReleaseComObject($access) | Out-Null
}
