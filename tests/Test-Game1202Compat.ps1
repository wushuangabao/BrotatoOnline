param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [Parameter(Mandatory = $true)][string]$Godot
)
$ErrorActionPreference = 'Stop'
$project = (Resolve-Path -LiteralPath $ProjectPath).Path
$repo = Split-Path -Parent $PSScriptRoot
$output = Join-Path (Split-Path -Parent $project) ('logs/game-1202-compat/' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Force "$output/userdata/Brotato/logs" | Out-Null
$files = @('scripts/menu_sync_manager.gd', 'scripts/protocol.gd', 'extensions/main_safe_pool_exit.gd', 'tests/game_1202_compat.gd', 'tests/game_1202_compat_manager.gd', 'tests/game_1202_compat.tscn')
foreach ($file in $files) {
    $hash = (Get-FileHash -LiteralPath (Join-Path $repo $file)).Hash
    if ($hash -ne (Get-FileHash -LiteralPath (Join-Path $project "mods-unpacked/wushuangabao-BrotatoOnlineFriends/$file")).Hash) { throw "Deploy current $file first." }
    "$file SHA256=$hash" | Add-Content "$output/source.txt"
}
$mods = @{}
foreach ($dir in Get-ChildItem "$project/mods-unpacked" -Directory) {
    $mods[$dir.Name] = @{ is_active = ($dir.Name -eq 'wushuangabao-BrotatoOnlineFriends'); zip_path = '' }
}
@{current_profile='default';profiles=@{default=@{mod_list=$mods}}} | ConvertTo-Json -Depth 8 | Set-Content "$output/userdata/Brotato/mod_user_profiles.json"
$previous = @{}
foreach ($key in @('APPDATA','BROTATO_TEST_DIR','SteamAppId')) { $previous[$key] = [Environment]::GetEnvironmentVariable($key, 'Process') }
$process = $null
try {
    $env:APPDATA = "$output/userdata"
    $env:BROTATO_TEST_DIR = $output
    $env:SteamAppId = '1942280'
    $arguments = '--path "{0}" --no-window --audio-driver Dummy res://mods-unpacked/wushuangabao-BrotatoOnlineFriends/tests/game_1202_compat.tscn' -f $project
    $process = Start-Process $Godot -WorkingDirectory $project -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput "$output/stdout.log" -RedirectStandardError "$output/stderr.log"
    Write-Output "Evidence: $output"
    if (-not $process.WaitForExit(120000)) { throw 'Game 1.2.0.2 regression timed out' }
    $process.WaitForExit()
    $process.Refresh()
    $lines = Get-Content "$output/stdout.log" | Select-String 'GAME_1202_'
    $lines
    if ($process.ExitCode -ne 0 -or -not ($lines -match 'GAME_1202_RESULT: \d+ checks, 0 failures') -or (Select-String "$output/stderr.log" -Pattern 'SCRIPT ERROR:' -Quiet)) { throw "Game 1.2.0.2 regression failed: $output" }
} finally {
    foreach ($key in $previous.Keys) { [Environment]::SetEnvironmentVariable($key, $previous[$key], 'Process') }
    if ($process -and -not $process.HasExited) { $process.Kill(); $process.WaitForExit() }
}
