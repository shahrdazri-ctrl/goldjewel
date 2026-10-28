$ErrorActionPreference = 'Stop'
. 'D:\REA-LAB\00-control\retry.ps1'

$root = 'D:\REA-LAB\01-target\mirror\Main'
$out = 'D:\REA-LAB\01-target\target-manifest.csv'
$rows = New-Object System.Collections.Generic.List[object]

Get-ChildItem -LiteralPath $root -Recurse -File -Force | ForEach-Object {
    $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    $rows.Add([pscustomobject]@{
        relative_path = $_.FullName.Substring($root.Length + 1)
        bytes = $_.Length
        sha256 = $hash
        last_write_utc = $_.LastWriteTimeUtc.ToString('o')
    })
}
$rows | Export-Csv -LiteralPath $out -NoTypeInformation -Encoding UTF8

$total = ($rows | Measure-Object bytes -Sum).Sum
$byExt = $rows | Group-Object { [System.IO.Path]::GetExtension($_.relative_path).ToLower() } |
    ForEach-Object { [pscustomobject]@{ ext = $_.Name; count = $_.Count; bytes = ($_.Group | Measure-Object bytes -Sum).Sum } } |
    Sort-Object bytes -Descending
$byExt | Export-Csv -LiteralPath 'D:\REA-LAB\01-target\extensions.csv' -NoTypeInformation -Encoding UTF8

Write-Host ("Files hashed : {0}" -f $rows.Count)
Write-Host ("Total bytes  : {0}" -f (Format-Bytes ([int64]$total)))
Write-Host ("Manifest     : {0}" -f $out)
