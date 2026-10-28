. 'D:\REA-LAB\00-control\env.ps1'
$ErrorActionPreference = 'Continue'

$ilspy = 'D:\REA-LAB\02-toolchain\ilspy\ilspycmd.exe'
$root = 'D:\REA-LAB\01-target\mirror\Main'
$app = Join-Path $root 'MatrixGold'
$plugin = Join-Path $app 'MatrixGoldPlugin'
$render = Join-Path $app 'MatrixGoldRenderPlugin'
$outRoot = 'D:\REA-LAB\03-decompiled\raw'
$log = 'D:\REA-LAB\09-logs\decompile.log'
New-Item -ItemType Directory -Force -Path $outRoot | Out-Null

$pattern = '^(MatrixGold|MatrixGoldPlugin|MatrixGoldRenderPlugin|CommonServiceLocator|SharedTypes|MatrixCommon|Common(\..*)?|Localization(Core)?|CS[A-Z].*|CS|GV[A-Z].*|Gemvision.*|SuperView|Viewport2D|MeshAPI|DebugDraw|ToastNotifications.*|Stuller.*|EventSystemNuGetPackage|MatrixGoldSkin)$'
$summary = Import-Csv 'D:\REA-LAB\04-index\summary.csv'
$summaryPath = 'D:\REA-LAB\03-decompiled\decompile-summary.csv'
$existing = @{}
if (Test-Path $summaryPath) {
    foreach ($r in (Import-Csv $summaryPath)) { $existing[$r.assembly] = $r }
}

$candidates = @{}
foreach ($row in $summary) {
    if ($row.managed -ne 'True') { continue }
    if ($row.assembly -cnotmatch $pattern) { continue }
    $full = Join-Path $root $row.file
    if (-not (Test-Path -LiteralPath $full)) { continue }
    $key = $row.assembly
    # Prefer the top-level app copy over plugin/render duplicates.
    if (-not $candidates.ContainsKey($key) -or ($row.file -notmatch 'MatrixGoldPlugin\\|MatrixGoldRenderPlugin\\' -and $candidates[$key].file -match 'MatrixGoldPlugin\\|MatrixGoldRenderPlugin\\')) {
        $candidates[$key] = [pscustomobject]@{ assembly = $row.assembly; file = $row.file; full = $full }
    }
}

$rows = @($existing.Values)
foreach ($c in ($candidates.Values | Sort-Object assembly)) {
    $out = Join-Path $outRoot $c.assembly
    if (Test-Path (Join-Path $out "$($c.assembly).csproj")) {
        Write-Host "skip (exists): $($c.assembly)"
        continue
    }
    Write-Host "decompiling: $($c.full)"
    $start = Get-Date
    $output = ''
    try {
        $output = (& $ilspy -p -o $out -r $app -r $plugin -r $render --disable-updatecheck $c.full 2>&1 | Out-String)
        $code = $LASTEXITCODE
    } catch {
        $code = 1
        $output = $_.Exception.Message
    }
    $elapsed = [math]::Round(((Get-Date) - $start).TotalSeconds, 1)
    $cs = 0; $bytes = 0; $xaml = 0
    if (Test-Path $out) {
        $cs = @(Get-ChildItem $out -Recurse -File -Filter *.cs).Count
        $xaml = @(Get-ChildItem $out -Recurse -File -Filter *.xaml).Count
        $bytes = (Get-ChildItem $out -Recurse -File | Measure-Object Length -Sum).Sum
    }
    $rows = @($rows | Where-Object { $_.assembly -ne $c.assembly })
    $rows += [pscustomobject]@{ assembly = $c.assembly; exit = $code; cs = $cs; xaml = $xaml; bytes = $bytes; seconds = $elapsed }
    "=== $($c.assembly) exit=$code cs=$cs xaml=$xaml bytes=$bytes ${elapsed}s ===" | Out-File -FilePath $log -Append -Encoding utf8
    if ($output.Trim().Length -gt 0) { $output | Out-File -FilePath $log -Append -Encoding utf8 }
    if ($code -ne 0) { Write-Warning "ilspycmd exit $code for $($c.assembly)" }
}

$rows = @($rows | Sort-Object assembly)
$rows | Export-Csv -LiteralPath $summaryPath -NoTypeInformation -Encoding UTF8
$rows | Format-Table -AutoSize | Out-String -Width 140 | Write-Host
Write-Host ("TOTAL assemblies={0} cs={1} xaml={2} bytes={3:N1}MB" -f $rows.Count, (($rows | Measure-Object cs -Sum).Sum), (($rows | Measure-Object xaml -Sum).Sum), (($rows | Measure-Object bytes -Sum).Sum / 1MB))
