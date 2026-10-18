# IBDMS — start Flutter web on port 8080 (safe to run multiple times).
$port = 8080
$frontendDir = $PSScriptRoot

Set-Location $frontendDir

# Check if Flutter is already serving on this port.
$listening = netstat -ano | Select-String ":$port\s+.*LISTENING"
foreach ($line in $listening) {
    $procId = ($line -split '\s+')[-1]
    if ($procId -match '^\d+$') {
        $proc = Get-Process -Id $procId -ErrorAction SilentlyContinue
        if ($proc -and $proc.ProcessName -eq 'dartvm') {
            Write-Host ""
            Write-Host "  Website is ALREADY running!" -ForegroundColor Green
            Write-Host "  Open: http://localhost:$port" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "  Do NOT run 'flutter run' again — that causes the port error." -ForegroundColor Yellow
            exit 0
        }
        if ($proc) {
            Write-Host "Stopping $($proc.ProcessName) (PID $procId) blocking port $port..."
            Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
        }
    }
}

Start-Sleep -Seconds 1

Write-Host ""
Write-Host "  Starting IBDMS website on http://localhost:$port" -ForegroundColor Cyan
Write-Host "  First build may take 1-2 minutes. After that, page loads fast." -ForegroundColor Gray
Write-Host ""

flutter run -d chrome --web-port $port --release
