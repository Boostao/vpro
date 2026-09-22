param(
  [Parameter(Mandatory = $true)] [string]$SourceDirectory,
  [Parameter(Mandatory = $true)] [string]$InterruptedBackend,
  [Parameter(Mandatory = $true)] [string]$ModulePath
)
$ErrorActionPreference = 'Stop'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$oracleRoot = Join-Path $env:LOCALAPPDATA "Temp\vpro-succession-reattach-$stamp"
New-Item -ItemType Directory -Path $oracleRoot -Force | Out-Null
$source = Join-Path $SourceDirectory 'VPro64.accdb'
$sourceHash = (Get-FileHash $source -Algorithm SHA256).Hash
$interruptedHash = (Get-FileHash $InterruptedBackend -Algorithm SHA256).Hash
Copy-Item -Path (Join-Path $SourceDirectory '*') -Destination $oracleRoot -Recurse -Force
$frontEnd = Join-Path $oracleRoot 'VPro64.accdb'
$backend = Join-Path $oracleRoot 'OracleProject.accdb'
Copy-Item -Path $InterruptedBackend -Destination $backend
$initialFrontEndHash = (Get-FileHash $frontEnd -Algorithm SHA256).Hash
$initialBackendHash = (Get-FileHash $backend -Algorithm SHA256).Hash
if ($initialFrontEndHash -ne $sourceHash) { throw 'Front-end clone hash mismatch' }
if ($initialBackendHash -ne $interruptedHash) { throw 'Backend clone hash mismatch' }
$output = Join-Path $oracleRoot 'succession-reattach.tsv'
$registryPath = 'HKCU:\Software\VB and VBA Program Settings\VPro64\Current'
$settings = @{}
foreach ($name in @('CurrProject', 'ProjectPath', 'CurrPlotlist')) {
  $settings[$name] = (Get-ItemProperty -Path $registryPath -ErrorAction SilentlyContinue).$name
}
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
  $sourceModule = Join-Path (Split-Path $SourceDirectory -Parent) 'VPro64_forAI\Modules\V7mdlSuccession.txt'
  if (-not (Test-Path $sourceModule)) { throw 'Canonical succession module unavailable' }
  $text = Get-Content $sourceModule -Raw
  $text = $text.Replace('Convert2Succession', 'OracleConvert2Succession').Replace('SuccessionProject', 'OracleSuccessionProject')
  $text = $text.Replace('Private Function OracleConvert2Succession', 'Public Function OracleConvert2Succession')
  $text = $text.Replace('MsgBox "This project is already a successional project"', 'OracleConversionError = "Already successional"')
  $text = $text.Replace('MsgBox "You can''t perform this operation on the sample project"', 'OracleConversionError = "Sample is protected"')
  $text = $text.Replace('MsgBox Err.Number', 'OracleConversionError = CStr(Err.Number) & ":" & Err.Description')
  $text = $text -replace 'Option Explicit', "Option Explicit`r`nPublic OracleConversionError As String`r`nPublic OracleConversionStage As String"
  $text = $text.Replace('If OracleSuccessionProject(FirstProject) Then', 'OracleConversionStage = "precheck"' + "`r`n" + 'If OracleSuccessionProject(FirstProject) Then')
  $module = Join-Path $oracleRoot 'V7mdlSuccession-reattach.bas'
  Set-Content -Path $module -Value $text
  $access.LoadFromText(5, 'zOracleSuccession', $module)
  $access.LoadFromText(5, 'modSuccessionReattachProbe', $ModulePath)
  $qOutput = $output.Replace('"', '""')
  $qBackend = $backend.Replace('"', '""')
  $returned = $access.Eval("RunSuccessionReattachOracle(`"$qOutput`",`"$qBackend`")")
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
  foreach ($name in $settings.Keys) {
    if ($null -eq $settings[$name]) {
      Remove-ItemProperty -Path $registryPath -Name $name -ErrorAction SilentlyContinue
    } else {
      New-Item -Path $registryPath -Force | Out-Null
      Set-ItemProperty -Path $registryPath -Name $name -Value $settings[$name]
    }
  }
}
Start-Sleep -Seconds 2
foreach ($pidAfter in @(Get-Process MSACCESS -ErrorAction SilentlyContinue | ForEach-Object Id)) {
  if ($pidAfter -notin $existing) { Stop-Process -Id $pidAfter -Force -ErrorAction SilentlyContinue }
}
[pscustomobject]@{
  OracleRoot = $oracleRoot
  SourceHashBefore = $sourceHash
  SourceHashAfter = (Get-FileHash $source -Algorithm SHA256).Hash
  InterruptedBackendHashBefore = $interruptedHash
  InterruptedBackendHashAfter = (Get-FileHash $InterruptedBackend -Algorithm SHA256).Hash
  InitialCopyHash = $initialFrontEndHash
  InitialBackendCopyHash = $initialBackendHash
  Returned = $returned
  ProbeError = $probeError
  Evidence = if (Test-Path $output) { [string[]](Get-Content $output) } else { @() }
} | ConvertTo-Json -Depth 5
if ($probeError) { exit 3 }
