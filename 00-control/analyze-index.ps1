$ErrorActionPreference = 'Stop'
. 'D:\REA-LAB\00-control\env.ps1'

$root = 'D:\REA-LAB\01-target\mirror\Main'
$out = 'D:\REA-LAB\04-index'
$project = 'D:\REA-LAB\02-toolchain\SymbolScan\SymbolScan.csproj'

# SymbolScan appends; clear the generated index so a re-run is idempotent.
Remove-Item -LiteralPath (Join-Path $out 'summary.csv') -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $out 'errors.log') -Force -ErrorAction SilentlyContinue
if (Test-Path (Join-Path $out 'raw')) {
    Remove-Item -LiteralPath (Join-Path $out 'raw') -Recurse -Force
}

& dotnet run --project $project -c Release -- --root $root --out $out
if ($LASTEXITCODE -ne 0) { throw "SymbolScan failed with exit $LASTEXITCODE" }

$rows = Import-Csv (Join-Path $out 'summary.csv')
$managed = @($rows | Where-Object { $_.managed -eq 'True' })
$errors = @($rows | Where-Object { $_.error -ne '' })
function Get-ColumnSum($items, $column) {
    ($items | ForEach-Object { [int]$_.$column } | Measure-Object -Sum).Sum
}

Write-Output ("files={0} managed={1} nativeOrInvalid={2}" -f $rows.Count, $managed.Count, ($rows.Count - $managed.Count))
Write-Output ("types={0} methods={1} strings={2} calls={3}" -f `
    (Get-ColumnSum $managed 'types'), (Get-ColumnSum $managed 'methods'), `
    (Get-ColumnSum $managed 'strings'), (Get-ColumnSum $managed 'calls'))

Write-Output '--- top 15 managed assemblies by methods ---'
$managed | Sort-Object { [int]$_.methods } -Descending | Select-Object -First 15 file, assembly, types, methods |
    Format-Table -AutoSize | Out-String -Width 140

$pattern = 'MatrixGold|SharedTypes|MatrixCommon|^Common|Localization|^CS|^GV|Gemvision|Stuller|SuperView|Viewport2D|MeshAPI|DebugDraw|Toast|EventSystem'
$first = @($managed | Where-Object { $_.assembly -match $pattern -and $_.file -notmatch '\\[a-z]{2}(-[A-Za-z]+)?\\' })
Write-Output '--- first-party managed assemblies ---'
$first | Sort-Object { [int]$_.methods } -Descending | Select-Object file, assembly, types, methods |
    Format-Table -AutoSize | Out-String -Width 140
Write-Output ("firstPartyAssemblies={0} types={1} methods={2}" -f $first.Count, `
    (Get-ColumnSum $first 'types'), (Get-ColumnSum $first 'methods'))

Write-Output '--- native / invalid ---'
$errors | Select-Object file, error | Format-Table -AutoSize | Out-String -Width 160
