$ErrorActionPreference = 'Continue'
$node = 'D:\REA-LAB\02-toolchain\node\node.exe'
$rea = 'D:\REA-LAB\02-toolchain\npm-global\node_modules\rea-agents\scripts\rea.mjs'
$root = 'D:\REA-LAB\01-target\mirror\Main'
$out = 'D:\REA-LAB\05-evidence\rea'

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

$rows = @()
foreach ($t in $targets) {
    $json = & $node $rea inspect-managed-artifact $t.path --json
    $code = $LASTEXITCODE
    $dest = Join-Path $out "$($t.name).artifact.json"
    if ($json) {
        $text = $json -join "`n"
        if (-not $text.TrimStart().StartsWith('{')) { Write-Warning "non-JSON output for $($t.name): $($text.Substring(0,[Math]::Min(120,$text.Length)))" }
        [IO.File]::WriteAllText($dest, $text + "`n", (New-Object Text.UTF8Encoding($false)))
    }
    $rows += [pscustomobject]@{ name = $t.name; exit = $code; bytes = (Get-Item $dest).Length }
    Write-Host ("{0}: exit={1} bytes={2:N0}" -f $t.name, $code, (Get-Item $dest).Length)
}
$rows | Export-Csv -LiteralPath 'D:\REA-LAB\05-evidence\rea\artifact-index.csv' -NoTypeInformation -Encoding UTF8
