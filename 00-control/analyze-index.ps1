$ErrorActionPreference = 'Stop'
$rows = Import-Csv 'D:\REA-LAB\04-index\summary.csv'
$managed = @($rows | Where-Object { $_.managed -eq 'True' })
$errors = @($rows | Where-Object { $_.error -ne '' })

Write-Output ("files={0} managed={1} nativeOrInvalid={2}" -f $rows.Count, $managed.Count, ($rows.Count - $managed.Count))
Write-Output ("types={0} methods={1} strings={2} calls={3}" -f `
    (($managed | Measure-Object { [int]$_.types } -Sum).Sum), `
    (($managed | Measure-Object { [int]$_.methods } -Sum).Sum), `
    (($managed | Measure-Object { [int]$_.strings } -Sum).Sum), `
    (($managed | Measure-Object { [int]$_.calls } -Sum).Sum))

Write-Output '--- top 15 managed assemblies by methods ---'
$managed | Sort-Object { [int]$_.methods } -Descending | Select-Object -First 15 file, assembly, types, methods |
    Format-Table -AutoSize | Out-String -Width 140

$pattern = 'MatrixGold|SharedTypes|MatrixCommon|^Common|Localization|^CS|^GV|Gemvision|Stuller|SuperView|Viewport2D|MeshAPI|DebugDraw|Toast|EventSystem'
$first = @($managed | Where-Object { $_.assembly -match $pattern -and $_.file -notmatch '\\[a-z]{2}(-[A-Za-z]+)?\\' })
Write-Output '--- first-party managed assemblies ---'
$first | Sort-Object { [int]$_.methods } -Descending | Select-Object file, assembly, types, methods |
    Format-Table -AutoSize | Out-String -Width 140
Write-Output ("firstPartyAssemblies={0} types={1} methods={2}" -f $first.Count, `
    (($first | Measure-Object { [int]$_.types } -Sum).Sum), `
    (($first | Measure-Object { [int]$_.methods } -Sum).Sum))

Write-Output '--- native / invalid ---'
$errors | Select-Object file, error | Format-Table -AutoSize | Out-String -Width 160
