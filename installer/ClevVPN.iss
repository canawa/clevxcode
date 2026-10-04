; Inno Setup script for ClevVPN
; Requires: https://jrsoftware.org/isdl.php

#define AppName "ClevVPN"
#define AppPublisher "ClevVPN"
#define AppExe "ClevVPN.exe"
#define AppVersion "1.2.0"
#define PublishDir "..\dist\app"

[Setup]
AppId={{B5F9C3D2-0A4E-5B7F-C6D8-2E3F4A5B6C7D}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppPublisher} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL=https://t.me/clevsupport_bot
AppSupportURL=https://t.me/clevsupport_bot
AppCopyright=Copyright (C) {#AppPublisher}
DefaultDirName={autopf}\ClevVPN
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
OutputDir=..\dist
OutputBaseFilename=ClevVPN-Setup-{#AppVersion}
SetupIconFile=..\src\ClevVPN\Assets\app.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppPublisher}
VersionInfoVersion={#AppVersion}
VersionInfoCompany={#AppPublisher}
VersionInfoDescription=Установщик {#AppPublisher}
VersionInfoProductName={#AppPublisher}
VersionInfoProductVersion={#AppVersion}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"

[Tasks]
Name: "desktopicon"; Description: "Создать ярлык на рабочем столе"; GroupDescription: "Дополнительно:"

[Files]
Source: "{#PublishDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "Запустить {#AppName}"; Flags: nowait postinstall skipifsilent

[Registry]
Root: HKCR; Subkey: "clevvpn"; ValueType: string; ValueName: ""; ValueData: "URL:ClevVPN"; Flags: uninsdeletekey
Root: HKCR; Subkey: "clevvpn"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""; Flags: uninsdeletekey
Root: HKCR; Subkey: "clevvpn\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\{#AppExe},0"; Flags: uninsdeletekey
Root: HKCR; Subkey: "clevvpn\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExe}"" ""%1"""; Flags: uninsdeletekey
