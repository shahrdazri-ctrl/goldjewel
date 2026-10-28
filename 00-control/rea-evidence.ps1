. 'D:\REA-LAB\00-control\env.ps1'
$ErrorActionPreference = 'Continue'

$rea = 'D:\REA-LAB\02-toolchain\npm-global\rea.cmd'
$root = 'D:\REA-LAB\01-target\mirror\Main'
$out = 'D:\REA-LAB\05-evidence\rea'
New-Item -ItemType Directory -Force -Path $out | Out-Null

$targets = @(
    @{ name = 'MatrixGold';        path = "$root\MatrixGold\MatrixGold.exe" },
    @{ name = 'CS';                path = "$root\MatrixGold\MatrixGoldPlugin\CS.dll" },
    @{ name = 'CSBlocks';          path = "$root\C46E9C27-4A0F-4A5E-86E8-18F7094A7461.mgp" },
    @{ name = 'MatrixGoldPlugin';  path = "$root\MatrixGold\MatrixGoldPlugin\MatrixGoldPlugin.rhp" },
    @{ name = 'SharedTypes';       path = "$root\MatrixGold\SharedTypes.dll" },
    @{ name = 'MatrixCommon';      path = "$root\MatrixGold\MatrixCommon.dll" },
    @{ name = 'Common';            path = "$root\MatrixGold\Common.dll" },
    @{ name = 'CSGemInstance';     path = "$root\MatrixGold\MatrixGoldPlugin\CSGemInstance.dll" },
    @{ name = 'CSMaterials';       path = "$root\MatrixGold\MatrixGoldPlugin\CSMaterials.dll" },
    @{ name = 'CSRingSizes';       path = "$root\MatrixGold\MatrixGoldPlugin\CSRingSizes.dll" },
    @{ name = 'GVBuilders';        path = "$root\MatrixGold\MatrixGoldPlugin\GVBuilders.dll" },
    @{ name = 'GemvisionGeometry'; path = "$root\MatrixGold\MatrixGoldPlugin\GemvisionGeometry.dll" },
    @{ name = 'Viewport2D';        path = "$root\MatrixGold\MatrixGoldPlugin\Viewport2D.dll" },
    @{ name = 'CSDatas';           path = "$root\MatrixGold\MatrixGoldPlugin\CSDatas.dll" }
)

foreach ($t in $targets) {
    if (-not (Test-Path -LiteralPath $t.path)) { Write-Warning "missing $($t.path)"; continue }
    Write-Host "REA artifact: $($t.name)"
    & $rea inspect-managed-artifact $t.path --json 2>&1 | Out-File -FilePath (Join-Path $out "$($t.name).artifact.json") -Encoding utf8
    Write-Host "REA members : $($t.name)"
    & $rea inspect-managed-members $t.path --detail summary --evidence-bundle (Join-Path $out "$($t.name).members.json") --json 2>&1 |
        Out-File -FilePath (Join-Path $out "$($t.name).members-summary.json") -Encoding utf8
}

Get-ChildItem $out | Select-Object Name, Length | Sort-Object Name | Format-Table -AutoSize | Out-String -Width 100 | Write-Host
