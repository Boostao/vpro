param(
  [Parameter(Mandatory = $true)] [string]$SourceDirectory,
  [Parameter(Mandatory = $true)] [string]$ModulePath
)
$ErrorActionPreference = 'Stop'
$source = Join-Path $SourceDirectory 'VPro64.accdb'
$before = (Get-FileHash $source -Algorithm SHA256).Hash
$root = Join-Path $env:LOCALAPPDATA ('Temp\vpro-diagnostic-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Path $root | Out-Null
Copy-Item -Path (Join-Path $SourceDirectory '*') -Destination $root -Recurse -Force
$frontEnd = Join-Path $root 'VPro64.accdb'
$copyHash = (Get-FileHash $frontEnd -Algorithm SHA256).Hash
if ($copyHash -ne $before) { throw 'Disposable front-end copy hash mismatch' }
$evidence = Join-Path $root 'diagnostic-classification.tsv'
$access = $null
$failure = $null
$returned = $null
try {
  $access = New-Object -ComObject Access.Application
  $access.Visible = $false
  $access.AutomationSecurity = 1
  $access.OpenCurrentDatabase($frontEnd, $false)
  Start-Sleep -Seconds 2
  foreach ($form in @($access.CurrentProject.AllForms | Where-Object { $_.IsLoaded } | ForEach-Object Name)) {
    try { $access.DoCmd.Close(2, $form, 2) } catch {}
  }
  $db = $access.CurrentDb()
  foreach ($name in @('MyRS5', 'Diagnostic')) {
    try { $null = $db.TableDefs($name); throw "Disposable fixture name already exists: $name" }
    catch { if ($_.Exception.Message -notmatch 'Item not found in this collection') { throw } }
  }
  $access.LoadFromText(5, 'modDiagnosticClassificationProbe', $ModulePath)
  $escaped = $evidence.Replace('"', '""')
  $returned = $access.Eval("RunDiagnosticClassificationProbe(`"$escaped`")")
} catch {
  $failure = $_.Exception.Message
} finally {
  if ($access) {
    try { $access.CloseCurrentDatabase() } catch {}
    $access.Quit()
    [Runtime.InteropServices.Marshal]::FinalReleaseComObject($access) | Out-Null
  }
}
[pscustomobject]@{
  OracleRoot = $root
  SourceHashBefore = $before
  SourceHashAfter = (Get-FileHash $source -Algorithm SHA256).Hash
  InitialCopyHash = $copyHash
  Result = $returned
  Error = $failure
  Evidence = if (Test-Path $evidence) { [string[]](Get-Content $evidence) } else { @() }
} | ConvertTo-Json -Depth 4
if ($failure -or $returned -eq 'ERROR' -or (Get-FileHash $source -Algorithm SHA256).Hash -ne $before) { exit 3 }
