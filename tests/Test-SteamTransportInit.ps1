param([string]$Godot = 'D:\GodotSteam\godotsteam.36.editor.windows.64.exe')
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$workspace = Split-Path -Parent (Split-Path -Parent $repo)
$output = Join-Path $workspace ('logs\steam-transport-init\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
$mod = Join-Path $output 'mods-unpacked\wushuangabao-BrotatoOnlineFriends'
New-Item -ItemType Directory -Force -Path (Join-Path $mod 'scripts') | Out-Null
[IO.File]::WriteAllText((Join-Path $output 'project.godot'), 'config_version=4')
Copy-Item -LiteralPath (Join-Path $repo 'scripts\steam_transport.gd') -Destination (Join-Path $mod 'scripts\steam_transport.gd')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'steam_transport_init.gd') -Destination (Join-Path $output 'test.gd')
Get-FileHash -LiteralPath (Join-Path $mod 'scripts\steam_transport.gd'), (Join-Path $output 'test.gd') | Format-List | Out-File (Join-Path $output 'source.txt')
$arguments = '--path "{0}" --no-window --audio-driver Dummy --script test.gd' -f $output
$process = Start-Process $Godot -ArgumentList $arguments -WorkingDirectory $output -WindowStyle Hidden -PassThru -RedirectStandardOutput "$output\stdout.log" -RedirectStandardError "$output\stderr.log"
try {
    if (-not $process.WaitForExit(30000)) { throw "Steam initialization regression timed out: $output" }
    $process.Refresh()
    $result = Get-Content "$output\stdout.log"
    $result | Select-String 'STEAM_INIT_'
    if ($process.ExitCode -ne 0 -or -not ($result -match 'STEAM_INIT_RESULT: 10 checks, 0 failures') -or (Select-String "$output\stderr.log" -Pattern 'SCRIPT ERROR:' -Quiet)) { throw "Steam initialization regression failed: $output" }
    Write-Output "Evidence: $output"
} finally {
    if (-not $process.HasExited) { $process.Kill(); $process.WaitForExit() }
}
