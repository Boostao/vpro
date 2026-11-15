param(
  [Parameter(Mandatory = $true)] [string]$SourceDirectory,
  [Parameter(Mandatory = $true)] [string]$ModulePath
)

$ErrorActionPreference = "Stop"
$stamp = Get-Date -Format "yyyyMMdd-HHmmss-fff"
$oracleRoot = Join-Path $env:LOCALAPPDATA "Temp\vpro-veg-optimize-$stamp"
New-Item -ItemType Directory -Path $oracleRoot -Force | Out-Null
$sourceFrontEnd = Join-Path $SourceDirectory "VPro64.accdb"
$sourceHashBefore = (Get-FileHash $sourceFrontEnd -Algorithm SHA256).Hash
Copy-Item -Path (Join-Path $SourceDirectory "*") -Destination $oracleRoot -Recurse -Force
$frontEnd = Join-Path $oracleRoot "VPro64.accdb"
$copyHashBefore = (Get-FileHash $frontEnd -Algorithm SHA256).Hash
if ($sourceHashBefore -ne $copyHashBefore) { throw "Disposable copy does not match source." }
$output = Join-Path $oracleRoot "veg-optimize.tsv"
$accessBefore = @(Get-Process MSACCESS -ErrorAction SilentlyContinue | ForEach-Object { $_.Id })
$access = $null
$returned = $null
$probeError = $null
try {
  $access = New-Object -ComObject Access.Application
  $access.Visible = $false
  $access.AutomationSecurity = 1
  $access.OpenCurrentDatabase($frontEnd, $false)
  Start-Sleep -Seconds 3
  foreach ($loaded in @($access.CurrentProject.AllForms | Where-Object { $_.IsLoaded } | ForEach-Object { $_.Name })) {
    try { $access.DoCmd.Close(2, $loaded, 2) } catch {}
  }
  $access.LoadFromText(5, "modVegOptimizeProbe", $ModulePath)
  $escapedOutput = $output.Replace('"', '""')
  $returned = $access.Eval("RunVegOptimizeOracle(`"$escapedOutput`")")
} catch {
  $probeError = "Line {0}: {1}" -f $_.InvocationInfo.ScriptLineNumber, $_.Exception.Message
} finally {
  if ($access) {
    try { $access.CloseCurrentDatabase() } catch {}
    $access.Quit()
    [Runtime.InteropServices.Marshal]::FinalReleaseComObject($access) | Out-Null
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
  }
}
Start-Sleep -Seconds 2
$accessAfter = @(Get-Process MSACCESS -ErrorAction SilentlyContinue | ForEach-Object { $_.Id })
foreach ($processId in $accessAfter) {
  if ($processId -notin $accessBefore) { Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue }
}
[pscustomobject]@{
  OracleRoot = $oracleRoot
  SourceHashBefore = $sourceHashBefore
  SourceHashAfter = (Get-FileHash $sourceFrontEnd -Algorithm SHA256).Hash
  InitialCopyHash = $copyHashBefore
  Output = $output
  Returned = $returned
  ProbeError = $probeError
  Evidence = if (Test-Path $output) { [string[]](Get-Content $output) } else { @() }
} | ConvertTo-Json -Depth 6
if ($probeError) { exit 3 }
