param()
$ErrorActionPreference = "Stop"

try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
} catch {}

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptPath

Write-Host "===========================" -ForegroundColor Cyan
Write-Host "   AUTO-UPDATING ZAPRET" -ForegroundColor Cyan
Write-Host "===========================" -ForegroundColor Cyan
Write-Host "Checking for .git directory..."

if (Test-Path (Join-Path $projectRoot ".git")) {
    Write-Host "[*] Git repository detected! Updating using 'git pull'..." -ForegroundColor Yellow
    Set-Location -Path $projectRoot
    try {
        git pull origin main
        Write-Host "[V] Update completed successfully via Git." -ForegroundColor Green
    } catch {
        Write-Host "[X] Git pull failed." -ForegroundColor Red
        Read-Host "Press Enter to continue..."
    }
} else {
    Write-Host "[*] No Git repository found. Downloading standard zip package..." -ForegroundColor Yellow
    $zipUrl = "https://github.com/ssbaxys/Vladpret/archive/refs/heads/main.zip"
    $zipPath = Join-Path $env:TEMP "Vladpret_update.zip"
    $extractPath = Join-Path $env:TEMP "Vladpret_update_extracted"

    try {
        Write-Host "Downloading latest version..."
        Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing
        
        Write-Host "Extracting files..."
        if (Test-Path $extractPath) { Remove-Item -Path $extractPath -Recurse -Force }
        Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force
        
        Write-Host "Copying new files to your folder..."
        $sourceDir = Join-Path $extractPath "Vladpret-main"
        if (Test-Path $sourceDir) {
            # Attempt to close zapret before overwriting
            $svc = Get-Service -Name "zapret" -ErrorAction SilentlyContinue
            if ($svc -and $svc.Status -eq 'Running') {
                Stop-Service -Name "zapret" -Force -ErrorAction SilentlyContinue
            }
            Get-Process -Name "winws" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            
            Copy-Item -Path "$sourceDir\*" -Destination $projectRoot -Recurse -Force
            Write-Host "[V] Files successfully updated!" -ForegroundColor Green
        } else {
            Write-Host "[X] Error: Could not find extracted folder." -ForegroundColor Red
        }
    } catch {
        Write-Host "[X] Update failed: $($_.Exception.Message)" -ForegroundColor Red
    } finally {
        # Cleanup
        if (Test-Path $zipPath) { Remove-Item -Path $zipPath -Force }
        if (Test-Path $extractPath) { Remove-Item -Path $extractPath -Recurse -Force }
    }
}

Write-Host ""
Write-Host "Update script finished."
Write-Host "Please restart service.bat to use the new version."
Write-Host ""
Read-Host "Press Enter to exit updater..."
