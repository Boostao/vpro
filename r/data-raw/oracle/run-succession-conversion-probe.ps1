param(
  [Parameter(Mandatory = $true)] [string]$SourceDirectory,
  [Parameter(Mandatory = $true)] [string]$ModulePath,
  [switch]$InterruptAfterVeg
)
$ErrorActionPreference = 'Stop'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$oracleRoot = Join-Path $env:LOCALAPPDATA "Temp\vpro-succession-$stamp"
New-Item -ItemType Directory -Path $oracleRoot -Force | Out-Null
$source = Join-Path $SourceDirectory 'VPro64.accdb'
$before = (Get-FileHash $source -Algorithm SHA256).Hash
Copy-Item -Path (Join-Path $SourceDirectory '*') -Destination $oracleRoot -Recurse -Force
$frontEnd = Join-Path $oracleRoot 'VPro64.accdb'
$copy = (Get-FileHash $frontEnd -Algorithm SHA256).Hash
if ($before -ne $copy) { throw 'Disposable front-end copy hash mismatch' }
$output = Join-Path $oracleRoot 'succession-conversion.tsv'
$backend = Join-Path $oracleRoot 'OracleProject.accdb'
$existing = @(Get-Process MSACCESS -ErrorAction SilentlyContinue | ForEach-Object Id)
$access = $null
$probeError = $null
$returned = $null
$registryPath = 'HKCU:\Software\VB and VBA Program Settings\VPro64\Current'
$originalSettings = @{}
foreach ($name in @('CurrProject', 'ProjectPath', 'CurrPlotlist')) {
  $value = (Get-ItemProperty -Path $registryPath -ErrorAction SilentlyContinue).$name
  $originalSettings[$name] = $value
}
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
  if (-not (Test-Path $sourceModule)) { throw "Missing canonical SaveAsText: $sourceModule" }
  $text = Get-Content $sourceModule -Raw
  $text = $text.Replace('Convert2Succession', 'OracleConvert2Succession').Replace('SuccessionProject', 'OracleSuccessionProject')
  $text = $text.Replace('Private Function OracleConvert2Succession', 'Public Function OracleConvert2Succession')
  $text = $text.Replace('NewYear = InputBox("What year do you wish to set the current data to?", "VPro - convert to succession", Year(Now()))', 'NewYear = 2021')
  $text = $text.Replace('MsgBox "Your project has been converted", vbInformation, "VPro"', '')
  $text = $text.Replace('MsgBox "This project is already a successional project"', 'OracleConversionError = "Already successional"')
  $text = $text.Replace('MsgBox "You can''t perform this operation on the sample project"', 'OracleConversionError = "Sample is protected"')
  $text = $text.Replace('MsgBox Err.Number', 'OracleConversionError = CStr(Err.Number) & ":" & Err.Description')
  $text = $text.Replace('DoCmd.OpenForm "MainMenu"', "' Oracle: MainMenu is not present in this front-end copy")
  $text = $text.Replace('Do Until Screen.ActiveForm.Name = "MainMenu"' + "`r`n" + '    DoEvents' + "`r`n" + 'Loop', "' Oracle: skip wait for missing MainMenu")
  $text = $text.Replace('Screen.ActiveForm.Recalc', "' Oracle: no active MainMenu form")
  $text = $text.Replace('If Screen.ActiveForm.Name = "MainMenu" Then', 'If False Then')
  if ($text.Contains('Do Until Screen.ActiveForm.Name = "MainMenu"')) { throw 'Unsafe probe: MainMenu wait was not removed' }
  $text = $text -replace 'Option Explicit', "Option Explicit`r`nPublic OracleConversionError As String`r`nPublic OracleConversionStage As String"
  $text = $text.Replace('If OracleSuccessionProject(FirstProject) Then', 'OracleConversionStage = "precheck"' + "`r`n" + 'If OracleSuccessionProject(FirstProject) Then')
  $text = $text.Replace('If CurrProject = "Sample" Then', 'OracleConversionStage = "sample guard"' + "`r`n" + 'If CurrProject = "Sample" Then')
  $text = $text.Replace('NewYear = 2021', 'OracleConversionStage = "year"' + "`r`n" + 'NewYear = 2021')
  $text = $text.Replace('Set MyTD = MyDB.TableDefs(Project)', 'OracleConversionStage = "vegetation schema"' + "`r`n" + 'Set MyTD = MyDB.TableDefs(Project)')
  $text = $text.Replace('Project = Left(Project, Len(Project) - 4) & "_Env"', 'OracleConversionStage = "environment schema"' + "`r`n" + 'Project = Left(Project, Len(Project) - 4) & "_Env"')
  if ($InterruptAfterVeg) {
    $text = $text.Replace('Project = Left(Project, Len(Project) - 4) & "_Env"', 'Err.Raise vbObjectError + 613, "OracleConversion", "Simulated interruption after Veg year update"' + "`r`n" + 'Project = Left(Project, Len(Project) - 4) & "_Env"')
  }
  $text = $text.Replace('    SetCurrentProject FirstProject', '    OracleConversionStage = "reactivate"' + "`r`n" + '    SetCurrentProject FirstProject')
  $module = Join-Path $oracleRoot 'V7mdlSuccession-oracle.bas'
  Set-Content -Path $module -Value $text
  $access.LoadFromText(5, 'zOracleSuccession', $module)
  $access.LoadFromText(5, 'modSuccessionConversionProbe', $ModulePath)
  $quotedOutput = $output.Replace('"', '""')
  $quotedBackend = $backend.Replace('"', '""')
  $returned = $access.Eval("RunSuccessionConversionOracle(`"$quotedOutput`",`"$quotedBackend`")")
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
  foreach ($name in $originalSettings.Keys) {
    if ($null -eq $originalSettings[$name]) {
      Remove-ItemProperty -Path $registryPath -Name $name -ErrorAction SilentlyContinue
    } else {
      New-Item -Path $registryPath -Force | Out-Null
      Set-ItemProperty -Path $registryPath -Name $name -Value $originalSettings[$name]
    }
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
  BackendHashAfter = if (Test-Path $backend) { (Get-FileHash $backend -Algorithm SHA256).Hash } else { $null }
  Returned = $returned
  ProbeError = $probeError
  Evidence = if (Test-Path $output) { [string[]](Get-Content $output) } else { @() }
} | ConvertTo-Json -Depth 5
if ($probeError) { exit 3 }
