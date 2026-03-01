param()

$ErrorActionPreference = "Stop"
try {
    # Ensure correct encoding for console output
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
} catch {}

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptPath
$binPath = Join-Path $projectRoot "bin"
$listsPath = Join-Path $projectRoot "lists"
$winwsPath = Join-Path $binPath "winws.exe"

function Write-Color ($text, $color) {
    Write-Host $text -ForegroundColor $color
}

Write-Color "=========================================" "Cyan"
Write-Color "   ZAPRET SMART STRATEGY ORCHESTRATOR   " "Cyan"
Write-Color "=========================================" "Cyan"
Write-Host "This tool will automatically test different DPI bypass strategies"
Write-Host "to find the best configuration for your ISP and network."
Write-Host ""
Write-Host "Please ensure you have closed Discord, YouTube, etc. before starting."
Write-Host ""

# 1. Prepare Environment
Write-Color "[*] Preparing environment..." "Yellow"

# Stop existing services/processes
$conflictingServices = @("zapret", "WinDivert", "GoodbyeDPI", "winws1", "winws2")
foreach ($svc in $conflictingServices) {
    if (Get-Service -Name $svc -ErrorAction SilentlyContinue) {
        Write-Host "Stopping service: $svc"
        Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
    }
}

$winwsProcs = Get-Process -Name "winws" -ErrorAction SilentlyContinue
if ($winwsProcs) {
    Write-Host "Stopping existing winws.exe processes..."
    $winwsProcs | Stop-Process -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 1

# List of sites to test
$TestUrls = @(
    "https://discord.com",
    "https://twitter.com",
    "https://www.instagram.com",
    "https://chatgpt.com"
)

# Test function
function Test-Connectivity {
    $success = 0
    $totalTimeMs = 0
    
    foreach ($url in $TestUrls) {
        try {
            # Use basic parsing and short timeout to quickly fail if DPI blocking is active
            $sw = [Diagnostics.Stopwatch]::StartNew()
            $request = Invoke-WebRequest -Uri $url -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop
            $sw.Stop()
            
            if ($request.StatusCode -ge 200 -and $request.StatusCode -lt 400) {
                # Success
                $success++
                $totalTimeMs += $sw.ElapsedMilliseconds
            }
        } catch {
            # Failed (likely DPI block or timeout)
        }
    }
    
    return @{
        SuccessRate = ($success / $TestUrls.Count) * 100
        AvgPing = if ($success -gt 0) { [math]::Round($totalTimeMs / $success) } else { 9999 }
    }
}

# Baseline Check
Write-Color "[*] Checking baseline connectivity without bypass..." "Yellow"
$baseline = Test-Connectivity
Write-Host "Baseline Success Rate: $($baseline.SuccessRate)%"
Write-Host "Baseline average ping: $($baseline.AvgPing)ms"

if ($baseline.SuccessRate -eq 100) {
    Write-Color "WARNING: All test sites are reachable without any bypass!" "Magenta"
    Write-Color "You might not need Zapret, or your ISP isn't fully blocking them yet." "Magenta"
    Write-Host "Continuing anyway to find fastest bypass configuration..."
}
Write-Host ""

# Strategy Definitions
# Based on common successful zapret arguments
$Strategies = @(
    @{
        Name = "Standard (Fake Split)"
        Args = "--wf-tcp=80,443 --filter-tcp=80,443 --dpi-desync=fake,split --dpi-desync-repeats=6 --dpi-desync-split-pos=1 --dpi-desync-fake-quic=`"$($binPath)\quic_initial_www_google_com.bin`" --new"
    },
    @{
        Name = "Disorder2 + Multisplit"
        Args = "--wf-tcp=80,443,8443 --filter-tcp=80,443,8443 --dpi-desync=disorder2,multisplit --dpi-desync-split-seqovl=568 --dpi-desync-split-pos=1 --dpi-desync-split-seqovl-pattern=`"$($binPath)\tls_clienthello_4pda_to.bin`" --new"
    },
    @{
        Name = "Syndata Aggressive"
        Args = "--wf-tcp=443 --filter-tcp=443 --dpi-desync=syndata,multisplit --dpi-desync-split-seqovl=681 --dpi-desync-split-pos=1 --dpi-desync-split-seqovl-pattern=`"$($binPath)\tls_clienthello_www_google_com.bin`" --new"
    },
    @{
        Name = "Multi-Protocol Hybrid (TCP+UDP Fake)"
        Args = "--wf-tcp=80,443,8443 --wf-udp=443 --filter-udp=443 --dpi-desync=fake --dpi-desync-repeats=11 --dpi-desync-fake-quic=`"$($binPath)\quic_initial_www_google_com.bin`" --new --filter-tcp=80,443,8443 --dpi-desync=fake,multisplit --dpi-desync-split-pos=1 --new"
    },
    @{
        Name = "ULTIMA Clone"
        Args = "--wf-tcp=80,443,2053,2083,2087,2096,8443 --filter-tcp=443 --dpi-desync=syndata,multisplit --dpi-desync-split-seqovl=681 --dpi-desync-split-pos=1 --dpi-desync-split-seqovl-pattern=`"$($binPath)\tls_clienthello_www_google_com.bin`" --new --filter-tcp=80,443 --dpi-desync=disorder2 --dpi-desync-split-seqovl=568 --dpi-desync-split-pos=1 --dpi-desync-split-seqovl-pattern=`"$($binPath)\tls_clienthello_4pda_to.bin`" --new"
    }
)

Write-Color "[*] Starting Strategy Testing Phase..." "Green"
Write-Host "Total strategies to test: $($Strategies.Count)"
Write-Host ""

$Results = @()

foreach ($strat in $Strategies) {
    Write-Color "-> Testing Strategy: $($strat.Name)" "Cyan"
    
    # Base arguments that all strategies should likely have for compatibility
    $baseArgs = "--hostlist=`"$($listsPath)\list-general.txt`" --hostlist=`"$($listsPath)\list-general-user.txt`" --hostlist-exclude=`"$($listsPath)\list-exclude.txt`" --hostlist-exclude=`"$($listsPath)\list-exclude-user.txt`""
    $fullArgs = "$($strat.Args) $baseArgs"

    # Start winws process hidden
    $processInfo = New-Object System.Diagnostics.ProcessStartInfo
    $processInfo.FileName = $winwsPath
    $processInfo.Arguments = $fullArgs
    $processInfo.CreateNoWindow = $true
    $processInfo.UseShellExecute = $false
    
    $process = [System.Diagnostics.Process]::Start($processInfo)
    
    # Wait for driver to init
    Start-Sleep -Seconds 2
    
    if (-not $process.HasExited) {
        $result = Test-Connectivity
        Write-Host "   Success Rate: $($result.SuccessRate)%"
        Write-Host "   Average Ping: $($result.AvgPing)ms"
        
        $Results += @{
            Name = $strat.Name
            Args = $strat.Args
            SuccessRate = $result.SuccessRate
            AvgPing = $result.AvgPing
        }
        
        # Stop process
        $process.Kill()
        $process.WaitForExit()
    } else {
        Write-Color "   [!] winws.exe crashed or failed to start with these parameters!" "Red"
    }
    
    Start-Sleep -Seconds 1
}

Write-Host ""
Write-Color "[*] Orchestrator Finished! Analyzing results..." "Green"

# Filter results for best
# Primary metric: SuccessRate > 0.
# Secondary metric: Highest SuccessRate.
# Tertiary metric: Lowest AvgPing.

$validResults = $Results | Where-Object { $_.SuccessRate -gt 0 }

if ($validResults.Count -eq 0) {
    Write-Color "[X] All strategies failed! Your ISP's DPI might be extremely aggressive." "Red"
    Write-Color "Please try manual tuning or check if Zapret is running properly." "Red"
    Read-Host "Press Enter to exit..."
    exit
}

$bestStrategy = $validResults | Sort-Object -Property @{Expression={$_.SuccessRate}; Descending=$true}, @{Expression={$_.AvgPing}; Descending=$false} | Select-Object -First 1

Write-Color "=========================================" "Cyan"
Write-Color " WINNER STRATEGY FOUND: $($bestStrategy.Name) " "Cyan"
Write-Color "=========================================" "Cyan"
Write-Host "Success Rate: $($bestStrategy.SuccessRate)%"
Write-Host "Average Ping: $($bestStrategy.AvgPing)ms"

# Generate Batch File
$outBatFile = Join-Path $projectRoot "general (AUTO_OPTIMIZED).bat"

$batContent = @"
@echo off
chcp 65001 > nul
:: 65001 - UTF-8
:: --- AUTO-GENERATED BY SMART STRATEGY ORCHESTRATOR ---
:: Generated on: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
:: Strategy Name: $($bestStrategy.Name)
:: Performance: $($bestStrategy.SuccessRate)% success rate, $($bestStrategy.AvgPing)ms avg ping

cd /d "%~dp0"
call service.bat status_zapret
call service.bat check_updates
call service.bat load_game_filter
call service.bat load_user_lists
echo:

set "BIN=%~dp0bin\"
set "LISTS=%~dp0lists\"
cd /d %BIN%

:: Ensure UDP proxy for discord/games is also appended if needed
set "BASE_UDP=--wf-udp=443,19294-19344,50000-50100,%GameFilterUDP% --filter-udp=443 --dpi-desync=fake --dpi-desync-repeats=11 --dpi-desync-fake-quic=`"%BIN%quic_initial_www_google_com.bin`" --new"
set "DISCORD_UDP=--filter-udp=19294-19344,50000-50100 --filter-l7=discord,stun --dpi-desync=fake --dpi-desync-repeats=11 --new"

:: Applying best WINNER strategy parameters...
start "zapret: %~n0" /min "%BIN%winws.exe" $($bestStrategy.Args) --hostlist="%LISTS%list-general.txt" --hostlist="%LISTS%list-general-user.txt" --hostlist-exclude="%LISTS%list-exclude.txt" --hostlist-exclude="%LISTS%list-exclude-user.txt" --ipset-exclude="%LISTS%ipset-exclude.txt" --ipset-exclude="%LISTS%ipset-exclude-user.txt" %BASE_UDP% %DISCORD_UDP%
"@

try {
    [System.IO.File]::WriteAllText($outBatFile, $batContent)
    Write-Host ""
    Write-Color "[V] Automatically created new launcher profile!" "Green"
    Write-Color "File saved as: $outBatFile" "Green"
    Write-Host "You can now run 'general (AUTO_OPTIMIZED).bat' from the main folder."
} catch {
    Write-Color "Failed to save the batch file. Error: $($_.Exception.Message)" "Red"
}

Write-Host ""
Read-Host "Press Enter to return to the menu..."
