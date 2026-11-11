param(
    [Parameter(Mandatory=$true)][string]$OnlinePackage,
    [string]$Runner='E:/github/BrotatoMod/work/friends-equipment-effects-20261111/runner',
    [string]$Label='equipment',
    [ValidateSet("xiao_tian_cai","streamer")][string]$Character="xiao_tian_cai",
    [int]$Wave=1,
    [ValidateSet("equipment","lifecycle")][string]$Suite="equipment"
)
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$game=(Resolve-Path "$Runner/common/Brotato/Brotato.exe").Path
foreach($p in @(Get-Process -Name Brotato -ErrorAction SilentlyContinue)) {
    if (-not $p.Path -or $p.Path -eq $game) { throw 'Test runner is active; cannot replace mounted packages.' }
}
$output=Join-Path (Split-Path -Parent $repo) ('friends-equipment-effects-20261111/'+$Label+'-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $output -Force | Out-Null
python "$PSScriptRoot/prepare_equipment_probe.py" $Runner $OnlinePackage $output
if($LASTEXITCODE -ne 0){throw 'Probe preparation failed'}
$previous=@{}
foreach($key in @('APPDATA','BROTATO_TEST_ROLE','BROTATO_TEST_DIR','BROTATO_TEST_PORT','BROTATO_TEST_CHARACTER','BROTATO_TEST_WAVE','BROTATO_TEST_SUITE')){$previous[$key]=[Environment]::GetEnvironmentVariable($key,'Process')}
$udp=[Net.Sockets.UdpClient]::new(0)
$port=$udp.Client.LocalEndPoint.Port
$udp.Dispose()
$processes=@{}
Write-Output "Evidence: $output"
try {
    $env:BROTATO_TEST_PORT=[string]$port
    $env:BROTATO_TEST_DIR=$output
    $env:BROTATO_TEST_CHARACTER=$Character
    $env:BROTATO_TEST_WAVE=[string]$Wave
    $env:BROTATO_TEST_SUITE=$Suite
    foreach($role in @('host','client')) {
        $env:BROTATO_TEST_ROLE=$role
        $env:APPDATA="$output/$role-userdata"
        New-Item -ItemType Directory -Force -Path "$env:APPDATA/Brotato/logs" | Out-Null
        $processes[$role]=Start-Process $game -ArgumentList '--enable-mods --no-window --audio-driver Dummy' -WorkingDirectory (Split-Path $game) -WindowStyle Hidden -PassThru -RedirectStandardOutput "$output/$role.stdout.log" -RedirectStandardError "$output/$role.stderr.log"
    }
    if($Suite -eq "lifecycle"){python "$PSScriptRoot/test_effect_lifecycle_lan.py" $output}
    else{python "$PSScriptRoot/test_equipment_effects_lan.py" $output}
    if($LASTEXITCODE -ne 0){throw "Runtime assertions failed: $output"}
    foreach($role in @('host','client')){
        if(-not $processes[$role].WaitForExit(10000)){throw "Process did not exit: $role"}
        if($processes[$role].ExitCode -ne 0 -or (Select-String "$output/$role.stderr.log" -Pattern 'SCRIPT ERROR:' -Quiet)){throw "Runtime script failure: $role"}
    }
} finally {
    foreach($p in $processes.Values){if(-not $p.HasExited){$p.Kill();$p.WaitForExit()}}
    foreach($key in $previous.Keys){[Environment]::SetEnvironmentVariable($key,$previous[$key],'Process')}
}
