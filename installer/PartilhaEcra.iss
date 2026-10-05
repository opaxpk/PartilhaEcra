; Instalador Windows da PartilhaEcra (Inno Setup 6).
; Compilado pelo GitHub Actions:  ISCC.exe /DAppVersion=1.2.3 installer\PartilhaEcra.iss
; Instala no perfil do utilizador (sem pedir administrador), o que permite
; que a própria app se atualize sozinha em modo silencioso.

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

[Setup]
AppId={{8E6C2B1A-5F4D-4C3B-9A7E-2D1F0B6C9E41}
AppName=PartilhaEcra
AppVersion={#AppVersion}
AppVerName=PartilhaEcra {#AppVersion}
AppPublisher=opaxpk
AppPublisherURL=https://github.com/opaxpk/PartilhaEcra
DefaultDirName={localappdata}\Programs\PartilhaEcra
DisableProgramGroupPage=yes
DisableDirPage=yes
PrivilegesRequired=lowest
OutputDir=..\dist
OutputBaseFilename=PartilhaEcra-Setup
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\PartilhaEcra.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "portuguese"; MessagesFile: "compiler:Languages\Portuguese.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\PartilhaEcra"; Filename: "{app}\PartilhaEcra.exe"
Name: "{autodesktop}\PartilhaEcra"; Filename: "{app}\PartilhaEcra.exe"; Tasks: desktopicon

[Run]
; Sem "skipifsilent": depois de uma atualização automática (modo silencioso) a app volta a abrir.
Filename: "{app}\PartilhaEcra.exe"; Description: "{cm:LaunchProgram,PartilhaEcra}"; Flags: nowait postinstall
