$ErrorActionPreference = 'Stop'
. 'D:\REA-LAB\00-control\retry.ps1'

$lab = 'D:\REA-LAB'
$temp = "$env:LOCALAPPDATA\Temp"
$profileDirs = @(
    "$env:USERPROFILE\.config\freebuff-desktop",
    "$env:LOCALAPPDATA\freebuff-desktop",
    "$env:APPDATA\freebuff-desktop",
    "$env:APPDATA\npm-cache",
    "$env:USERPROFILE\.npm"
)

$cFree = (Get-PSDrive C).Free
$dFree = (Get-PSDrive D).Free

$fridaDirs = @(Get-ChildItem -LiteralPath $temp -Directory -Filter 'frida-*' -ErrorAction SilentlyContinue)
$fridaBytes = ($fridaDirs | ForEach-Object { Get-DirSizeBytes $_.FullName } | Measure-Object -Sum).Sum
if ($null -eq $fridaBytes) { $fridaBytes = 0 }

$odis = Join-Path $temp 'odis_download_dest'
$adapp = Join-Path $temp 'AdAppMgrRollBackBackup'

$topTemp = @()
Get-ChildItem -LiteralPath $temp -Force -ErrorAction SilentlyContinue | ForEach-Object {
    $size = if ($_.PSIsContainer) { Get-DirSizeBytes $_.FullName } else { $_.Length }
    $topTemp += [pscustomobject]@{ name = $_.Name; bytes = [int64]$size; isDir = $_.PSIsContainer }
}
$topTemp = $topTemp | Sort-Object bytes -Descending | Select-Object -First 40

$result = [ordered]@{
    capturedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    cFreeBytes = [int64]$cFree
    dFreeBytes = [int64]$dFree
    localAppDataTempBytes = [int64](Get-DirSizeBytes $temp)
    fridaDirCount = $fridaDirs.Count
    fridaBytes = [int64]$fridaBytes
    odisBytes = [int64](Get-DirSizeBytes $odis)
    adAppMgrBytes = [int64](Get-DirSizeBytes $adapp)
    cProfileDirs = @($profileDirs | ForEach-Object {
        [pscustomobject]@{ path = $_; bytes = [int64](Get-DirSizeBytes $_) }
    })
    topTempEntries = $topTemp
}

New-Item -ItemType Directory -Force -Path "$lab\00-control" | Out-Null
Write-AtomicText -Path "$lab\00-control\c-baseline.json" -Content ($result | ConvertTo-Json -Depth 6)

Write-Host ("C: free      : {0}" -f (Format-Bytes $cFree))
Write-Host ("D: free      : {0}" -f (Format-Bytes $dFree))
Write-Host ("Temp total   : {0}" -f (Format-Bytes $result.localAppDataTempBytes))
Write-Host ("frida dirs   : {0} = {1}" -f $fridaDirs.Count, (Format-Bytes $fridaBytes))
Write-Host ("odis         : {0}" -f (Format-Bytes $result.odisBytes))
Write-Host ("AdAppMgr     : {0}" -f (Format-Bytes $result.adAppMgrBytes))
