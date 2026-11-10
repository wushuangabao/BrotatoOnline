param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [Parameter(Mandatory = $true)][string]$Godot,
    [ValidateSet('single','three','pads','keyboard','late_keyboard')][string]$Case = 'single',
    [string]$BaselineArchive = ''
)
$ErrorActionPreference = 'Stop'
$project = (Resolve-Path -LiteralPath $ProjectPath).Path
$repo = Split-Path -Parent $PSScriptRoot
$output = Join-Path $project ('evidence/selection-' + $Case + '-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $output -Force | Out-Null
$baselineHashes = @{}
if ($BaselineArchive) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $BaselineArchive).Path)
    try {
        foreach ($entry in $zip.Entries) {
            if (-not $entry.FullName.EndsWith('.gd')) { continue }
            $stream = $entry.Open()
            $sha = [System.Security.Cryptography.SHA256]::Create()
            try { $baselineHashes[$entry.FullName.Replace('/', '\')] = [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-', '') } finally { $stream.Dispose(); $sha.Dispose() }
        }
    } finally { $zip.Dispose() }
    "Baseline SHA256=$((Get-FileHash -LiteralPath $BaselineArchive).Hash)" | Add-Content (Join-Path $output 'source.txt')
}
$sourceFiles = @(Get-ChildItem (Join-Path $repo 'scripts'), (Join-Path $repo 'extensions') -Filter '*.gd' -Recurse -File | ForEach-Object { $_.FullName.Substring($repo.Length + 1) }) + @('mod_main.gd','tests/selection_input.gd','tests/selection_input.tscn','tests/selection_input_lan.gd','tests/selection_input_lan.tscn')
foreach ($file in $sourceFiles) {
    $hash = (Get-FileHash -LiteralPath (Join-Path $repo $file)).Hash
    $baselineKey = "mods-unpacked/wushuangabao-BrotatoOnlineFriends/$file".Replace('/', '\')
    if ($BaselineArchive -and -not $file.StartsWith('tests/')) {
        if (-not $baselineHashes.ContainsKey($baselineKey)) { throw "Missing baseline script: $file" }
        $hash = $baselineHashes[$baselineKey]
    }
    if ($hash -ne (Get-FileHash -LiteralPath (Join-Path $project "mods-unpacked/wushuangabao-BrotatoOnlineFriends/$file")).Hash) { throw "Deploy current $file first." }
    "$file SHA256=$hash" | Add-Content (Join-Path $output 'source.txt')
}
foreach ($file in Get-ChildItem -LiteralPath "$PSScriptRoot/fixtures/Local-InputProbe" -File) {
    $hash = (Get-FileHash -LiteralPath $file.FullName).Hash
    if ($hash -ne (Get-FileHash -LiteralPath "$project/mods-unpacked/Local-InputProbe/$($file.Name)").Hash) { throw "Deploy test fixture $($file.Name) first." }
    "fixture/$($file.Name) SHA256=$hash" | Add-Content (Join-Path $output 'source.txt')
}
$versions = @{'wushuangabao-FiveItemShop'='1.1.3';'wushuangabao-NoobsWantToLive'='1.1.0'}
foreach ($id in $versions.Keys) {
    $manifest = Get-Content -Raw -LiteralPath "$project/mods-unpacked/$id/manifest.json" | ConvertFrom-Json
    if ($manifest.version_number -ne $versions[$id]) { throw "Wrong companion Mod version: $id" }
    Get-ChildItem -LiteralPath "$project/mods-unpacked/$id" -Filter '*.gd' -Recurse -File | ForEach-Object {
        "$id/$($_.Name) SHA256=$((Get-FileHash -LiteralPath $_.FullName).Hash)" | Add-Content (Join-Path $output 'source.txt')
    }
}
$modList = @{}
foreach ($manifestFile in Get-ChildItem -LiteralPath "$project/mods-unpacked" -Filter manifest.json -Recurse -File) {
    $manifest = Get-Content -Raw -LiteralPath $manifestFile.FullName | ConvertFrom-Json
    $id = "$($manifest.namespace)-$($manifest.name)"
    $modList[$id] = @{ is_active = ($id -in @('wushuangabao-BrotatoOnlineFriends','wushuangabao-FiveItemShop','wushuangabao-NoobsWantToLive','Local-InputProbe')); zip_path = '' }
}
$roles = if ($Case -eq 'single') { @('single') } elseif ($Case -eq 'three') { @('host','client1','client2') } else { @('host','client1') }
$scene = if ($Case -eq 'single') { 'selection_input' } else { 'selection_input_lan' }
$previous = @{}
foreach ($key in @('APPDATA','FRIENDS_PROBE_CASE','FRIENDS_PROBE_ROLE','FRIENDS_PROBE_DIR')) { $previous[$key] = [Environment]::GetEnvironmentVariable($key,'Process') }
$processes = @{}
Write-Output "Evidence: $output"
try {
    try {
        foreach ($role in $roles) {
            New-Item -ItemType Directory -Path "$output/$role/Brotato/logs" -Force | Out-Null
            @{ current_profile='default'; profiles=@{ default=@{ mod_list=$modList } } } | ConvertTo-Json -Depth 8 | Set-Content "$output/$role/Brotato/mod_user_profiles.json" -Encoding utf8
            $env:APPDATA = "$output/$role"
            $env:FRIENDS_PROBE_CASE = $Case
            $env:FRIENDS_PROBE_ROLE = $role
            $env:FRIENDS_PROBE_DIR = $output
            $arguments = '--path "{0}" --enable-mods --no-window --audio-driver Dummy res://mods-unpacked/wushuangabao-BrotatoOnlineFriends/tests/{1}.tscn' -f $project,$scene
            $processes[$role] = Start-Process $Godot -ArgumentList $arguments -WorkingDirectory $project -WindowStyle Hidden -PassThru -RedirectStandardOutput "$output/$role.stdout.log" -RedirectStandardError "$output/$role.stderr.log"
        }
    } finally {
        foreach ($key in $previous.Keys) { [Environment]::SetEnvironmentVariable($key,$previous[$key],'Process') }
    }
    $deadline = [DateTime]::UtcNow.AddSeconds(90)
    while (@($processes.Values | Where-Object { -not $_.HasExited }).Count -gt 0 -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 200 }
    foreach ($role in $roles) {
        $process = $processes[$role]
        if (-not $process.HasExited) { throw "Test timed out: $role ($output)" }
        $process.WaitForExit()
        $resultPath = "$output/$role-result.json"
        if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $resultPath) -or (Select-String -LiteralPath "$output/$role.stderr.log" -Pattern 'SCRIPT ERROR:|SELECTION_INPUT_FAIL:' -Quiet)) { throw "Regression failed: $role ($output)" }
        $result = Get-Content -Raw -LiteralPath $resultPath | ConvertFrom-Json
        if ($result.failures.Count -ne 0 -or $result.checks -lt 1) { throw "Assertions failed: $role ($output)" }
        Write-Output "$role PASS: $($result.checks) assertions"
    }
} finally {
    foreach ($process in $processes.Values) {
        if (-not $process.HasExited) { $process.Kill(); $process.WaitForExit() }
    }
}
