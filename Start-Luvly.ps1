# Start the existing local API and check both demonstration endpoints.
# Does not create public tunnels, change billing, or alter security settings.
$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot
$backendRoot = Join-Path $projectRoot 'payment_backend'
$nodeExe = (Get-Command node -ErrorAction Stop).Source
$healthy = $false
try {
    $health = Invoke-RestMethod 'http://127.0.0.1:8787/health' -TimeoutSec 3
    $healthy = $health.environment -eq 'sandbox' -and $health.staffWorkspaceVersion -eq 1
} catch { }
if (-not $healthy) {
    $logRoot = Join-Path $projectRoot 'work/startup'
    New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $outLog = Join-Path $logRoot "$stamp.out.log"
    $errLog = Join-Path $logRoot "$stamp.err.log"
    $serverFile = Join-Path $backendRoot 'server.mjs'
    $backendProcess = Start-Process -FilePath $nodeExe -ArgumentList ('"' + $serverFile + '"') -WorkingDirectory $backendRoot -WindowStyle Hidden -RedirectStandardOutput $outLog -RedirectStandardError $errLog -PassThru
    for ($attempt = 0; $attempt -lt 20; $attempt++) {
        Start-Sleep -Milliseconds 500
        $backendProcess.Refresh()
        if ($backendProcess.HasExited) { break }
        try {
            $health = Invoke-RestMethod 'http://127.0.0.1:8787/health' -TimeoutSec 2
            if ($health.environment -eq 'sandbox' -and $health.staffWorkspaceVersion -eq 1) { $healthy = $true; break }
        } catch { }
    }
    if (-not $healthy) { throw "Backend did not become ready. Inspect $errLog locally; do not share secret files." }
    Write-Host "Local backend started (PID $($backendProcess.Id))."
} else { Write-Host 'Local backend is already running; reused it.' }
& $nodeExe (Join-Path $backendRoot 'check_readiness.mjs')
$result = $LASTEXITCODE
if ($result -ne 0) {
    Write-Host 'If Local portal fails, start the existing Flutter Chrome runner on port 5000.'
    Write-Host 'If Mobile public backend fails, the temporary tunnel needs recovery before the phone demonstration.'
}
exit $result
