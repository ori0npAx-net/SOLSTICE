# Add a persistent 16 x 16 field without altering existing panels or schema.
$ErrorActionPreference = 'Stop'
$runtime = Join-Path $PSScriptRoot '.runtime'
$maria = Get-ChildItem $runtime -Directory -Filter 'mariadb*' | Select-Object -First 1
if (-not $maria) { throw 'The project-local MariaDB client is missing.' }
$rng = [Random]::new()
$offlineCount = $rng.Next(16, 65)
$offlineSlots = @(0..255 | Sort-Object { $rng.Next() } | Select-Object -First $offlineCount)
$statements = @('USE solar_tracker_db;', 'START TRANSACTION;')
for ($row = 0; $row -lt 16; $row++) {
    for ($col = 0; $col -lt 16; $col++) {
        $name = 'Godot Field R{0:D2} C{1:D2}' -f ($row + 1), ($col + 1)
        $status = if (($row * 16 + $col) -in $offlineSlots) { 'Offline' } else { 'Active' }
        $statements += "INSERT INTO SOLAR_PANEL(model_name,capacity_watts,status) SELECT '$name',300,'$status' WHERE NOT EXISTS (SELECT 1 FROM SOLAR_PANEL WHERE model_name='$name');"
    }
}
$statements += 'COMMIT;'
$statements += "SELECT status,COUNT(*) AS panel_count FROM SOLAR_PANEL WHERE model_name REGEXP '^Godot Field R[0-9]{2} C[0-9]{2}$' GROUP BY status;"
$env:MYSQL_PWD = Get-Content (Join-Path $runtime 'db-root-password.txt') -Raw
try {
    $statements | & (Join-Path $maria.FullName 'bin/mariadb.exe') --host=127.0.0.1 --user=root
    if ($LASTEXITCODE -ne 0) { throw 'Could not create the field.' }
} finally { Remove-Item Env:MYSQL_PWD -ErrorAction SilentlyContinue }
