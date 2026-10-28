$ErrorActionPreference = 'Continue'
$temp = Join-Path $env:LOCALAPPDATA 'Temp'
$log  = 'D:\REA-LAB\09-logs\cleanup-c.log'
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $log) | Out-Null
function Get-Size($p) {
    if (-not (Test-Path -LiteralPath $p)) { return 0 }
    $s = 0
    Get-ChildItem -LiteralPath $p -Recurse -Force -File -ErrorAction SilentlyContinue |
        ForEach-Object { $s += $_.Length }
    return $s
}
$before = @{}
$targets = @()
$targets += Get-ChildItem -LiteralPath $temp -Directory -Filter 'frida-*' -ErrorAction SilentlyContinue
foreach ($n in @('odis_download_dest','AdAppMgrRollBackBackup')) {
    $p = Join-Path $temp $n
    if (Test-Path -LiteralPath $p) { $targets += Get-Item -LiteralPath $p }
}
"cleanup start $(Get-Date -Format o)" | Out-File -FilePath $log -Encoding utf8
"temp root: $temp" | Out-File -FilePath $log -Append -Encoding utf8
"targets: $($targets.Count)" | Out-File -FilePath $log -Append -Encoding utf8

$freed = 0
$failed = @()
foreach ($t in $targets) {
    # hard guard: only under %LOCALAPPDATA%\Temp
    if (-not $t.FullName.StartsWith($temp, [StringComparison]::OrdinalIgnoreCase)) {
        $failed += $t.FullName
        continue
    }
    $sz = Get-Size $t.FullName
    try {
        Remove-Item -LiteralPath $t.FullName -Recurse -Force -ErrorAction Stop
        $freed += $sz
        "removed $($t.Name) $sz" | Out-File -FilePath $log -Append -Encoding utf8
    } catch {
        $failed += $t.FullName
        "kept (in use) $($t.Name): $($_.Exception.Message)" | Out-File -FilePath $log -Append -Encoding utf8
    }
}
$remaining = Get-ChildItem -LiteralPath $temp -Directory -Filter 'frida-*' -ErrorAction SilentlyContinue
$result = [ordered]@{
    ranAtUtc        = (Get-Date).ToUniversalTime().ToString('o')
    tempRoot        = $temp
    targetCount     = $targets.Count
    freedBytes      = $freed
    freedGiB        = [math]::Round($freed / 1GB, 3)
    failedPaths     = $failed
    fridaRemaining  = @($remaining).Count
    odisRemaining   = Test-Path -LiteralPath (Join-Path $temp 'odis_download_dest')
    adskRemaining   = Test-Path -LiteralPath (Join-Path $temp 'AdAppMgrRollBackBackup')
    cFreeBytes      = (Get-PSDrive C).Free
}
$result | ConvertTo-Json -Depth 5 | Out-File -FilePath 'D:\REA-LAB\00-control\cleanup-result.json' -Encoding utf8
$result | ConvertTo-Json -Depth 5
