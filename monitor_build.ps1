# Monitor GitHub Actions Build Status
Write-Host "🚀 Monitoring Var6 iOS Build Status..." -ForegroundColor Green
Write-Host "Repository: void7775/var6" -ForegroundColor Yellow
Write-Host "Checking: https://github.com/void7775/var6/actions" -ForegroundColor Cyan
Write-Host ""

# Function to check build status
function Check-BuildStatus {
    Write-Host "⏱️ Build Status Check - $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Blue
    Write-Host "Expected build time: 10-15 minutes" -ForegroundColor Gray
    Write-Host "Build includes:" -ForegroundColor Gray
    Write-Host "  ✅ Flutter setup and dependencies" -ForegroundColor Gray
    Write-Host "  ✅ Code analysis" -ForegroundColor Gray
    Write-Host "  ✅ Widget tests" -ForegroundColor Gray
    Write-Host "  📱 iOS compilation (no code signing)" -ForegroundColor Gray
    Write-Host "  📦 Artifact packaging" -ForegroundColor Gray
    Write-Host ""
}

# Initial check
Check-BuildStatus

Write-Host "🔗 Opening GitHub Actions..." -ForegroundColor Green
Start-Process "https://github.com/void7775/var6/actions"

Write-Host ""
Write-Host "📋 Build Status Legend:" -ForegroundColor Yellow
Write-Host "  🟡 Yellow circle = Build running" -ForegroundColor Yellow
Write-Host "  ✅ Green check = Build successful" -ForegroundColor Green
Write-Host "  ❌ Red X = Build failed (we'll fix it!)" -ForegroundColor Red
Write-Host "  ⏸️ Gray circle = Build queued" -ForegroundColor Gray
Write-Host ""
Write-Host "💡 Tip: Refresh the page to see latest status" -ForegroundColor Cyan
