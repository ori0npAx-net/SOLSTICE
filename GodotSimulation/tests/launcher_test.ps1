# Regression: a copied project without .runtime invokes setup before discovery.
# Uses placeholder runtimes plus the already-running local backend; no downloads.
$ErrorActionPreference = 'Stop'
$project = Split-Path $PSScriptRoot -Parent
$repo = Split-Path $project -Parent
$fixture = Join-Path $project ('.runtime/launcher-test-' + [Guid]::NewGuid().ToString('N'))
$simulation = Join-Path $fixture 'GodotSimulation'
New-Item -ItemType Directory -Force $simulation,(Join-Path $fixture 'Backend') | Out-Null
Copy-Item (Join-Path $project 'Launch.ps1') $simulation
foreach ($file in @('1_schema.sql','2_sample_data.sql','3_queries.sql','4_app_user.sql','6_simulation_history.sql','Backend/Server.java')) {
    Copy-Item (Join-Path $repo $file) (Join-Path $fixture $file)
}
@'
$runtime = Join-Path $PSScriptRoot '.runtime'
New-Item -ItemType Directory -Force (Join-Path $runtime 'jdk-test/bin'),(Join-Path $runtime 'mariadb-test/bin') | Out-Null
New-Item -ItemType File (Join-Path $runtime 'jdk-test/bin/java.exe'),(Join-Path $runtime 'mariadb-test/bin/mariadbd.exe'),(Join-Path $runtime 'setup-invoked') | Out-Null
'@ | Set-Content (Join-Path $simulation 'Setup-Runtimes.ps1')
if (Test-Path (Join-Path $simulation '.runtime')) { throw 'Fixture must start without runtime folder.' }
& (Join-Path $simulation 'Launch.ps1') -BackendOnly
if (-not (Test-Path (Join-Path $simulation '.runtime/setup-invoked'))) { throw 'Missing runtime did not trigger setup.' }
& (Join-Path $simulation 'Launch.ps1') -BackendOnly
Write-Host 'PASS: missing runtime triggers setup; subsequent launch reuses installed runtimes.'
