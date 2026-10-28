$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
. 'D:\REA-LAB\00-control\env.ps1'
. 'D:\REA-LAB\00-control\retry.ps1'

$tool = 'D:\REA-LAB\02-toolchain'
$index = Invoke-RestMethod -Uri 'https://nodejs.org/dist/index.json' -UseBasicParsing
$v24 = $index | Where-Object { $_.version -match '^v24\.' } | ForEach-Object {
    [pscustomobject]@{ Version = $_.version; Sem = [version]($_.version.TrimStart('v')) }
} | Sort-Object Sem -Descending
$pick = $v24 | Where-Object { $_.Sem -ge [version]'24.22.1' } | Select-Object -First 1
if (-not $pick) { throw 'No Node 24.22.1+ release found.' }

$zip = Join-Path $tool 'node.zip'
$url = "https://nodejs.org/dist/$($pick.Version)/node-$($pick.Version)-win-x64.zip"
Write-Host "Downloading $url"
Invoke-WithRetry -Label 'node download' -Action { Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing }

$extract = Join-Path $tool '_node_extract'
if (Test-Path $extract) { Remove-Item -LiteralPath $extract -Recurse -Force }
New-Item -ItemType Directory -Force -Path $extract | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::ExtractToDirectory($zip, $extract)

$inner = Get-ChildItem -LiteralPath $extract -Directory | Select-Object -First 1
$dest = Join-Path $tool 'node'
if (Test-Path $dest) { Remove-Item -LiteralPath $dest -Recurse -Force }
Move-Item -LiteralPath $inner.FullName -Destination $dest

Remove-Item -LiteralPath $zip -Force
Remove-Item -LiteralPath $extract -Recurse -Force

$node = Join-Path $dest 'node.exe'
$npm = Join-Path $dest 'npm.cmd'
Write-Host ("node: " + (& $node --version))
Write-Host ("npm : " + (& $npm --version))
