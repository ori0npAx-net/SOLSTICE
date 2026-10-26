# Portable, project-local installations. No administrator privileges or PATH changes.
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = 'SilentlyContinue'
$runtime = Join-Path $PSScriptRoot '.runtime'
New-Item -ItemType Directory -Force $runtime | Out-Null
if (-not (Get-ChildItem $runtime -Directory -Filter 'jdk*' | Where-Object { Test-Path (Join-Path $_.FullName 'bin/java.exe') })) {
    $package = (Invoke-RestMethod 'https://api.adoptium.net/v3/assets/latest/21/hotspot?architecture=x64&image_type=jdk&os=windows&vendor=eclipse')[0].binary.package
    $archive = Join-Path $runtime 'java.zip'
    Write-Host 'Downloading Java 21 from Eclipse Adoptium…'
    Invoke-WebRequest $package.link -OutFile $archive -UseBasicParsing
    if ((Get-FileHash $archive -Algorithm SHA256).Hash.ToLower() -ne $package.checksum) { throw 'Java checksum mismatch.' }
    Expand-Archive $archive $runtime -Force
}
if (-not (Get-ChildItem $runtime -Directory -Filter 'mariadb*' | Where-Object { Test-Path (Join-Path $_.FullName 'bin/mariadbd.exe') })) {
    $base = 'https://archive.mariadb.org/mariadb-11.4.5/winx64-packages/'
    $archive = Join-Path $runtime 'mariadb.zip'
    Write-Host 'Downloading portable MariaDB…'
    Invoke-WebRequest ($base + 'mariadb-11.4.5-winx64.zip') -OutFile $archive -UseBasicParsing
    $sums = (Invoke-WebRequest ($base + 'sha256sums.txt') -UseBasicParsing).Content
    $expected = ($sums -split "`n" | Where-Object { $_ -match 'mariadb-11.4.5-winx64.zip$' }) -split '\s+' | Select-Object -First 1
    if ((Get-FileHash $archive -Algorithm SHA256).Hash.ToLower() -ne $expected) { throw 'MariaDB checksum mismatch.' }
    Expand-Archive $archive $runtime -Force
}
Write-Host 'Java and MariaDB runtimes are ready.'
