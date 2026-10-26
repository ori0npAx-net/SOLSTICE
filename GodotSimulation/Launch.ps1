param([switch]$Editor, [switch]$BackendOnly)
$ErrorActionPreference = 'Stop'
$project = $PSScriptRoot
$repo = Split-Path $project -Parent
$runtime = Join-Path $project '.runtime'
$logs = Join-Path $project 'logs'
foreach ($required in @('Backend/Server.java','1_schema.sql','2_sample_data.sql','3_queries.sql','4_app_user.sql','6_simulation_history.sql')) {
    if (-not (Test-Path -LiteralPath (Join-Path $repo $required))) {
        throw "Keep GodotSimulation inside the complete Solar-Tracking-Web-Application folder. Missing: $required. Copy or download the rest of the repository too; the simulation uses its original backend and SQL files."
    }
}
New-Item -ItemType Directory -Force $runtime | Out-Null
New-Item -ItemType Directory -Force $logs | Out-Null
$javaReady = @(Get-ChildItem $runtime -Directory -Filter 'jdk*' | Where-Object { Test-Path (Join-Path $_.FullName 'bin/java.exe') }).Count -gt 0
$mariaReady = @(Get-ChildItem $runtime -Directory -Filter 'mariadb*' | Where-Object { Test-Path (Join-Path $_.FullName 'bin/mariadbd.exe') }).Count -gt 0
if (-not $javaReady -or -not $mariaReady) {
    Write-Host 'First-time setup: downloading missing Java/MariaDB runtimes. Internet access is required.'
    & (Join-Path $project 'Setup-Runtimes.ps1')
}

function Test-Port([int]$Port) {
    $client = New-Object System.Net.Sockets.TcpClient
    try { $client.Connect('127.0.0.1', $Port); return $true } catch { return $false } finally { $client.Dispose() }
}
function Wait-Port([int]$Port) {
    for ($attempt = 0; $attempt -lt 60; $attempt++) {
        if (Test-Port $Port) { return }
        Start-Sleep -Milliseconds 500
    }
    throw "Service on port $Port did not start. See $logs."
}
function Find-Godot {
    if ($env:GODOT_EXE -and (Test-Path -LiteralPath $env:GODOT_EXE)) { return $env:GODOT_EXE }
    $cmd = Get-Command godot,godot4 -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return $cmd.Source }
    $found = Get-ChildItem (Join-Path $env:USERPROFILE 'Downloads') -Filter 'Godot*_win64.exe' -Recurse -File -ErrorAction SilentlyContinue | Where-Object Name -NotMatch 'console' | Select-Object -First 1
    if ($found) { return $found.FullName }
    throw 'Godot was not found. Set GODOT_EXE to your Godot 4 executable.'
}

$javaFolder = Get-ChildItem $runtime -Directory -Filter 'jdk*' | Select-Object -First 1
$java = if ($javaFolder) { Join-Path $javaFolder.FullName 'bin/java.exe' } else { (Get-Command java -ErrorAction Stop).Source }
if (-not (Test-Port 3306)) {
    $maria = Get-ChildItem $runtime -Directory -Filter 'mariadb*' | Select-Object -First 1
    if (-not $maria) { throw 'Start your existing MariaDB/MySQL database, or run Setup-Runtimes.ps1 first.' }
    $bin = Join-Path $maria.FullName 'bin'
    $data = Join-Path $runtime 'database'
    $secretPath = Join-Path $runtime 'db-root-password.txt'
    if (-not (Test-Path (Join-Path $data 'mysql'))) {
        $password = [Guid]::NewGuid().ToString('N')
        Set-Content -LiteralPath $secretPath -Value $password -NoNewline
        & (Join-Path $bin 'mariadb-install-db.exe') "--datadir=$data" "--password=$password" --port=3306 | Out-File (Join-Path $logs 'database-init.log')
        if ($LASTEXITCODE -ne 0) { throw 'Database initialization failed. Check database-init.log.' }
    }
    $config = Join-Path $runtime 'database.ini'
    @"
[mysqld]
basedir=$($maria.FullName.Replace('\','/'))
datadir=$($data.Replace('\','/'))
port=3306
bind-address=127.0.0.1
"@ | Set-Content -LiteralPath $config
    $process = Start-Process (Join-Path $bin 'mariadbd.exe') -ArgumentList "--defaults-file=`"$config`"",'--console' -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $logs 'database.log') -RedirectStandardError (Join-Path $logs 'database-error.log')
    Set-Content (Join-Path $runtime 'database.pid') $process.Id
    Wait-Port 3306
    # Initialize ONLY our new portable database. Existing tables are never reset.
    $password = Get-Content -LiteralPath $secretPath -Raw
    $env:MYSQL_PWD = $password
    try {
        $client = Join-Path $bin 'mariadb.exe'
        $exists = & $client --host=127.0.0.1 --user=root --batch --skip-column-names --execute="SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name='solar_tracker_db'"
        if ($LASTEXITCODE -ne 0) { throw 'Could not access the local database.' }
        if ([int]$exists -eq 0) {
            $sql = @('1_schema.sql','2_sample_data.sql','3_queries.sql','4_app_user.sql') | ForEach-Object { Get-Content (Join-Path $repo $_) -Raw }
            $sql | & $client --host=127.0.0.1 --user=root | Out-File (Join-Path $logs 'schema-init.log')
            if ($LASTEXITCODE -ne 0) { throw 'Original database scripts failed. Check schema-init.log.' }
        }
    } finally { Remove-Item Env:MYSQL_PWD -ErrorAction SilentlyContinue }
}

# Apply additive history migration before starting the updated server.
$databasePidFile = Join-Path $runtime 'database.pid'
if (Test-Path -LiteralPath $databasePidFile) {
    $ownedDatabase = Get-Process -Id ([int](Get-Content $databasePidFile)) -ErrorAction SilentlyContinue
    if ($ownedDatabase -and $ownedDatabase.Path -and $ownedDatabase.Path.StartsWith($runtime, [StringComparison]::OrdinalIgnoreCase)) {
        & (Join-Path $project 'Create-Field.ps1')
    }
}
$serverHash = (Get-FileHash (Join-Path $repo 'Backend/Server.java') -Algorithm SHA256).Hash
$hashPath = Join-Path $runtime 'backend-source.sha256'
$backendPidFile = Join-Path $runtime 'backend.pid'
if ((Test-Port 8080) -and (Test-Path $backendPidFile) -and ((-not (Test-Path $hashPath)) -or (Get-Content $hashPath) -ne $serverHash)) {
    $ownedBackend = Get-Process -Id ([int](Get-Content $backendPidFile)) -ErrorAction SilentlyContinue
    if ($ownedBackend -and $ownedBackend.Path -and $ownedBackend.Path.StartsWith($runtime, [StringComparison]::OrdinalIgnoreCase)) {
        Stop-Process -Id $ownedBackend.Id
        $ownedBackend.WaitForExit(5000) | Out-Null
    }
}
if (-not (Test-Port 8080)) {
    $process = Start-Process $java -WorkingDirectory $repo -ArgumentList '-cp','"Backend/lib/*"','Backend/Server.java' -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $logs 'backend.log') -RedirectStandardError (Join-Path $logs 'backend-error.log')
    Set-Content (Join-Path $runtime 'backend.pid') $process.Id
    Set-Content $hashPath $serverHash
    Wait-Port 8080
}
$health = $null
for ($attempt = 0; $attempt -lt 20; $attempt++) {
    try {
        $health = Invoke-RestMethod 'http://127.0.0.1:8080/api/health' -TimeoutSec 5
        if ($health[0].database_status -eq 'connected') { break }
    } catch { if ($attempt -eq 19) { throw "Backend/database connection failed. Check $logs. $($_.Exception.Message)" } }
    Start-Sleep -Milliseconds 500
}
if ($health[0].database_status -ne 'connected') { throw 'The existing backend is not connected to the database.' }
Write-Host 'Database and original Java backend are ready.'
if (-not $BackendOnly) {
    $godot = Find-Godot
    $arguments = @('--path', "`"$project`"")
    if ($Editor) { $arguments += '--editor' }
    Start-Process $godot -ArgumentList $arguments -WorkingDirectory $project
    Write-Host 'Godot simulation opened. The website remains at http://localhost:8080.'
}
