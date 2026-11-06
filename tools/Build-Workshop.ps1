param([Parameter(Mandatory = $true)][string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
$source = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path
$manifest = Get-Content -LiteralPath (Join-Path $source 'manifest.json') -Raw | ConvertFrom-Json
$modId = "$($manifest.namespace)-$($manifest.name)"
$version = $manifest.version_number
if ($modId -ne 'six666-BrotatoOnline' -or $version -notmatch '^\d+\.\d+\.\d+$') { throw 'Unexpected Mod ID or version.' }
$protocol = Get-Content -LiteralPath (Join-Path $source 'scripts/protocol.gd') -Raw
if ($protocol -notmatch ('const MOD_VERSION = "' + [regex]::Escape($version) + '"')) { throw 'Manifest/protocol package versions differ.' }
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$output = (Resolve-Path -LiteralPath $OutputDirectory).Path
$zipPath = Join-Path $output "$modId-Fixed-$version.zip"
if (Test-Path -LiteralPath $zipPath) { throw "Output already exists: $zipPath" }
# Explicit allowlist: never package the game, tests, saves, logs or .git.
$relativeFiles = @('manifest.json', 'mod_main.gd', 'LICENSE', 'README.md', 'README.en.md', 'CHANGELOG.md', 'tools/Build-Workshop.ps1')
foreach ($folder in @('scripts', 'extensions', 'translations', 'docs')) {
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $source $folder) -File -Recurse) {
        $relativeFiles += $file.FullName.Substring($source.Length + 1).Replace('\', '/')
    }
}
$relativeFiles = @($relativeFiles | Sort-Object -Unique)
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::Open($zipPath, [IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($relative in $relativeFiles) {
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, (Join-Path $source $relative), "mods-unpacked/$modId/$relative", [IO.Compression.CompressionLevel]::Optimal) | Out-Null
    }
} finally { $archive.Dispose() }
# Reopen the completed ZIP and compare every entry with its source hash.
$archive = [IO.Compression.ZipFile]::OpenRead($zipPath)
$fileHashes = [ordered]@{}
try {
    if ($archive.Entries.Count -ne $relativeFiles.Count) { throw 'Unexpected ZIP entry count.' }
    foreach ($relative in $relativeFiles) {
        $entry = $archive.GetEntry("mods-unpacked/$modId/$relative")
        if ($null -eq $entry) { throw "Missing ZIP entry: $relative" }
        $stream = $entry.Open()
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $actual = [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-', '') }
        finally { $sha.Dispose(); $stream.Dispose() }
        $expected = (Get-FileHash -LiteralPath (Join-Path $source $relative) -Algorithm SHA256).Hash
        if ($actual -ne $expected) { throw "ZIP content differs: $relative" }
        $fileHashes[$relative] = $actual
    }
} finally { $archive.Dispose() }
$zipHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash
"$zipHash  $([IO.Path]::GetFileName($zipPath))" | Set-Content -LiteralPath "$zipPath.sha256" -Encoding ascii
[ordered]@{ mod_id=$modId; version=$version; zip=$zipPath; sha256=$zipHash; entry_count=$relativeFiles.Count; verification='Every ZIP entry matches its source SHA256'; files=$fileHashes } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath "$zipPath.contents.json" -Encoding utf8
Get-Item -LiteralPath $zipPath | Select-Object FullName, Length
Write-Output "Verified $($relativeFiles.Count) entries. SHA256=$zipHash"
