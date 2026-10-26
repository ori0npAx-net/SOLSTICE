# Maintain a 4 x 4 field. Back up before removing old 16 x 16 field positions.
$ErrorActionPreference = 'Stop'
$runtime = Join-Path $PSScriptRoot '.runtime'
$maria = Get-ChildItem $runtime -Directory -Filter 'mariadb*' | Select-Object -First 1
if (-not $maria) { throw 'The project-local MariaDB client is missing.' }
$rng = [Random]::new()
$offlineCount = $rng.Next(2, 6)
$offlineSlots = @(0..15 | Sort-Object { $rng.Next() } | Select-Object -First $offlineCount)
$statements = @('USE solar_tracker_db;', 'START TRANSACTION;')
$oldField = "model_name REGEXP '^Godot Field R(0[1-9]|1[0-6]) C(0[1-9]|1[0-6])$' AND model_name NOT REGEXP '^Godot Field R0[1-4] C0[1-4]$'"
$statements += "DELETE FROM SOLAR_PANEL WHERE $oldField;"
for ($row = 0; $row -lt 4; $row++) {
    for ($col = 0; $col -lt 4; $col++) {
        $name = 'Godot Field R{0:D2} C{1:D2}' -f ($row + 1), ($col + 1)
        $status = if (($row * 4 + $col) -in $offlineSlots) { 'Offline' } else { 'Active' }
        $statements += "INSERT INTO SOLAR_PANEL(model_name,capacity_watts,status) SELECT '$name',300,'$status' WHERE NOT EXISTS (SELECT 1 FROM SOLAR_PANEL WHERE model_name='$name');"
    }
}
$statements += 'COMMIT;'
$statements += Get-Content (Join-Path (Split-Path $PSScriptRoot -Parent) '6_simulation_history.sql') -Raw
$statements += "SELECT status,COUNT(*) AS panel_count FROM SOLAR_PANEL WHERE model_name REGEXP '^Godot Field R[0-9]{2} C[0-9]{2}$' GROUP BY status;"
$env:MYSQL_PWD = Get-Content (Join-Path $runtime 'db-root-password.txt') -Raw
try {
    $client = Join-Path $maria.FullName 'bin/mariadb.exe'
    $excess = & $client --host=127.0.0.1 --user=root --batch --skip-column-names --execute="SELECT COUNT(*) FROM solar_tracker_db.SOLAR_PANEL WHERE $oldField"
    if ($LASTEXITCODE -ne 0) { throw 'Could not inspect existing field. No panels changed.' }
    if ([int]$excess -gt 0) {
        $backups = Join-Path $runtime 'backups'
        New-Item -ItemType Directory -Force $backups | Out-Null
        $backup = Join-Path $backups ('before-4x4-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.sql')
        & (Join-Path $maria.FullName 'bin/mariadb-dump.exe') --host=127.0.0.1 --user=root --single-transaction --databases solar_tracker_db "--result-file=$backup"
        if ($LASTEXITCODE -ne 0 -or (Get-Item $backup).Length -eq 0) { throw 'Backup failed. No panels removed.' }
        Write-Host "Database backup saved to $backup"
    }
    $statements | & (Join-Path $maria.FullName 'bin/mariadb.exe') --host=127.0.0.1 --user=root
    if ($LASTEXITCODE -ne 0) { throw 'Could not create the field.' }
} finally { Remove-Item Env:MYSQL_PWD -ErrorAction SilentlyContinue }
