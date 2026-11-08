param([string]$Version = '1.1.0')
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$stage = Join-Path $PSScriptRoot 'stage'
$cache = Join-Path $PSScriptRoot 'cache'
$dist = Join-Path $repo 'dist'
New-Item -ItemType Directory -Force -Path $cache, $dist | Out-Null
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Force -Path $stage, "$stage\app", "$stage\runtime\php", "$stage\runtime\mysql", "$stage\prerequisites" | Out-Null
$downloads = @(
    @{name='php.zip'; url='https://downloads.php.net/~windows/releases/php-8.4.27-1-nts-Win32-vs17-x64.zip'; version='PHP 8.4.27-1 NTS x64'},
    @{name='mysql.zip'; url='https://cdn.mysql.com/Downloads/MySQL-8.4/mysql-8.4.13-winx64.zip'; version='MySQL Community 8.4.13 x64'},
    @{name='vc_redist.x64.exe'; url='https://aka.ms/vs/17/release/vc_redist.x64.exe'; version='Microsoft Visual C++ Redistributable x64'}
)
$manifest = @()
foreach ($item in $downloads) {
    $file = Join-Path $cache $item.name
    if (-not (Test-Path $file)) { Invoke-WebRequest $item.url -OutFile $file -UseBasicParsing }
    if ($item.name -eq 'vc_redist.x64.exe') {
        $sig = Get-AuthenticodeSignature $file
        if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'Microsoft Corporation') { throw 'Invalid Microsoft runtime signature.' }
    }
    $manifest += @{component=$item.version; url=$item.url; sha256=(Get-FileHash $file -Algorithm SHA256).Hash; bytes=(Get-Item $file).Length}
}
Expand-Archive "$cache\php.zip" "$stage\runtime\php" -Force
Expand-Archive "$cache\mysql.zip" "$cache\mysql-expanded" -Force
$mysql = Get-ChildItem "$cache\mysql-expanded" -Directory | Select-Object -First 1
foreach ($directory in @('bin','lib','share','docs')) { Copy-Item (Join-Path $mysql.FullName $directory) "$stage\runtime\mysql\$directory" -Recurse -Force }
Get-ChildItem "$stage\runtime\mysql" -Recurse -Filter '*.pdb' | Remove-Item -Force
foreach ($file in @('LICENSE','README')) { if (Test-Path (Join-Path $mysql.FullName $file)) { Copy-Item (Join-Path $mysql.FullName $file) "$stage\runtime\mysql" } }
Copy-Item "$cache\vc_redist.x64.exe" "$stage\prerequisites"
foreach ($directory in @('src','public','database','bin','tests')) { Copy-Item "$repo\$directory" "$stage\app\$directory" -Recurse }
Copy-Item "$repo\README.md" "$stage\app"
foreach ($file in @('launcher.ps1','windows-db.php')) { Copy-Item "$PSScriptRoot\$file" $stage }
# Windows PowerShell 5.1 uses the BOM to recognize Cyrillic script text.
[IO.File]::WriteAllText("$stage\launcher.ps1", (Get-Content "$PSScriptRoot\launcher.ps1" -Raw -Encoding UTF8), (New-Object Text.UTF8Encoding($true)))
$phpIni = @'
[PHP]
extension_dir="ext"
extension=pdo_mysql
extension=mbstring
date.timezone=Asia/Irkutsk
display_errors=Off
log_errors=On
default_charset=UTF-8
session.use_strict_mode=1
session.cookie_httponly=1
session.cookie_samesite=Lax
'@
[IO.File]::WriteAllText("$stage\runtime\php\php.ini", $phpIni, (New-Object Text.UTF8Encoding($false)))
# Use an absolute extension directory so launch working directory never matters.
$ini = (Get-Content "$stage\runtime\php\php.ini" -Raw).Replace('extension_dir="ext"', 'extension_dir="${PHP_EXTENSION_DIR}"')
[IO.File]::WriteAllText("$stage\runtime\php\php.ini", $ini, (New-Object Text.UTF8Encoding($false)))
$env:PHP_EXTENSION_DIR = "$stage\runtime\php\ext"
$vc = Start-Process "$stage\prerequisites\vc_redist.x64.exe" '/install /quiet /norestart' -Wait -PassThru
if ($vc.ExitCode -notin @(0,1638,3010)) { throw "Visual C++ prerequisite failed: $($vc.ExitCode)" }
$compiler = "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
& $compiler /nologo /target:winexe /platform:x64 /reference:System.Windows.Forms.dll /out:"$stage\LaundryQueue.exe" "$PSScriptRoot\Launcher.cs"
if ($LASTEXITCODE -ne 0) { throw 'Launcher compilation failed.' }
$manifest | ConvertTo-Json -Depth 5 | Set-Content "$stage\components.json" -Encoding UTF8
Copy-Item "$stage\components.json" "$dist\components.json"
$inno = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
if (-not (Test-Path $inno)) { $inno = "${env:ProgramFiles(x86)}\Inno Setup 7\ISCC.exe" }
if (-not (Test-Path $inno)) { throw 'Inno Setup compiler is required.' }
& $inno "$PSScriptRoot\setup.iss"
if ($LASTEXITCODE -ne 0) { throw 'Installer compilation failed.' }
$source = Join-Path $cache 'source\LaundryQueue'
New-Item -ItemType Directory -Force -Path $source | Out-Null
git -C $repo archive HEAD --format=zip --output="$cache\source-code.zip"
Expand-Archive "$cache\source-code.zip" $source -Force
Compress-Archive (Split-Path $source) "$dist\LaundryQueue-Sources-$Version.zip" -Force
Get-ChildItem $dist -File | Where-Object Name -ne 'SHA256SUMS.txt' | ForEach-Object { "$((Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower())  $($_.Name)" } | Set-Content "$dist\SHA256SUMS.txt" -Encoding ASCII
Write-Host "BUILD PASS: $dist"
