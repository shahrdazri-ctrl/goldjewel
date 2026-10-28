$ErrorActionPreference = 'Continue'
. 'D:\REA-LAB\00-control\env.ps1'
. 'D:\REA-LAB\00-control\retry.ps1'

$log = 'D:\REA-LAB\09-logs\install-tools.log'
"=== install started $(Get-Date -Format o) ===" | Out-File -FilePath $log -Encoding utf8

Write-Host '--- npm install -g rea-agents ---'
& "$env:LAB\02-toolchain\node\npm.cmd" install -g rea-agents@latest --no-fund --no-audit *>&1 | Tee-Object -FilePath $log -Append

Write-Host '--- rea version ---'
& "$env:LAB\02-toolchain\npm-global\rea.cmd" --version --json *>&1 | Tee-Object -FilePath $log -Append

Write-Host '--- dotnet tool install ilspycmd ---'
& dotnet tool install ilspycmd --tool-path "$env:LAB\02-toolchain\ilspy" --add-source https://api.nuget.org/v3/index.json *>&1 | Tee-Object -FilePath $log -Append

Write-Host '--- ilspycmd version ---'
& "$env:LAB\02-toolchain\ilspy\ilspycmd.exe" --version *>&1 | Tee-Object -FilePath $log -Append

Write-Host '--- done ---'
