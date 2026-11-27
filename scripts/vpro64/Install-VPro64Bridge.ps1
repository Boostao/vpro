<#
.SYNOPSIS
  Installs the VPro 2.0 -> VPro64 SQLite VBA Importer (V7mdlImportSQLite.bas)
  into an existing VPro64.accdb Microsoft Access database.

.DESCRIPTION
  1. Unblocks extracted files to prevent Windows Mark-of-the-Web (MOTW) macro warnings.
  2. Verifies that Christian Werner's 64-bit SQLite3 ODBC Driver is installed.
  3. Creates a timestamped backup copy of VPro64.accdb (unless -SkipBackup is passed).
  4. Imports (or updates) V7mdlImportSQLite.bas inside VPro64.accdb via Access COM.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Install-VPro64Bridge.ps1

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Install-VPro64Bridge.ps1 -AccdbPath "C:\VPro64\VPro64.accdb"
#>
[CmdletBinding()]
param(
    [string]$AccdbPath = "",
    [string]$ModulePath = "",
    [switch]$SkipBackup,
    [switch]$CheckDriverOnly
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($ModulePath)) {
    $ModulePath = Join-Path $scriptDir "V7mdlImportSQLite.bas"
}

Write-Host "=== VPro64 SQLite Import Bridge Setup ===" -ForegroundColor Cyan

# 1. Clear Windows Mark-of-the-Web (Zone.Identifier) on extracted bridge files
try {
    Get-ChildItem -Path $scriptDir -File -ErrorAction SilentlyContinue | ForEach-Object {
        Unblock-File -Path $_.FullName -ErrorAction SilentlyContinue
    }
} catch {
    # Non-fatal on filesystems without alternate data streams
}

# 2. Verify 64-bit SQLite3 ODBC Driver
$sqliteDriver = $null
try {
    $sqliteDriver = Get-OdbcDriver -ErrorAction Stop | Where-Object {
        $_.Name -eq "SQLite3 ODBC Driver" -and $_.Platform -like "*64*"
    } | Select-Object -First 1
} catch {
    Write-Warning "Could not query Windows ODBC drivers automatically: $($_.Exception.Message)"
}

if ($null -ne $sqliteDriver) {
    Write-Host "[OK] Found $($sqliteDriver.Name) ($($sqliteDriver.Platform))." -ForegroundColor Green
} else {
    Write-Host "[!] 64-bit 'SQLite3 ODBC Driver' was not detected." -ForegroundColor Yellow
    Write-Host "    Download and install Christian Werner's 64-bit SQLite3 ODBC Driver:"
    Write-Host "      http://www.ch-werner.de/sqliteodbc/sqliteodbc_w64.exe"
    Write-Host "    (Accept defaults, then restart Microsoft Access.)"
    if ($CheckDriverOnly) {
        exit 1
    }
}

if ($CheckDriverOnly) {
    exit 0
}

if (-not (Test-Path -LiteralPath $ModulePath -PathType Leaf)) {
    throw "VBA module file not found: $ModulePath"
}
$resolvedModule = (Resolve-Path -LiteralPath $ModulePath).Path

# 3. Locate VPro64.accdb (interactive Windows picker if omitted)
if ([string]::IsNullOrWhiteSpace($AccdbPath)) {
    Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = "Select your VPro64.accdb file"
    $dialog.Filter = "Microsoft Access Database (*.accdb)|*.accdb|All Files (*.*)|*.*"
    $dialog.CheckFileExists = $true
    if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
        Write-Host "Cancelled. No changes were made."
        exit 0
    }
    $AccdbPath = $dialog.FileName
}

if (-not (Test-Path -LiteralPath $AccdbPath -PathType Leaf)) {
    throw "Access database not found: $AccdbPath"
}
$resolvedAccdb = (Resolve-Path -LiteralPath $AccdbPath).Path

# Clear MOTW on the selected .accdb as well if present
try { Unblock-File -Path $resolvedAccdb -ErrorAction SilentlyContinue } catch {}

# 4. Back up VPro64.accdb before modifying
if (-not $SkipBackup) {
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupPath = "$resolvedAccdb.backup-$stamp.accdb"
    Copy-Item -LiteralPath $resolvedAccdb -Destination $backupPath -Force
    Write-Host "[OK] Backup saved to: $backupPath" -ForegroundColor Green
}

# 5. Import V7mdlImportSQLite.bas into VPro64.accdb via Microsoft Access COM
$access = $null
try {
    Write-Host "Opening Microsoft Access to import V7mdlImportSQLite..."
    $access = New-Object -ComObject Access.Application
    $access.Visible = $false
    $access.OpenCurrentDatabase($resolvedAccdb)

    $vbProject = $access.VBE.ActiveVBProject
    $existing = $null
    foreach ($comp in $vbProject.VBComponents) {
        if ($comp.Name -eq "V7mdlImportSQLite") {
            $existing = $comp
            break
        }
    }
    if ($null -ne $existing) {
        Write-Host "Replacing existing V7mdlImportSQLite module..."
        $vbProject.VBComponents.Remove($existing)
    }

    $null = $vbProject.VBComponents.Import($resolvedModule)
    $access.DoCmd.Save(5, "V7mdlImportSQLite")  # acModule = 5
    Write-Host "[OK] Imported V7mdlImportSQLite into $resolvedAccdb" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps in VPro64:" -ForegroundColor Cyan
    Write-Host "  1. Open $resolvedAccdb in Microsoft Access (64-bit)."
    Write-Host "  2. Press Ctrl+G (VBA Immediate Window), type ImportSQLiteProject, and press Enter."
    Write-Host "  3. Choose any .db file exported from VPro 2.0 (Interchange -> VPro64)."
} catch {
    Write-Host ""
    Write-Host "[!] Automatic Access COM import did not complete: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "    (Microsoft Access blocks programmatic VBA edits unless 'Trust access to the VBA project object model' is enabled.)"
    Write-Host ""
    Write-Host "Manual 20-second import in Microsoft Access:" -ForegroundColor Cyan
    Write-Host "  1. Open $resolvedAccdb in Microsoft Access."
    Write-Host "  2. Press Alt+F11 to open the VBA Editor."
    Write-Host "  3. Click File -> Import File... and choose:"
    Write-Host "       $resolvedModule"
    Write-Host "  4. Click Debug -> Compile, press Ctrl+S to save, then run ImportSQLiteProject from Ctrl+G."
    exit 1
} finally {
    if ($null -ne $access) {
        try { $access.CloseCurrentDatabase() } catch {}
        try { $access.Quit() } catch {}
        try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($access) } catch {}
    }
}
