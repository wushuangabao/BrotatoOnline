param(
    [Parameter(Mandatory=$true)][string]$OnlinePackage,
    [string]$Runner='E:/github/BrotatoMod/work/friends-equipment-effects-20261111/runner'
)
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$game=(Resolve-Path "$Runner/common/Brotato/Brotato.exe").Path
foreach($p in @(Get-Process -Name Brotato -ErrorAction SilentlyContinue)) {
    if (-not $p.Path -or $p.Path -eq $game) { throw 'Test runner is active; cannot replace mounted packages.' }
}
$output=Join-Path (Split-Path -Parent $repo) ('friends-equipment-effects-20261111/meca-retail-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $output -Force | Out-Null
python "$PSScriptRoot/prepare_equipment_probe.py" $Runner $OnlinePackage $output
if($LASTEXITCODE -ne 0){throw 'Probe preparation failed'}
python "$PSScriptRoot/prepare_meca_retail_probe.py" $Runner $output
if($LASTEXITCODE -ne 0){throw 'Meca probe preparation failed'}
$previous=@{}
foreach($key in @('APPDATA','BROTATO_TEST_ROLE','BROTATO_TEST_DIR','BROTATO_TEST_PORT')){$previous[$key]=[Environment]::GetEnvironmentVariable($key,'Process')}
$udp=[Net.Sockets.UdpClient]::new(0)
$port=$udp.Client.LocalEndPoint.Port
$udp.Dispose()
$processes=@{}
Write-Output "Evidence: $output"
try {
    $env:BROTATO_TEST_PORT=[string]$port
    $env:BROTATO_TEST_DIR=$output
    foreach($role in @('host','client')) {
        $env:BROTATO_TEST_ROLE=$role
        $env:APPDATA="$output/$role-userdata"
        New-Item -ItemType Directory -Force -Path "$env:APPDATA/Brotato/logs" | Out-Null
        $processes[$role]=Start-Process $game -ArgumentList '--enable-mods --no-window --audio-driver Dummy' -WorkingDirectory (Split-Path $game) -WindowStyle Hidden -PassThru -RedirectStandardOutput "$output/$role.stdout.log" -RedirectStandardError "$output/$role.stderr.log"
    }
    $deadline=[DateTime]::UtcNow.AddSeconds(180)
    while (@($processes.Values | Where-Object { -not $_.HasExited }).Count -gt 0 -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 200 }
    foreach($role in @('host','client')) {
        $p=$processes[$role]
        if(-not $p.HasExited){throw "Meca retail timeout: $role"}
        $lines=Get-Content "$output/$role.stdout.log" | Select-String 'MECA_UPGRADE_LAN_'
        $lines
        if($p.ExitCode -ne 0 -or -not ($lines -match "MECA_UPGRADE_LAN_RESULT: $role PASS") -or (Select-String "$output/$role.stderr.log" -Pattern 'SCRIPT ERROR:' -Quiet)){throw "Meca retail regression failed: $role"}
    }
} finally {
    foreach($p in $processes.Values){if(-not $p.HasExited){$p.Kill();$p.WaitForExit()}}
    foreach($key in $previous.Keys){[Environment]::SetEnvironmentVariable($key,$previous[$key],'Process')}
}
