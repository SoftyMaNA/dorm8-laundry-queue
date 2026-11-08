#define AppVersion "1.1.0"
[Setup]
AppId={{73DB743B-0D43-4D2B-96AD-92AC47EC13B4}
AppName=Электронная очередь в прачечную
AppVersion={#AppVersion}
AppPublisher=Общежитие №8 ИрГУПС
DefaultDirName={autopf}\Dorm8LaundryQueue
DefaultGroupName=Электронная очередь в прачечную
OutputDir=..\..\dist
OutputBaseFilename=LaundryQueueSetup-{#AppVersion}-x64
ArchitecturesAllowed=x64os
ArchitecturesInstallIn64BitMode=x64os
MinVersion=10.0
PrivilegesRequired=admin
WizardStyle=modern
Compression=lzma2/fast
SolidCompression=yes
UninstallDisplayIcon={app}\LaundryQueue.exe
SetupLogging=yes
CloseApplications=no
[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
[Tasks]
Name: "desktopicon"; Description: "Создать ярлык на рабочем столе"; Flags: checkedonce
[Files]
Source: "stage\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
[Icons]
Name: "{group}\Электронная очередь"; Filename: "{app}\LaundryQueue.exe"
Name: "{group}\Завершить работу очереди"; Filename: "{app}\LaundryQueue.exe"; Parameters: "--stop"
Name: "{group}\Удалить приложение"; Filename: "{uninstallexe}"
Name: "{commondesktop}\Электронная очередь"; Filename: "{app}\LaundryQueue.exe"; Tasks: desktopicon
[Run]
Filename: "{app}\prerequisites\vc_redist.x64.exe"; Parameters: "/install /quiet /norestart"; StatusMsg: "Подготовка компонентов Microsoft Visual C++..."; Flags: waituntilterminated
Filename: "{app}\LaundryQueue.exe"; Description: "Открыть электронную очередь"; Flags: nowait postinstall skipifsilent runasoriginaluser
[UninstallRun]
Filename: "{app}\LaundryQueue.exe"; Parameters: "--stop"; Flags: waituntilterminated; RunOnceId: "StopLaundry"
[Code]
function PrepareToInstall(var NeedsRestart: Boolean): String;
var ResultCode: Integer;
begin
  Result := '';
  if FileExists(ExpandConstant('{app}\LaundryQueue.exe')) then
  begin
    Exec(ExpandConstant('{app}\LaundryQueue.exe'), '--stop', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Sleep(3000);
  end;
end;
