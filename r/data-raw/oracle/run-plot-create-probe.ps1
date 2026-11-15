param(
  [Parameter(Mandatory = $true)]
  [string]$SourceDirectory,
  [Parameter(Mandatory = $true)]
  [string]$ModulePath,
  [Parameter(Mandatory = $true)]
  [ValidateSet("key-only", "env-only", "admin-only", "both-tables", "leave-key", "cancel-dirty")]
  [string]$Mode,
  [Parameter(Mandatory = $true)]
  [ValidatePattern("^[A-Za-z][A-Za-z0-9_]{0,6}$")]
  [string]$PlotNumber
)

$ErrorActionPreference = "Stop"
$stamp = Get-Date -Format "yyyyMMdd-HHmmss-fff"
$oracleRoot = Join-Path $env:LOCALAPPDATA "Temp\vpro-plot-create-$Mode-$stamp"
New-Item -ItemType Directory -Path $oracleRoot -Force | Out-Null
Copy-Item -Path (Join-Path $SourceDirectory "*") -Destination $oracleRoot -Recurse -Force
$frontEnd = Join-Path $oracleRoot "VPro64.accdb"
$output = Join-Path $oracleRoot "plot-create-$Mode.tsv"
$sourceFrontEnd = Join-Path $SourceDirectory "VPro64.accdb"
$sourceHashBefore = (Get-FileHash $sourceFrontEnd -Algorithm SHA256).Hash
$copyHashBefore = (Get-FileHash $frontEnd -Algorithm SHA256).Hash
$accessBefore = @(Get-Process MSACCESS -ErrorAction SilentlyContinue | ForEach-Object { $_.Id })
$access = New-Object -ComObject Access.Application
Start-Sleep -Milliseconds 500
$accessProcessIds = @(
  Get-Process MSACCESS -ErrorAction SilentlyContinue |
    Where-Object { $_.Id -notin $accessBefore } |
    ForEach-Object { $_.Id }
)
$access.Visible = $false
$returned = $null
$probeError = $null
try {
  $access.AutomationSecurity = 1
  $access.OpenCurrentDatabase($frontEnd, $false)
  Start-Sleep -Seconds 3
  foreach ($loaded in @($access.CurrentProject.AllForms | Where-Object { $_.IsLoaded } | ForEach-Object { $_.Name })) {
    try { $access.DoCmd.Close(2, $loaded, 2) } catch {}
  }
  $access.LoadFromText(5, "modPlotCreateProbe", $ModulePath)
  $escapedOutput = $output.Replace('"', '""')
  $escapedMode = $Mode.Replace('"', '""')
  $escapedPlot = $PlotNumber.Replace('"', '""')
  $returned = $access.Eval("RunPlotCreateOracle(""$escapedOutput"",""$escapedMode"",""$escapedPlot"")")
  $access.CloseCurrentDatabase()
} catch {
  $probeError = "Line {0}: {1}" -f $_.InvocationInfo.ScriptLineNumber, $_.Exception.Message
} finally {
  try { $access.CloseCurrentDatabase() } catch {}
  $access.Quit()
  [Runtime.InteropServices.Marshal]::FinalReleaseComObject($access) | Out-Null
  [GC]::Collect()
  [GC]::WaitForPendingFinalizers()
}
Start-Sleep -Seconds 2
foreach ($processId in $accessProcessIds) {
  $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
  if ($process) {
    Stop-Process -Id $processId -Force
  }
}
$result = [pscustomobject]@{
  OracleRoot = $oracleRoot
  FrontEnd = $frontEnd
  SourceHashBefore = $sourceHashBefore
  SourceHashAfter = (Get-FileHash $sourceFrontEnd -Algorithm SHA256).Hash
  InitialCopyHash = $copyHashBefore
  Output = $output
  Returned = $returned
  ProbeError = $probeError
  Evidence = if (Test-Path $output) { [string[]](Get-Content $output) } else { @() }
}
$result | ConvertTo-Json -Depth 6
if ($probeError) { exit 3 }
