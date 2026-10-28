$ErrorActionPreference = 'Continue'
$node = 'D:\REA-LAB\02-toolchain\node\node.exe'
$rea = 'D:\REA-LAB\02-toolchain\npm-global\node_modules\rea-agents\scripts\rea.mjs'
$root = 'D:\REA-LAB\01-target\mirror\Main'
$out = 'D:\REA-LAB\05-evidence\rea'
$env:NODE_OPTIONS = '--max-old-space-size=12288'

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
    $bundle = Join-Path $out "$($t.name).members.json"
    $summaryPath = Join-Path $out "$($t.name).members-summary.json"
    if (Test-Path $bundle) { Remove-Item $bundle -Force }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $summary = & $node $rea inspect-managed-members $t.path --detail summary --evidence-bundle $bundle --json
    $code = $LASTEXITCODE
    $sw.Stop()
    if ($summary) { $summary | Set-Content -LiteralPath $summaryPath -Encoding utf8 }
    $size = 0
    if (Test-Path $bundle) { $size = (Get-Item $bundle).Length }
    Write-Host ("{0}: exit={1} {2:N1}s {3:N1}MB summary={4}" -f $t.name, $code, $sw.Elapsed.TotalSeconds, ($size / 1MB), (Test-Path $summaryPath))
}
