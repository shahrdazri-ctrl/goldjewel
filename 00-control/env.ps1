$ErrorActionPreference = 'Stop'
$Lab = 'D:\REA-LAB'
$env:LAB = $Lab

# Every temp/cache location this job controls -> D:
$env:TEMP = "$Lab\02-toolchain\tmp"
$env:TMP = $env:TEMP
$env:TMPDIR = $env:TEMP
$env:npm_config_cache = "$Lab\02-toolchain\npm-cache"
$env:npm_config_prefix = "$Lab\02-toolchain\npm-global"
$env:npm_config_tmp = $env:TEMP
$env:npm_config_userconfig = "$Lab\02-toolchain\npmrc"
$env:NUGET_PACKAGES = "$Lab\02-toolchain\nuget"
$env:DOTNET_CLI_HOME = "$Lab\02-toolchain\dotnet"
$env:DOTNET_NOLOGO = '1'
$env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
$env:REA_LOG_LEVEL = 'info'

foreach ($p in @(
    $env:TEMP,
    "$Lab\02-toolchain\npm-cache",
    "$Lab\02-toolchain\npm-global",
    "$Lab\02-toolchain\nuget",
    "$Lab\02-toolchain\dotnet",
    "$Lab\02-toolchain\ilspy",
    "$Lab\03-decompiled",
    "$Lab\04-index",
    "$Lab\05-evidence",
    "$Lab\08-reports",
    "$Lab\09-logs"
)) { New-Item -ItemType Directory -Force -Path $p | Out-Null }

$env:PATH = "$Lab\02-toolchain\node;$Lab\02-toolchain\npm-global;$Lab\02-toolchain\ilspy;$env:PATH"
Write-Host "LAB=$Lab"
Write-Host "TEMP=$env:TEMP"
Write-Host "NODE=$(try { (& "$Lab\02-toolchain\node\node.exe" --version) } catch { 'not-installed' })"
