param([switch]$Stop, [switch]$NoBrowser, [switch]$Headless)
$ErrorActionPreference = 'Stop'
$appRoot = $PSScriptRoot
$env:PHP_EXTENSION_DIR = Join-Path $appRoot 'runtime\php\ext'
$dataRoot = Join-Path $env:LOCALAPPDATA 'Dorm8LaundryQueue'
$configPath = Join-Path $dataRoot 'config.json'
$statePath = Join-Path $dataRoot 'state.json'
New-Item -ItemType Directory -Force -Path $dataRoot | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)
function Save-Json($path, $value) { [IO.File]::WriteAllText($path, ($value | ConvertTo-Json), $utf8) }
function Read-Json($path) { Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json }
function Free-Port {
    $listener = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, 0)
    $listener.Start(); $port = $listener.LocalEndpoint.Port; $listener.Stop(); return $port
}
function Secret {
    $bytes = New-Object byte[] 24
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($bytes); $rng.Dispose()
    return ([BitConverter]::ToString($bytes)).Replace('-', '').ToLowerInvariant()
}
function Run-Php($file, $extraArgs = @()) {
    $env:LAUNDRY_CONFIG = $configPath
    & (Join-Path $appRoot 'runtime\php\php.exe') -c (Join-Path $appRoot 'runtime\php\php.ini') $file @extraArgs
    if ($LASTEXITCODE -ne 0) { throw "PHP operation failed: $file (exit $LASTEXITCODE)" }
}
function Stop-Application {
    if (Test-Path $configPath) {
        try { Run-Php (Join-Path $appRoot 'windows-db.php') @('shutdown') } catch { }
    }
    if (Test-Path $statePath) {
        $old = Read-Json $statePath
        # Terminate only the PHP process launched from this application's runtime.
        $process = Get-Process -Id $old.phpPid -ErrorAction SilentlyContinue
        if ($process -and $process.Path -eq (Join-Path $appRoot 'runtime\php\php.exe')) { $process.Kill() }
        Remove-Item -LiteralPath $statePath -Force -ErrorAction SilentlyContinue
    }
}
if ($Stop) { Stop-Application; exit 0 }
$mutex = New-Object Threading.Mutex($false, 'Local\Dorm8LaundryQueue')
if (-not $mutex.WaitOne(0)) {
    if ((Test-Path $statePath) -and -not $NoBrowser) {
        $running = Read-Json $statePath
        Start-Process $running.url
    }
    exit 0
}
$mysqlProcess = $null; $phpProcess = $null
try {
    if (-not (Test-Path $configPath)) {
        # Credentials and writable database belong to the current Windows user.
        $config = @{ dbPort = (Free-Port); httpPort = (Free-Port); rootPassword = (Secret); appPassword = (Secret) }
        Save-Json $configPath $config
    }
    $config = Read-Json $configPath
    # Re-select HTTP port if another application has taken the previous port.
    $config.httpPort = Free-Port
    Save-Json $configPath $config
    $mysqlHome = Join-Path $appRoot 'runtime\mysql'
    $dbDir = Join-Path $dataRoot 'mysql-data'
    $mysqlExe = Join-Path $mysqlHome 'bin\mysqld.exe'
    if (-not (Test-Path (Join-Path $dbDir 'mysql'))) {
        $config.dbPort = Free-Port
        Save-Json $configPath $config
        $init = Start-Process $mysqlExe -ArgumentList @('--no-defaults', '--initialize-insecure', ('--basedir="' + $mysqlHome + '"'), ('--datadir="' + $dbDir + '"')) -PassThru -Wait -WindowStyle Hidden
        if ($init.ExitCode -ne 0) { throw 'MySQL data initialization failed. See mysql-data error log.' }
    }
    $iniPath = Join-Path $dataRoot 'mysql.ini'
    $settings = @"
[mysqld]
basedir=$($mysqlHome.Replace('\','/'))
datadir=$($dbDir.Replace('\','/'))
bind-address=127.0.0.1
port=$($config.dbPort)
mysqlx=0
skip-log-bin
innodb-buffer-pool-size=64M
log-error=$((Join-Path $dataRoot 'mysql-error.log').Replace('\','/'))
"@
    [IO.File]::WriteAllText($iniPath, $settings, $utf8)
    $setupSql = Join-Path $dataRoot 'initialize.sql'
    $readyPath = Join-Path $dataRoot 'database-ready'
    $mysqlArguments = @('--defaults-file="' + $iniPath + '"')
    if (-not (Test-Path $readyPath)) {
        $sql = "ALTER USER 'root'@'localhost' IDENTIFIED BY '$($config.rootPassword)';`nCREATE DATABASE IF NOT EXISTS laundry_queue CHARACTER SET utf8mb4;`nCREATE USER IF NOT EXISTS 'laundry_app'@'127.0.0.1' IDENTIFIED BY '$($config.appPassword)';`nGRANT ALL ON laundry_queue.* TO 'laundry_app'@'127.0.0.1';`n"
        [IO.File]::WriteAllText($setupSql, $sql, $utf8)
        $mysqlArguments += '--init-file="' + $setupSql + '"'
    }
    $mysqlProcess = Start-Process $mysqlExe -ArgumentList $mysqlArguments -PassThru -WindowStyle Hidden
    $env:LAUNDRY_CONFIG = $configPath
    $ready = $false
    for ($attempt = 0; $attempt -lt 90; $attempt++) {
        & (Join-Path $appRoot 'runtime\php\php.exe') -c (Join-Path $appRoot 'runtime\php\php.ini') (Join-Path $appRoot 'windows-db.php') ping 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { $ready = $true; break }
        if ($mysqlProcess.HasExited) { throw 'MySQL exited before readiness. See mysql-error.log.' }
        Start-Sleep -Milliseconds 500
    }
    if (-not $ready) { throw 'MySQL readiness timeout.' }
    Run-Php (Join-Path $appRoot 'windows-db.php') @('prepare')
    [IO.File]::WriteAllText($readyPath, 'ready', $utf8)
    Remove-Item -LiteralPath $setupSql -Force -ErrorAction SilentlyContinue
    $env:DB_HOST = '127.0.0.1'; $env:DB_PORT = [string]$config.dbPort
    $env:DB_DATABASE = 'laundry_queue'; $env:DB_USERNAME = 'laundry_app'; $env:DB_PASSWORD = $config.appPassword
    $env:PHP_SESSION_SAVE_PATH = Join-Path $dataRoot 'sessions'
    New-Item -ItemType Directory -Force -Path $env:PHP_SESSION_SAVE_PATH | Out-Null
    $url = "http://127.0.0.1:$($config.httpPort)/"
    $phpArgs = @('-c', ('"' + (Join-Path $appRoot 'runtime\php\php.ini') + '"'), '-d', ('session.save_path="' + $env:PHP_SESSION_SAVE_PATH + '"'), '-S', "127.0.0.1:$($config.httpPort)", '-t', ('"' + (Join-Path $appRoot 'app\public') + '"'))
    $phpProcess = Start-Process (Join-Path $appRoot 'runtime\php\php.exe') -ArgumentList $phpArgs -WorkingDirectory (Join-Path $appRoot 'app') -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $dataRoot 'web-output.log') -RedirectStandardError (Join-Path $dataRoot 'web-error.log')
    $webReady = $false
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        try { $response = Invoke-WebRequest $url -UseBasicParsing -TimeoutSec 2; if ($response.StatusCode -eq 200) { $webReady = $true; break } } catch { }
        Start-Sleep -Milliseconds 300
    }
    if (-not $webReady) { throw 'Application web server readiness timeout.' }
    Save-Json $statePath @{ url = $url; phpPid = $phpProcess.Id; mysqlPid = $mysqlProcess.Id; supervisorPid = $PID; appRoot = $appRoot }
    if (-not $NoBrowser) { Start-Process $url }
    if ($Headless) {
        while ((Test-Path $statePath) -and -not $phpProcess.HasExited -and -not $mysqlProcess.HasExited) { Start-Sleep -Seconds 1 }
    } else {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        $tray = New-Object Windows.Forms.NotifyIcon
        $tray.Icon = [Drawing.SystemIcons]::Application
        $tray.Text = 'Электронная очередь в прачечную'
        $menu = New-Object Windows.Forms.ContextMenuStrip
        $open = $menu.Items.Add('Открыть очередь')
        $open.add_Click({ Start-Process $url })
        $exitItem = $menu.Items.Add('Завершить работу')
        $exitItem.add_Click({ [Windows.Forms.Application]::ExitThread() })
        $tray.ContextMenuStrip = $menu
        $tray.add_DoubleClick({ Start-Process $url })
        $tray.Visible = $true
        $timer = New-Object Windows.Forms.Timer
        $timer.Interval = 1000
        $timer.add_Tick({ if (-not (Test-Path $statePath)) { [Windows.Forms.Application]::ExitThread() } })
        $timer.Start()
        [Windows.Forms.Application]::Run()
        $timer.Dispose(); $tray.Dispose()
    }
} catch {
    $_ | Out-String | Add-Content (Join-Path $dataRoot 'launcher-error.log') -Encoding UTF8
    if (-not $Headless) { Add-Type -AssemblyName System.Windows.Forms; [Windows.Forms.MessageBox]::Show("Не удалось запустить очередь. Подробности: $dataRoot\launcher-error.log", 'Электронная очередь') | Out-Null }
    exit 1
} finally {
    Stop-Application
    if ($phpProcess -and -not $phpProcess.HasExited) { $phpProcess.Kill() }
    if ($mysqlProcess -and -not $mysqlProcess.HasExited) { $mysqlProcess.WaitForExit(15000) | Out-Null }
    $mutex.ReleaseMutex(); $mutex.Dispose()
}
