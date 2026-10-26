$ErrorActionPreference = 'Stop'
$runtime = Join-Path $PSScriptRoot '.runtime'
foreach ($name in @('backend','database')) {
    $file = Join-Path $runtime "$name.pid"
    if (Test-Path -LiteralPath $file) {
        $servicePid = [int](Get-Content -LiteralPath $file)
        $process = Get-Process -Id $servicePid -ErrorAction SilentlyContinue
        # A recycled PID must never cause an unrelated process to be stopped.
        if ($process -and $process.Path -and $process.Path.StartsWith($runtime, [StringComparison]::OrdinalIgnoreCase)) {
            if ($name -eq 'database') {
                $maria = Get-ChildItem $runtime -Directory -Filter 'mariadb*' | Select-Object -First 1
                $env:MYSQL_PWD = Get-Content (Join-Path $runtime 'db-root-password.txt') -Raw
                try { & (Join-Path $maria.FullName 'bin/mariadb-admin.exe') --host=127.0.0.1 --user=root shutdown }
                finally { Remove-Item Env:MYSQL_PWD -ErrorAction SilentlyContinue }
            } else { Stop-Process -Id $servicePid }
        }
        Remove-Item -LiteralPath $file
    }
}
