param(
  [Parameter(Mandatory = $true)] [string]$SourceDirectory,
  [Parameter(Mandatory = $true)] [string]$ModulePath,
  [Parameter(Mandatory = $true)] [ValidateSet('covers', 'duplicate', 'duplicate-after', 'same-year', 'missing')] [string]$Scenario
)
$ErrorActionPreference = 'Stop'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$oracleRoot = Join-Path $env:LOCALAPPDATA "Temp\vpro-succession-copy-$Scenario-$stamp"
New-Item -ItemType Directory -Path $oracleRoot -Force | Out-Null
$source = Join-Path $SourceDirectory 'VPro64.accdb'
$sourceModule = Join-Path (Split-Path $SourceDirectory -Parent) 'VPro64_forAI\Modules\V7mdlSuccession.txt'
if (-not (Test-Path $sourceModule)) { throw "Missing canonical source: $sourceModule" }
$before = (Get-FileHash $source -Algorithm SHA256).Hash
$moduleBefore = (Get-FileHash $sourceModule -Algorithm SHA256).Hash
Copy-Item -Path (Join-Path $SourceDirectory '*') -Destination $oracleRoot -Recurse -Force
$frontEnd = Join-Path $oracleRoot 'VPro64.accdb'
$initialCopy = (Get-FileHash $frontEnd -Algorithm SHA256).Hash
if ($before -ne $initialCopy) { throw 'Disposable front-end copy hash mismatch' }
$output = Join-Path $oracleRoot 'succession-copy.tsv'
$backend = Join-Path $oracleRoot 'OracleProject.accdb'
$existing = @(Get-Process MSACCESS -ErrorAction SilentlyContinue | ForEach-Object Id)
$registryPath = 'HKCU:\Software\VB and VBA Program Settings\VPro64\Current'
$settings = @{}
foreach ($name in @('CurrProject', 'ProjectPath', 'CurrPlotlist')) {
  $settings[$name] = (Get-ItemProperty -Path $registryPath -ErrorAction SilentlyContinue).$name
}
$access = $null
$probeError = $null
$returned = $null
try {
  $text = Get-Content $sourceModule -Raw
  $start = $text.IndexOf('Private Function CopySuccessionData(')
  $finish = $text.IndexOf('End Function', $text.IndexOf('Private Function Check4DuplicateData(', $start))
  if ($start -lt 0 -or $finish -lt 0) { throw 'Canonical copy and duplicate functions not found' }
  $text = "Option Compare Database`r`nOption Explicit`r`nPublic OracleSourceYear As Integer`r`nPublic OracleCopyError As String`r`nDim CheckRS As Recordset`r`n" + $text.Substring($start, $finish + 'End Function'.Length - $start)
  $text = $text.Replace('CopySuccessionData', 'OracleCopySuccessionData').Replace('Check4DuplicateData', 'OracleCheck4DuplicateData')
  $text = $text.Replace('Private Function OracleCopySuccessionData', 'Public Function OracleCopySuccessionData')
  $prompt = 'Yr2Copy = InputBox("Enter as 4 digit integer for the year you wish to copy.", "Copy Succession Species")'
  if (-not $text.Contains($prompt)) { throw 'Expected source-year prompt not found' }
  $text = $text.Replace($prompt, 'Yr2Copy = OracleSourceYear')
  $text = $text.Replace('MsgBox "There were no records to copy from the year you specified.", vbInformation, "VPro"', 'OracleCopyError = "No source records"')
  $text = $text.Replace('MsgBox Err.Description', 'OracleCopyError = CStr(Err.Number) & ":" & Err.Description')
  if ($text.Contains('InputBox(') -or $text.Contains('MsgBox ')) { throw 'Unsafe modal in adapted copy module' }
  $adapted = Join-Path $oracleRoot 'V7mdlSuccession-copy-oracle.bas'
  Set-Content -Path $adapted -Value $text
  $access = New-Object -ComObject Access.Application
  $access.Visible = $false
  $access.AutomationSecurity = 1
  $access.OpenCurrentDatabase($frontEnd, $false)
  Start-Sleep -Seconds 3
  foreach ($loaded in @($access.CurrentProject.AllForms | Where-Object { $_.IsLoaded } | ForEach-Object Name)) {
    try { $access.DoCmd.Close(2, $loaded, 2) } catch {}
  }
  $access.LoadFromText(5, 'zOracleSuccessionCopy', $adapted)
  $access.LoadFromText(5, 'modSuccessionCopyProbe', $ModulePath)
  $qOutput = $output.Replace('"', '""')
  $qBackend = $backend.Replace('"', '""')
  $returned = $access.Eval("RunSuccessionCopyOracle(`"$qOutput`",`"$qBackend`",`"$Scenario`")")
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
  Scenario = $Scenario
  OracleRoot = $oracleRoot
  SourceHashBefore = $before
  SourceHashAfter = (Get-FileHash $source -Algorithm SHA256).Hash
  ModuleHashBefore = $moduleBefore
  ModuleHashAfter = (Get-FileHash $sourceModule -Algorithm SHA256).Hash
  InitialCopyHash = $initialCopy
  BackendHashAfter = if (Test-Path $backend) { (Get-FileHash $backend -Algorithm SHA256).Hash } else { $null }
  Returned = $returned
  ProbeError = $probeError
  Evidence = if (Test-Path $output) { [string[]](Get-Content $output) } else { @() }
} | ConvertTo-Json -Depth 5
if ($probeError) { exit 3 }
