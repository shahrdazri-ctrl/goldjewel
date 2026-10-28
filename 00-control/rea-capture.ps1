param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$Target,
    [Parameter(Mandatory = $true)][string]$Bundle
)
$ErrorActionPreference = 'Continue'
$node = 'D:\REA-LAB\02-toolchain\node\node.exe'
$rea = 'D:\REA-LAB\02-toolchain\npm-global\node_modules\rea-agents\scripts\rea.mjs'
$env:NODE_OPTIONS = '--max-old-space-size=12288'
if (Test-Path $Bundle) { Remove-Item $Bundle -Force }
$summaryPath = $Bundle -replace '\.json$', '-summary.json'
$sw = [Diagnostics.Stopwatch]::StartNew()
$summary = & $node $rea inspect-managed-members $Target --detail summary --evidence-bundle $Bundle --json
$code = $LASTEXITCODE
$sw.Stop()
if ($summary) { $summary | Set-Content -LiteralPath $summaryPath -Encoding utf8 }
$size = 'missing'
if (Test-Path $Bundle) { $size = '{0:N1}MB' -f ((Get-Item $Bundle).Length / 1MB) }
Write-Host ("{0}: exit={1} elapsed={2:N1}s bundle={3}" -f $Name, $code, $sw.Elapsed.TotalSeconds, $size)
if (Test-Path $Bundle) {
    $o = Get-Content -Raw -LiteralPath $Bundle | ConvertFrom-Json
    $nr = $o.records[0].normalized_result
    $strings = 'null'
    if ($null -ne $nr.user_strings) { $strings = $nr.user_strings.Count }
    Write-Host ("  types={0} methods={1} fields={2} refs={3} calls={4} strings={5}" -f $nr.types.Count, $nr.methods.Count, $nr.fields.Count, $nr.member_refs.Count, $nr.call_edges.Count, $strings)
    Write-Host ("  coverage={0}" -f $nr.coverage.state)
}
exit $code
