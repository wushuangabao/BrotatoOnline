param(
    [string]$ProjectPath='E:\github\BrotatoMod\work\friends-input-diagnosis-20261110',
    [string]$Godot='E:\github\BrotatoMod\work\NoobsWantToLive-source-runner\Brotato-source.exe',
    [string]$BaselineArchive='E:\github\BrotatoMod\dist\wushuangabao-BrotatoOnlineFriends-6.8.1.zip',
    [ValidateSet('pads','keyboard','client_keyboard','both_keyboard')][string]$Case='keyboard',
    [ValidateSet('fixed','baseline')][string]$ResumeVersion='fixed',
    [switch]$Matrix
)
$ErrorActionPreference='Stop'
$project=(Resolve-Path -LiteralPath $ProjectPath).Path
$repo=Split-Path -Parent $PSScriptRoot
$target=Join-Path $project 'mods-unpacked/wushuangabao-BrotatoOnlineFriends'
$label=if($Matrix){'matrix'}else{$Case}
$output=Join-Path $project ('evidence/save-compat-'+$label+'-'+$ResumeVersion+'-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Force -Path $output | Out-Null
$production=@(Get-ChildItem "$repo/scripts","$repo/extensions" -Filter '*.gd' -Recurse -File | ForEach-Object {$_.FullName.Substring($repo.Length+1)})+@('mod_main.gd','manifest.json')
Copy-Item -LiteralPath "$PSScriptRoot/save_compatibility.gd","$PSScriptRoot/save_compatibility.tscn" -Destination "$target/tests"
$mods=@{}
foreach($id in @('wushuangabao-BrotatoOnlineFriends','wushuangabao-FiveItemShop','wushuangabao-NoobsWantToLive','Local-InputProbe')){$mods[$id]=@{is_active=$true;zip_path=''}}
$previous=@{}
foreach($key in @('APPDATA','FRIENDS_PROBE_ROLE','FRIENDS_PROBE_DIR','SAVE_TEST_PHASE','SAVE_TEST_ROOT','SAVE_TEST_HOST_INPUT','SAVE_TEST_CLIENT_INPUT')){$previous[$key]=[Environment]::GetEnvironmentVariable($key,'Process')}
$configs=@(
    @{name='pads';host='pads';client='pads'},
    @{name='keyboard';host='mixed';client='pads'},
    @{name='client_keyboard';host='pads';client='mixed'},
    @{name='both_keyboard';host='mixed';client='mixed'}
)
$saveConfigs=if($Matrix){$configs}else{@($configs | Where-Object {$_.name -eq $Case})}
$results=[System.Collections.Generic.List[object]]::new()
Add-Type -AssemblyName System.IO.Compression.FileSystem
Write-Output "Evidence: $output"
try {
    foreach($saved in $saveConfigs){
        $saveRoot=Join-Path $output ('saved-'+$saved.name)
        foreach($role in @('host','client1')){
            $data="$saveRoot/userdata/$role/Brotato"
            New-Item -ItemType Directory -Force -Path "$data/logs" | Out-Null
            @{current_profile='default';profiles=@{default=@{mod_list=$mods}}} | ConvertTo-Json -Depth 8 | Set-Content "$data/mod_user_profiles.json" -Encoding utf8
        }
        $resumeConfigs=if($Matrix){$configs}else{@($saved)}
        $steps=@(@{phase='create';config=$saved;name='create'})+@($resumeConfigs | ForEach-Object {@{phase='resume';config=$_;name=('resume-'+$_.name)}})
        $created=$false
        foreach($step in $steps){
            if($step.phase -eq 'resume' -and -not $created){continue}
            $phaseDir=Join-Path $saveRoot $step.name
            New-Item -ItemType Directory -Force -Path $phaseDir | Out-Null
            $dataRoot="$saveRoot/userdata"
            if($step.phase -eq 'create' -or $ResumeVersion -eq 'baseline'){
                $zip=[System.IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $BaselineArchive).Path)
                try {foreach($rel in $production){$entry=$zip.GetEntry(('mods-unpacked/wushuangabao-BrotatoOnlineFriends/'+$rel).Replace('\','/')); if(-not $entry){throw "Missing release entry: $rel"}; [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry,(Join-Path $target $rel),$true)}} finally {$zip.Dispose()}
            } else {
                foreach($rel in $production){Copy-Item -LiteralPath (Join-Path $repo $rel) -Destination (Join-Path $target $rel)}
            }
            if($step.phase -eq 'resume'){
                # Resume each configuration from an untouched copy of the same original network save.
                $dataRoot="$saveRoot/$($step.name)-userdata"
                Copy-Item -LiteralPath "$saveRoot/userdata" -Destination $dataRoot -Recurse
            }
            foreach($rel in $production){"$rel SHA256=$((Get-FileHash -LiteralPath (Join-Path $target $rel)).Hash)" | Add-Content "$phaseDir/source.txt"}
            foreach($rel in @('save_compatibility.gd','save_compatibility.tscn')){"tests/$rel SHA256=$((Get-FileHash -LiteralPath "$target/tests/$rel").Hash)" | Add-Content "$phaseDir/source.txt"}
            $step.config | ConvertTo-Json | Set-Content "$phaseDir/input-config.json"
            $processes=@{}
            $row=[ordered]@{save=$saved.name;phase=$step.name;passed=$false;checks=0;error=''}
            try {
                foreach($role in @('host','client1')){
                    $env:APPDATA="$dataRoot/$role"
                    $env:FRIENDS_PROBE_ROLE=$role
                    $env:FRIENDS_PROBE_DIR=$phaseDir
                    $env:SAVE_TEST_PHASE=$step.phase
                    $env:SAVE_TEST_ROOT=$saveRoot
                    $env:SAVE_TEST_HOST_INPUT=$step.config.host
                    $env:SAVE_TEST_CLIENT_INPUT=$step.config.client
                    $processes[$role]=Start-Process $Godot -ArgumentList ('--path "{0}" --enable-mods --no-window --audio-driver Dummy res://mods-unpacked/wushuangabao-BrotatoOnlineFriends/tests/save_compatibility.tscn' -f $project) -WorkingDirectory $project -WindowStyle Hidden -PassThru -RedirectStandardOutput "$phaseDir/$role.stdout.log" -RedirectStandardError "$phaseDir/$role.stderr.log"
                }
                $deadline=[DateTime]::UtcNow.AddSeconds(140)
                while(@($processes.Values | Where-Object {-not $_.HasExited}).Count -gt 0 -and [DateTime]::UtcNow -lt $deadline){Start-Sleep -Milliseconds 200}
                foreach($role in @('host','client1')){
                    $p=$processes[$role]
                    if(-not $p.HasExited -or $p.ExitCode -ne 0 -or -not(Test-Path "$phaseDir/$role-result.json")){throw "$($step.name) $role failed: $phaseDir"}
                    $result=Get-Content -Raw "$phaseDir/$role-result.json" | ConvertFrom-Json
                    if($result.failures.Count -gt 0 -or (Select-String "$phaseDir/$role.stderr.log" -Pattern 'SCRIPT ERROR:' -Quiet)){throw "$($step.name) $role assertions failed: $phaseDir"}
                    $row.checks+=$result.checks
                }
                $row.passed=$true
                if($step.phase -eq 'create'){$created=$true}
                Write-Output "$($saved.name) -> $($step.name) PASS: $($row.checks) assertions"
            } catch {
                $row.error=$_.Exception.Message
                Write-Output "FAIL: $($row.error)"
            } finally {
                foreach($p in $processes.Values){if(-not $p.HasExited){$p.Kill();$p.WaitForExit()}}
                Get-ChildItem $dataRoot -Recurse -File | ForEach-Object {[pscustomobject]@{path=$_.FullName.Substring($saveRoot.Length+1);sha256=(Get-FileHash -LiteralPath $_.FullName).Hash}} | ConvertTo-Json | Set-Content "$phaseDir/userdata-hashes.json"
                $results.Add([pscustomobject]$row)
                $results | ConvertTo-Json | Set-Content "$output/results.json"
            }
        }
    }
    if(@($results | Where-Object {-not $_.passed}).Count -gt 0){throw "Save compatibility failed; retained evidence: $output"}
} finally {
    foreach($rel in $production){Copy-Item -LiteralPath (Join-Path $repo $rel) -Destination (Join-Path $target $rel)}
    foreach($key in $previous.Keys){[Environment]::SetEnvironmentVariable($key,$previous[$key],'Process')}
}
