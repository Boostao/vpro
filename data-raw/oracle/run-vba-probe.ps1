param(
  [Parameter(Mandatory = $true)]
  [string]$SourceDirectory,
  [Parameter(Mandatory = $true)]
  [string]$ModulePath
)

$ErrorActionPreference = "Stop"
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$oracleRoot = Join-Path $env:LOCALAPPDATA "Temp\vpro-crud-oracle-vba-$stamp"
New-Item -ItemType Directory -Path $oracleRoot -Force | Out-Null
Copy-Item -Path (Join-Path $SourceDirectory "*") -Destination $oracleRoot -Recurse -Force
$frontEnd = Join-Path $oracleRoot "VPro64.accdb"
$output = Join-Path $oracleRoot "child-oracle.tsv"
$sourceHash = (Get-FileHash (Join-Path $SourceDirectory "VPro64.accdb") -Algorithm SHA256).Hash
$copyHash = (Get-FileHash $frontEnd -Algorithm SHA256).Hash
$access = New-Object -ComObject Access.Application
$access.Visible = $false
try {
  $access.AutomationSecurity = 1
  $access.OpenCurrentDatabase($frontEnd, $false)
  Start-Sleep -Seconds 3
  foreach ($loaded in @($access.CurrentProject.AllForms | Where-Object { $_.IsLoaded } | ForEach-Object { $_.Name })) {
    try { $access.DoCmd.Close(2, $loaded, 2) } catch {}
  }
  $access.LoadFromText(5, "modOracleProbe", $ModulePath)
  $escapedOutput = $output.Replace('"', '""')
  $returned = $access.Eval("RunChildOracle(""$escapedOutput"")")
  $access.CloseCurrentDatabase()
  [pscustomobject]@{
    OracleRoot = $oracleRoot
    FrontEnd = $frontEnd
    SourceHash = $sourceHash
    InitialCopyHash = $copyHash
    Output = $output
    Returned = $returned
    Evidence = if (Test-Path $output) { [string[]](Get-Content $output) } else { @() }
  } | ConvertTo-Json -Depth 6
} catch {
  Write-Error ("Line {0}: {1}" -f $_.InvocationInfo.ScriptLineNumber, $_.Exception.Message)
  exit 3
} finally {
  try { $access.CloseCurrentDatabase() } catch {}
  $access.Quit()
  [Runtime.InteropServices.Marshal]::FinalReleaseComObject($access) | Out-Null
}
