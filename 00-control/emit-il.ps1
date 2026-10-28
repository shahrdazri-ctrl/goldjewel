$ErrorActionPreference = 'Continue'

$ilspy = 'D:\REA-LAB\02-toolchain\ilspy\ilspycmd.exe'
$root = 'D:\REA-LAB\01-target\mirror\Main'
$app = Join-Path $root 'MatrixGold'
$plugin = Join-Path $app 'MatrixGoldPlugin'
$render = Join-Path $app 'MatrixGoldRenderPlugin'
$outRoot = 'D:\REA-LAB\03-decompiled\il'
$log = 'D:\REA-LAB\09-logs\il.log'
New-Item -ItemType Directory -Force -Path $outRoot | Out-Null

$pattern = '^(MatrixGold|MatrixGoldPlugin|MatrixGoldRenderPlugin|CommonServiceLocator|SharedTypes|MatrixCommon|Common(\..*)?|Localization(Core)?|CS[A-Z].*|CS|GV[A-Z].*|Gemvision.*|SuperView|Viewport2D|MeshAPI|DebugDraw|ToastNotifications.*|Stuller.*|EventSystemNuGetPackage|MatrixGoldSkin)$'
$summary = Import-Csv 'D:\REA-LAB\04-index\summary.csv'

$candidates = @{}
foreach ($row in $summary) {
    if ($row.managed -ne 'True') { continue }
    if ($row.assembly -cnotmatch $pattern) { continue }
    $full = Join-Path $root $row.file
    if (-not (Test-Path -LiteralPath $full)) { continue }
    $key = $row.assembly
    if (-not $candidates.ContainsKey($key) -or ($row.file -notmatch 'MatrixGoldPlugin\\|MatrixGoldRenderPlugin\\' -and $candidates[$key].file -match 'MatrixGoldPlugin\\|MatrixGoldRenderPlugin\\')) {
        $candidates[$key] = [pscustomobject]@{ assembly = $row.assembly; file = $row.file; full = $full }
    }
}

$rows = @()
foreach ($c in ($candidates.Values | Sort-Object assembly)) {
    $out = Join-Path $outRoot $c.assembly
    New-Item -ItemType Directory -Force -Path $out | Out-Null
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $output = ''
    try {
        $output = (& $ilspy -il -o $out -r $app -r $plugin -r $render --disable-updatecheck $c.full 2>&1 | Out-String)
        $code = $LASTEXITCODE
    } catch {
        $code = 1
        $output = $_.Exception.Message
    }
    $sw.Stop()
    $methods = 0
    $bytes = 0
    $produced = @(Get-ChildItem -LiteralPath $out -Filter *.il -File | Sort-Object Length -Descending)
    if ($produced.Count -gt 0) {
        $il = $produced[0].FullName
        $bytes = $produced[0].Length
        $methods = @(Select-String -LiteralPath $il -Pattern '^\s*\.method\b' -AllMatches).Count
    }
    $rows += [pscustomobject]@{ assembly = $c.assembly; exit = $code; methods = $methods; bytes = $bytes; seconds = [math]::Round($sw.Elapsed.TotalSeconds, 1) }
    "=== $($c.assembly) exit=$code methods=$methods bytes=$bytes $($sw.Elapsed.TotalSeconds)s ===" | Out-File -FilePath $log -Append -Encoding utf8
    if ($output.Trim().Length -gt 0) { $output | Out-File -FilePath $log -Append -Encoding utf8 }
    Write-Host ("{0}: exit={1} methods={2} bytes={3:N0}" -f $c.assembly, $code, $methods, $bytes)
}

$rows | Export-Csv -LiteralPath 'D:\REA-LAB\03-decompiled\il-index.csv' -NoTypeInformation -Encoding UTF8
$total = ($rows | Measure-Object methods -Sum).Sum
Write-Host ("TOTAL assemblies={0} methods={1} bytes={2:N1}MB" -f $rows.Count, $total, (($rows | Measure-Object bytes -Sum).Sum / 1MB))
