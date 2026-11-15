param(
  [Parameter(Mandatory = $true)] [string]$SourceDirectory,
  [Parameter(Mandatory = $true)] [string]$ModulePath,
  [switch]$RunOptimizer
)
$ErrorActionPreference = "Stop"
$stamp = Get-Date -Format "yyyyMMdd-HHmmss-fff"
$oracleRoot = Join-Path $env:LOCALAPPDATA "Temp\vpro-veg-full-$stamp"
New-Item -ItemType Directory -Path $oracleRoot -Force | Out-Null
$source = Join-Path $SourceDirectory "VPro64.accdb"
$before = (Get-FileHash $source -Algorithm SHA256).Hash
Copy-Item -Path (Join-Path $SourceDirectory "*") -Destination $oracleRoot -Recurse -Force
$frontEnd = Join-Path $oracleRoot "VPro64.accdb"
$copy = (Get-FileHash $frontEnd -Algorithm SHA256).Hash
if ($before -ne $copy) { throw "Disposable copy hash mismatch" }
$output = Join-Path $oracleRoot "veg-optimize-full.tsv"
$existing = @(Get-Process MSACCESS -ErrorAction SilentlyContinue | ForEach-Object Id)
$access = $null
$probeError = $null
$returned = $null
try {
  $access = New-Object -ComObject Access.Application
  $access.Visible = $false
  $access.AutomationSecurity = 1
  $access.OpenCurrentDatabase($frontEnd, $false)
  Start-Sleep -Seconds 3
  foreach ($loaded in @($access.CurrentProject.AllForms | Where-Object { $_.IsLoaded } | ForEach-Object Name)) {
    try { $access.DoCmd.Close(2, $loaded, 2) } catch {}
  }
  if ($RunOptimizer) {
    $sourceModule = Join-Path (Split-Path $SourceDirectory -Parent) "VPro64_forAI\Modules\V7mdlOptimizeVeg.txt"
    if (-not (Test-Path $sourceModule)) { throw "Optimizer SaveAsText not found: $sourceModule" }
    $optimizerText = Get-Content $sourceModule -Raw
    $optimizerText = $optimizerText.Replace('OptimizeVeg', 'OracleOptimizeVeg').Replace('Check4DuplicatedSpecies', 'OracleCheck4DuplicatedSpecies')
    $optimizerText = $optimizerText.Replace('MsgBox "VPro has optimized your vegetation records.  If you have a data form open, it may be necessary to close and reopen the form to show the changes.", , "VPro"', "")
    $optimizerText = $optimizerText.Replace('MsgBox "Once you''ve fixed your vegetation records, try again.", , "VPro"', "")
    $optimizerText = $optimizerText.Replace('MsgBox Err.Description', "")
    $optimizerText = $optimizerText.Replace('Msg = "There are some problems in your vegetation data.  Would you like VPro to generate an error report?"', 'Msg = "Oracle diagnostic error"')
    $optimizerText = $optimizerText.Replace('Response = MsgBox(Msg, dgdef, Title)', 'Response = 7')
    $optimizerText = $optimizerText.Replace('MsgBox "These errors should be fixed before using this data."', "")
    $tempModule = Join-Path $oracleRoot "V7mdlOptimizeVeg-oracle.bas"
    Set-Content -Path $tempModule -Value $optimizerText
    $access.LoadFromText(5, "zOracleOptimizeVeg", $tempModule)
  }
  $access.LoadFromText(5, "modVegOptimizeFullProbe", $ModulePath)
  $escaped = $output.Replace('"', '""')
  $runFlag = if ($RunOptimizer) { "True" } else { "False" }
  $returned = $access.Eval("RunVegOptimizeFullOracle(`"$escaped`",$runFlag)")
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
foreach ($pidAfter in @(Get-Process MSACCESS -ErrorAction SilentlyContinue | ForEach-Object Id)) {
  if ($pidAfter -notin $existing) { Stop-Process -Id $pidAfter -Force -ErrorAction SilentlyContinue }
}
[pscustomobject]@{
  OracleRoot = $oracleRoot
  SourceHashBefore = $before
  SourceHashAfter = (Get-FileHash $source -Algorithm SHA256).Hash
  InitialCopyHash = $copy
  Output = $output
  Returned = $returned
  ProbeError = $probeError
  Evidence = if (Test-Path $output) { [string[]](Get-Content $output) } else { @() }
} | ConvertTo-Json -Depth 6
if ($probeError) { exit 3 }
