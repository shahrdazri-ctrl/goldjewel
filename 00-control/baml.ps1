. 'D:\REA-LAB\00-control\env.ps1'
$ErrorActionPreference = 'Continue'

$tool = 'D:\REA-LAB\02-toolchain\BamlTool\bin\Release\net8.0\BamlTool.dll'
$root = 'D:\REA-LAB\01-target\mirror\Main'
$app = Join-Path $root 'MatrixGold'
$plugin = Join-Path $app 'MatrixGoldPlugin'
$render = Join-Path $app 'MatrixGoldRenderPlugin'
$raw = 'D:\REA-LAB\03-decompiled\raw'
$outRoot = 'D:\REA-LAB\03-decompiled\xaml'
New-Item -ItemType Directory -Force -Path $outRoot | Out-Null

$allAsm = Get-ChildItem $root -Recurse -File | Where-Object { $_.Extension -in '.dll', '.exe', '.mgp', '.rhp' }

foreach ($dir in Get-ChildItem $raw -Directory) {
    $bamls = @(Get-ChildItem $dir.FullName -Recurse -File -Filter *.baml -ErrorAction SilentlyContinue)
    if ($bamls.Count -eq 0) { continue }
    $asm = $allAsm | Where-Object { $_.BaseName -eq $dir.Name } | Select-Object -First 1
    if (-not $asm) { Write-Warning "no assembly for $($dir.Name)"; continue }
    $out = Join-Path $outRoot $dir.Name
    New-Item -ItemType Directory -Force -Path $out | Out-Null
    Write-Host "BAML: $($dir.Name) ($($bamls.Count) files) <- $($asm.FullName)"
    & dotnet $tool $asm.FullName $dir.FullName $out $app $plugin $render 2>&1 | Out-String | Write-Host
}

$xaml = @(Get-ChildItem $outRoot -Recurse -File -Filter *.xaml)
Write-Host ("TOTAL xaml={0}" -f $xaml.Count)
