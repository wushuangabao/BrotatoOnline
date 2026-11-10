param(
    [ValidateSet('cat','hiker','tracking','multi')][string]$Case='cat',
    [Parameter(Mandatory=$true)][string]$OnlinePackage,
    [string]$Runner='E:/github/BrotatoMod/work/NoobsWantToLive-retail',
    [string]$Label='movement',
    [switch]$HardRejoin,
    [switch]$WaitRejoin
)
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$game=(Resolve-Path "$Runner/common/Brotato/Brotato.exe").Path
foreach($p in @(Get-Process -Name Brotato -ErrorAction SilentlyContinue)) {
    if (-not $p.Path -or $p.Path -eq $game) { throw 'Test runner is active; cannot replace mounted packages.' }
}
$output=Join-Path (Split-Path -Parent $repo) ('movement-rewards-evidence/'+$Label+'-'+$Case+'-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $output -Force | Out-Null
python "$PSScriptRoot/prepare_movement_probe.py" $Runner $OnlinePackage $output
if($LASTEXITCODE -ne 0){throw 'Probe preparation failed'}
$previous=@{}
foreach($key in @('APPDATA','BROTATO_TEST_ROLE','BROTATO_TEST_DIR','BROTATO_TEST_PORT','BROTATO_TEST_CHARACTER')){$previous[$key]=[Environment]::GetEnvironmentVariable($key,'Process')}
$udp=[Net.Sockets.UdpClient]::new(0)
$port=$udp.Client.LocalEndPoint.Port
$udp.Dispose()
$processes=@{}
Write-Output "Evidence: $output"
try {
    $env:BROTATO_TEST_PORT=[string]$port
    $env:BROTATO_TEST_DIR=$output
    $env:BROTATO_TEST_CHARACTER=switch($Case){'hiker' {'character_hiker'} 'multi' {'character_hiker'} 'tracking' {'character_wushuangabao_nwtl_wang_ye_xiang'} default {'character_wushuangabao_nwtl_an_mao'}}
    foreach($role in @('host','client')) {
        $env:BROTATO_TEST_ROLE=$role
        $env:APPDATA="$output/$role-userdata"
        New-Item -ItemType Directory -Force -Path "$env:APPDATA/Brotato/logs" | Out-Null
        $processes[$role]=Start-Process $game -ArgumentList '--enable-mods --no-window --audio-driver Dummy' -WorkingDirectory (Split-Path $game) -WindowStyle Hidden -PassThru -RedirectStandardOutput "$output/$role.stdout.log" -RedirectStandardError "$output/$role.stderr.log"
    }
    $driver=switch($Case){'hiker' {'test_hiker_rewards_lan.py'} 'multi' {'test_movement_multi_lan.py'} 'tracking' {'test_damage_tracking_lan.py'} default {'test_movement_rewards_lan.py'}}
    if($WaitRejoin){python "$PSScriptRoot/$driver" $output --delay-settlement --luck-gains --hard-rejoin --wait-rejoin}
    elseif($HardRejoin){python "$PSScriptRoot/$driver" $output --delay-settlement --luck-gains --hard-rejoin}
    else{python "$PSScriptRoot/$driver" $output --delay-settlement --luck-gains}
    if($LASTEXITCODE -ne 0){throw "Runtime assertions failed: $output"}
    foreach($role in @('host','client')){
        if(-not $processes[$role].WaitForExit(10000)){throw "Process did not exit: $role"}
        if($processes[$role].ExitCode -ne 0 -or (Select-String "$output/$role.stderr.log" -Pattern 'SCRIPT ERROR:' -Quiet)){throw "Runtime script failure: $role"}
    }
} finally {
    foreach($p in $processes.Values){if(-not $p.HasExited){$p.Kill();$p.WaitForExit()}}
    foreach($key in $previous.Keys){[Environment]::SetEnvironmentVariable($key,$previous[$key],'Process')}
}
