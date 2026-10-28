$ErrorActionPreference = 'Stop'
. 'D:\REA-LAB\00-control\retry.ps1'

$src = 'D:\MAIN SOFTWARE\jewerly software\matrix gold\Gemvision.MatrixGold\Main'
$dst = 'D:\REA-LAB\01-target\mirror\Main'

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dst) | Out-Null

Write-Host "Mirroring $src -> $dst"
& robocopy $src $dst /E /COPY:DAT /R:3 /W:2 /NFL /NDL /NJH /NJS /NP
$rc = $LASTEXITCODE
if ($rc -ge 8) { throw "robocopy failed with exit code $rc" }
Write-Host "robocopy exit: $rc"

$app = Join-Path $dst 'MatrixGold'
Write-Host ("Mirror size: {0:N2} GB" -f ((Get-ChildItem -LiteralPath $dst -Recurse -Force | Measure-Object -Property Length -Sum).Sum / 1GB))
Write-Host ("App assemblies: {0}" -f (Get-ChildItem -LiteralPath $app -File | Where-Object { $_.Extension -in '.dll','.exe' }).Count)
