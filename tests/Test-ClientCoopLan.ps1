param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [ValidateRange(2,3)][int]$ClientPlayers = 2,
    [ValidateRange(1,2)][int]$HostPlayers = 1,
    [string]$Godot = 'D:\GodotSteam\godotsteam.36.editor.windows.64.exe'
)
$ErrorActionPreference = 'Stop'
if ($HostPlayers + $ClientPlayers -gt 4) { throw 'The room supports at most four players.' }
$project = (Resolve-Path -LiteralPath $ProjectPath).Path
$repo = Split-Path -Parent $PSScriptRoot
$output = Join-Path (Split-Path -Parent $project) ('logs\client-local-coop-lan\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Force -Path $output | Out-Null
$sourceFiles = @(Get-ChildItem (Join-Path $repo 'scripts'), (Join-Path $repo 'extensions') -Filter '*.gd' -Recurse -File | ForEach-Object { $_.FullName.Substring($repo.Length + 1) }) + @('tests/client_coop_lan.gd', 'tests/client_coop_lan.tscn')
foreach ($file in $sourceFiles) {
    $hash = (Get-FileHash -LiteralPath (Join-Path $repo $file)).Hash
    if ($hash -ne (Get-FileHash -LiteralPath (Join-Path $project "mods-unpacked/wushuangabao-BrotatoOnlineFriends/$file")).Hash) { throw "Deploy current $file first." }
    "$file SHA256=$hash" | Add-Content (Join-Path $output 'source.txt')
}
$modList = @{}
foreach ($manifestFile in Get-ChildItem -LiteralPath (Join-Path $project 'mods-unpacked') -Filter manifest.json -Recurse -File) {
    $manifest = Get-Content -LiteralPath $manifestFile.FullName -Raw | ConvertFrom-Json
    $modId = "$($manifest.namespace)-$($manifest.name)"
    $modList[$modId] = @{ is_active = ($modId -eq 'wushuangabao-BrotatoOnlineFriends'); zip_path = '' }
}
$previous = @{}
foreach ($key in @('APPDATA', 'BROTATO_TEST_ROLE', 'BROTATO_TEST_DIR', 'BROTATO_TEST_CLIENT_PLAYERS', 'BROTATO_TEST_HOST_PLAYERS')) { $previous[$key] = [Environment]::GetEnvironmentVariable($key, 'Process') }
$processes = @{}
try {
    foreach ($role in @('host', 'client')) {
        $data = Join-Path $output $role
        New-Item -ItemType Directory -Force -Path "$data\Brotato\logs" | Out-Null
        @{ current_profile = 'default'; profiles = @{ default = @{ mod_list = $modList } } } | ConvertTo-Json -Depth 8 | Set-Content "$data\Brotato\mod_user_profiles.json" -Encoding utf8
        $env:APPDATA = $data
        $env:BROTATO_TEST_ROLE = $role
        $env:BROTATO_TEST_CLIENT_PLAYERS = [string]$ClientPlayers
        $env:BROTATO_TEST_HOST_PLAYERS = [string]$HostPlayers
        $env:BROTATO_TEST_DIR = $output
        $arguments = '--path "{0}" --no-window --audio-driver Dummy res://mods-unpacked/wushuangabao-BrotatoOnlineFriends/tests/client_coop_lan.tscn' -f $project
        $processes[$role] = Start-Process $Godot -ArgumentList $arguments -WorkingDirectory $project -WindowStyle Hidden -PassThru -RedirectStandardOutput "$output\$role.stdout.log" -RedirectStandardError "$output\$role.stderr.log"
    }
} catch {
    foreach ($process in $processes.Values) {
        if (-not $process.HasExited) { $process.Kill(); $process.WaitForExit() }
    }
    throw
} finally {
    foreach ($key in $previous.Keys) { [Environment]::SetEnvironmentVariable($key, $previous[$key], 'Process') }
}
try {
    $deadline = [DateTime]::UtcNow.AddSeconds(180)
    while (@($processes.Values | Where-Object { -not $_.HasExited }).Count -gt 0 -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 200 }
    foreach ($role in @('host', 'client')) {
        $process = $processes[$role]
        if (-not $process.HasExited) { throw "LAN test timed out: $output" }
        $lines = Get-Content "$output\$role.stdout.log" | Select-String 'CLIENT_COOP_LAN_'
        $lines
        if ($process.ExitCode -ne 0 -or -not ($lines -match "CLIENT_COOP_LAN_RESULT: $role PASS") -or (Select-String "$output\$role.stderr.log" -Pattern 'SCRIPT ERROR:|CLIENT_COOP_LAN_FAIL:' -Quiet)) { throw "LAN regression failed: $output" }
    }
    Write-Output "Evidence: $output"
} finally {
    foreach ($process in $processes.Values) {
        if (-not $process.HasExited) { $process.Kill(); $process.WaitForExit() }
    }
}
