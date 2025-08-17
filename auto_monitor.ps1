# Automatic iOS Build Monitor - Checks every 2 minutes
param(
    [int]$MaxChecks = 15,  # Maximum 30 minutes of monitoring
    [int]$IntervalSeconds = 120  # 2 minutes between checks
)

$checkCount = 0
$startTime = Get-Date

Write-Host "🤖 AUTO-MONITOR STARTED" -ForegroundColor Green
Write-Host "Repository: void7775/var6" -ForegroundColor Yellow
Write-Host "Checking every 2 minutes for up to 30 minutes" -ForegroundColor Cyan
Write-Host "Start time: $($startTime.ToString('HH:mm:ss'))" -ForegroundColor Gray
Write-Host "=" * 50 -ForegroundColor Gray

# Function to check and display status
function Show-BuildStatus {
    param([int]$CheckNumber)
    
    $currentTime = Get-Date
    $elapsed = $currentTime - $startTime
    
    Write-Host ""
    Write-Host "🔍 CHECK #$CheckNumber - $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Blue
    Write-Host "⏱️ Elapsed: $($elapsed.ToString('mm\:ss'))" -ForegroundColor Gray
    
    # Open GitHub Actions (will refresh if already open)
    Start-Process "https://github.com/void7775/var6/actions" -WindowStyle Minimized
    
    Write-Host "Expected build status:" -ForegroundColor Yellow
    if ($elapsed.TotalMinutes -lt 5) {
        Write-Host "  🟡 Should be: Setting up Flutter & dependencies" -ForegroundColor Yellow
    } elseif ($elapsed.TotalMinutes -lt 8) {
        Write-Host "  🟡 Should be: Running tests & analysis" -ForegroundColor Yellow
    } elseif ($elapsed.TotalMinutes -lt 12) {
        Write-Host "  🟡 Should be: Building iOS app" -ForegroundColor Yellow
    } elseif ($elapsed.TotalMinutes -lt 15) {
        Write-Host "  🟡 Should be: Packaging artifacts" -ForegroundColor Yellow
    } else {
        Write-Host "  ✅ Should be: COMPLETED or ❌ FAILED" -ForegroundColor Green
    }
    
    Write-Host "👀 Check GitHub Actions tab for real-time status" -ForegroundColor Cyan
    Write-Host "-" * 40 -ForegroundColor Gray
}

# Main monitoring loop
while ($checkCount -lt $MaxChecks) {
    $checkCount++
    
    Show-BuildStatus -CheckNumber $checkCount
    
    if ($checkCount -lt $MaxChecks) {
        Write-Host "⏳ Waiting 2 minutes for next check..." -ForegroundColor Magenta
        Start-Sleep -Seconds $IntervalSeconds
    }
}

Write-Host ""
Write-Host "🏁 MONITORING COMPLETE" -ForegroundColor Green
Write-Host "Total time: $((Get-Date) - $startTime | ForEach-Object {$_.ToString('mm\:ss')})" -ForegroundColor Yellow
Write-Host "Final check: https://github.com/void7775/var6/actions" -ForegroundColor Cyan
Start-Process "https://github.com/void7775/var6/actions"
