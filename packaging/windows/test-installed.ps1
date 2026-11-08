$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$evidence = Join-Path $repo 'installer-evidence'
New-Item -ItemType Directory -Force -Path $evidence | Out-Null
$installDir = Join-Path $env:ProgramFiles 'Dorm8LaundryQueue'
$dataRoot = Join-Path $env:LOCALAPPDATA 'Dorm8LaundryQueue'
$installer = (Get-ChildItem "$repo\dist\LaundryQueueSetup-*-x64.exe" | Select-Object -First 1).FullName
$results = New-Object Collections.Generic.List[object]
function Result($name, $detail) { $results.Add(@{check=$name; status='PASS'; detail=$detail}); Write-Host "PASS: $name - $detail" }
function Require($ok, $message) { if (-not $ok) { throw $message } }
function Capture($name) {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $bounds = [Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bitmap = New-Object Drawing.Bitmap($bounds.Width, $bounds.Height)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    $graphics.CopyFromScreen($bounds.Location, [Drawing.Point]::Empty, $bounds.Size)
    $bitmap.Save((Join-Path $evidence $name), [Drawing.Imaging.ImageFormat]::Png)
    $graphics.Dispose(); $bitmap.Dispose()
}
function Launch {
    Remove-Item "$dataRoot\state.json" -Force -ErrorAction SilentlyContinue
    Start-Process "$installDir\LaundryQueue.exe" '--headless --no-browser'
    for ($attempt=0; $attempt -lt 120; $attempt++) {
        if (Test-Path "$dataRoot\state.json") { return (Get-Content "$dataRoot\state.json" -Raw | ConvertFrom-Json) }
        Start-Sleep -Seconds 1
    }
    if (Test-Path "$dataRoot\launcher-error.log") { Get-Content "$dataRoot\launcher-error.log" }
    if (Test-Path "$dataRoot\mysql-error.log") { Get-Content "$dataRoot\mysql-error.log" -Tail 30 }
    throw 'Application failed to start.'
}
function Stop-App { Start-Process "$installDir\LaundryQueue.exe" '--stop' -Wait; Start-Sleep -Seconds 4 }
try {
    # This is a genuine screenshot of the installer wizard on the Windows runner.
    $wizard = Start-Process $installer '/LANG=russian /SP-' -PassThru
    Start-Sleep -Seconds 4
    Capture '01-installer-wizard.png'
    $wizard.Kill(); $wizard.WaitForExit()
    $install = Start-Process $installer ('/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /LOG="' + "$evidence\installation.log" + '"') -PassThru -Wait
    Require ($install.ExitCode -eq 0) "Installer exit: $($install.ExitCode)"
    Require (Test-Path "$installDir\LaundryQueue.exe") 'Launcher missing after install.'
    Require (Test-Path "$installDir\runtime\php\php.exe") 'Bundled PHP missing.'
    Require (Test-Path "$installDir\runtime\mysql\bin\mysqld.exe") 'Bundled MySQL missing.'
    Result 'Offline payload installation' 'Installer, application, PHP and MySQL installed from one EXE.'
    $state = Launch
    $config = Get-Content "$dataRoot\config.json" -Raw | ConvertFrom-Json
    $env:LAUNDRY_CONFIG = "$dataRoot\config.json"
    $env:PHP_EXTENSION_DIR = "$installDir\runtime\php\ext"
    $php = "$installDir\runtime\php\php.exe"
    $ini = "$installDir\runtime\php\php.ini"
    $page = Invoke-WebRequest $state.url -SessionVariable webSession -UseBasicParsing
    Require ($page.Content -match 'Электронная очередь в прачечную') 'Page title missing.'
    Require ($page.Content -notmatch 'Не удалось выполнить операцию') 'Database error on page.'
    Result 'Automatic first launch' 'Database schema and initial data created; HTTP 200.'
    & $php -c $ini "$installDir\windows-db.php" test-database
    Require ($LASTEXITCODE -eq 0) 'Test database setup failed.'
    $env:DB_HOST='127.0.0.1'; $env:DB_PORT=[string]$config.dbPort; $env:DB_DATABASE='laundry_installer_test'
    $env:DB_USERNAME='laundry_app'; $env:DB_PASSWORD=$config.appPassword
    & $php -c $ini "$installDir\app\tests\run.php" | Tee-Object "$evidence\booking-tests.txt"
    Require ($LASTEXITCODE -eq 0) 'Booking integration tests failed.'
    Copy-Item "$installDir\app\var\results-all.xml" $evidence
    Result 'Four booking integration tests' '4 passed, 0 failures, installed PHP and installed MySQL.'
    $token = [regex]::Match($page.Content, 'name="csrf" value="([^"]+)"').Groups[1].Value
    Require ($token.Length -gt 20) 'CSRF token missing.'
    $form = @{csrf=$token;student_id='1';machine_id='1';start='2031-02-12T10:00';end='2031-02-12T11:00'}
    $created = Invoke-WebRequest $state.url -Method Post -Body $form -WebSession $webSession -UseBasicParsing
    Require ($created.Content -match 'Создано бронирование') 'Booking through HTTP failed.'
    Require ($created.Content -match '2031-02-12 10:00:00') 'Created booking absent from page.'
    $env:LAUNDRY_TEST_URL = $state.url
    node "$PSScriptRoot\capture-app.cjs"
    Require ($LASTEXITCODE -eq 0) 'Application screenshot failed.'
    Result 'Browser booking' 'POST with CSRF created a booking and notification.'
    Stop-App
    $state = Launch
    $again = Invoke-WebRequest $state.url -UseBasicParsing
    Require ($again.Content -match '2031-02-12 10:00:00') 'Booking lost after restart.'
    Result 'Persistence after restart' 'Booking retained; initial data not duplicated.'
    Stop-App
    $reinstall = Start-Process $installer '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-' -PassThru -Wait
    Require ($reinstall.ExitCode -eq 0) 'Reinstall failed.'
    $state = Launch
    Require ((Invoke-WebRequest $state.url -UseBasicParsing).Content -match '2031-02-12 10:00:00') 'Reinstall erased booking.'
    Result 'Reinstallation' 'Existing user database preserved.'
    Stop-App
    $uninstall = Start-Process "$installDir\unins000.exe" '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART' -PassThru -Wait
    Require ($uninstall.ExitCode -eq 0) 'Uninstall failed.'
    Require (-not (Test-Path "$installDir\LaundryQueue.exe")) 'Application files remain after uninstall.'
    Require (Test-Path "$dataRoot\mysql-data") 'User database unexpectedly erased.'
    Result 'Uninstallation' 'Application removed; user database retained.'
    @{runner=(Get-CimInstance Win32_OperatingSystem).Caption; architecture=$env:PROCESSOR_ARCHITECTURE; results=$results; completed=(Get-Date).ToUniversalTime().ToString('o')} | ConvertTo-Json -Depth 6 | Set-Content "$evidence\verification.json" -Encoding UTF8
} catch {
    $_ | Out-String | Set-Content "$evidence\failure.txt" -Encoding UTF8
    if (Test-Path "$dataRoot\launcher-error.log") { Copy-Item "$dataRoot\launcher-error.log" $evidence }
    if (Test-Path "$dataRoot\mysql-error.log") { Copy-Item "$dataRoot\mysql-error.log" $evidence }
    throw
} finally { if (Test-Path "$installDir\LaundryQueue.exe") { try { Stop-App } catch { } } }
