/// PowerShell and shell script templates for Windows OpenSSH pairing,
/// Session 1 GUI execution, screenshots, power management, and smart postBuild hooks.
class PowerShellTemplates {
  const PowerShellTemplates._();

  /// Generates the PowerShell script that enables OpenSSH Server on Windows 11
  /// and authorizes the host's SSH public key with locale-independent SIDs.
  static String sshPairingScript(String sshPublicKey) {
    final escapedKey = sshPublicKey.trim().replaceAll('"', '');
    return '''
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 -ErrorAction SilentlyContinue | Out-Null
Start-Service sshd
Set-Service -Name sshd -StartupType 'Automatic'
New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 -ErrorAction SilentlyContinue | Out-Null

\$k = "$escapedKey"
New-Item -Force -ItemType Directory "\$env:USERPROFILE\\.ssh" | Out-Null
Set-Content -Path "\$env:USERPROFILE\\.ssh\\authorized_keys" -Value \$k -Encoding Ascii
Set-Content -Path "C:\\ProgramData\\ssh\\administrators_authorized_keys" -Value \$k -Encoding Ascii
icacls.exe "C:\\ProgramData\\ssh\\administrators_authorized_keys" /inheritance:r /grant "*S-1-5-32-544:F" /grant "*S-1-5-18:F" | Out-Null
Restart-Service sshd
Write-Host "SUCCESS! OpenSSH Server enabled and SSH key authorized!" -ForegroundColor Green
Write-Host ("Windows User: " + (whoami)) -ForegroundColor Cyan
''';
  }

  /// Generates `session1_runner.ps1` which runs in Windows Interactive Session 1
  /// via Task Scheduler (`/IT`), sets `FLUTTER_ENGINE_SWITCHES`, and keeps the
  /// Task Scheduler Job Object alive until `running.lock` is removed or the app exits.
  /// Reads the active `appName` dynamically from `active_app.txt` if present.
  static String session1RunnerScript({
    required String remoteBaseDir,
    required String defaultAppName,
  }) {
    return '''
\$ErrorActionPreference = "SilentlyContinue"
\$dir = "$remoteBaseDir"
\$appName = "$defaultAppName"
if (Test-Path "\$dir\\active_app.txt") {
  \$readApp = (Get-Content "\$dir\\active_app.txt" -Raw).Trim()
  if (\$readApp.Length -gt 0) { \$appName = \$readApp }
}
\$appDir = "\$dir\\runners\\\$appName"
if (!(Test-Path "\$appDir\\\$appName.exe") -and (Test-Path "\$dir\\\$appName\\\$appName.exe")) {
  \$appDir = "\$dir\\\$appName"
}
\$outLog = "\$dir\\app_out.log"
\$errLog = "\$dir\\app_err.log"

\$switches = @(
  "enable-dart-profiling=true",
  "enable-checked-mode=true",
  "verify-entry-points=true"
)
if (Test-Path "\$dir\\engine_switches.txt") {
  \$raw = (Get-Content "\$dir\\engine_switches.txt" -Raw).Trim()
  if (\$raw.Length -gt 0) {
    \$parsed = \$raw -split "\\s+" | ForEach-Object { \$_ -replace "^--", "" } | Where-Object { \$_ -ne "" }
    if (\$parsed.Count -gt 0) {
      \$switches = @(\$parsed)
    }
  }
}

\$env:FLUTTER_ENGINE_SWITCHES = \$switches.Count.ToString()
for (\$i = 0; \$i -lt \$switches.Count; \$i++) {
  \$idx = \$i + 1
  Set-Item -Path "Env:\\FLUTTER_ENGINE_SWITCH_\$idx" -Value \$switches[\$i]
}

\$proc = Start-Process -FilePath "\$appDir\\\$appName.exe" `
  -WorkingDirectory \$appDir `
  -RedirectStandardOutput \$outLog `
  -RedirectStandardError \$errLog `
  -WindowStyle Normal `
  -PassThru

\$proc.Id.ToString() | Set-Content -Path "\$dir\\active_app.pid" -Encoding Ascii

while ((Test-Path "\$dir\\running.lock") -and (!\$proc.HasExited)) {
  Start-Sleep -Milliseconds 500
}

if (!\$proc.HasExited) {
  Stop-Process -Id \$proc.Id -Force -ErrorAction SilentlyContinue
}
Remove-Item "\$dir\\active_app.pid" -Force -ErrorAction SilentlyContinue
''';
  }

  /// Generates `run_debug.ps1` invoked over SSH by Flutter custom-devices `runDebug`.
  /// Accepts the first argument as `appName` (or falls back to `defaultAppName`).
  static String runDebugScript({
    required String remoteBaseDir,
    required String defaultAppName,
    required String scheduledTaskName,
  }) {
    return '''
\$ErrorActionPreference = "SilentlyContinue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
\$dir = "$remoteBaseDir"
\$outLog = "\$dir\\app_out.log"
\$errLog = "\$dir\\app_err.log"

\$appName = "$defaultAppName"
if (Test-Path "\$dir\\active_app.txt") {
  \$readApp = (Get-Content "\$dir\\active_app.txt" -Raw).Trim()
  if (\$readApp.Length -gt 0) { \$appName = \$readApp }
}

Remove-Item "\$dir\\running.lock" -Force -ErrorAction SilentlyContinue
Stop-Process -Name \$appName -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 300

Remove-Item \$outLog -Force -ErrorAction SilentlyContinue
Remove-Item \$errLog -Force -ErrorAction SilentlyContinue
(\$args -join " ") | Set-Content -Path "\$dir\\engine_switches.txt" -Encoding Ascii
"running" | Set-Content -Path "\$dir\\running.lock" -Encoding Ascii

try {
  schtasks /Run /TN "$scheduledTaskName" | Out-Null

  \$outPos = 0
  \$errPos = 0
  \$started = \$false
  \$waitCount = 0

  while (\$true) {
    if (Test-Path \$outLog) {
      \$fs = [System.IO.File]::Open(\$outLog, 'Open', 'Read', 'ReadWrite')
      if (\$fs.Length -gt \$outPos) {
        \$fs.Seek(\$outPos, 'Begin') | Out-Null
        \$sr = New-Object System.IO.StreamReader(\$fs, [System.Text.Encoding]::UTF8)
        \$text = \$sr.ReadToEnd()
        \$outPos = \$fs.Position
        if (\$text.Length -gt 0) {
          [Console]::Out.Write(\$text)
          [Console]::Out.Flush()
        }
      }
      \$fs.Close()
    }
    if (Test-Path \$errLog) {
      \$fs2 = [System.IO.File]::Open(\$errLog, 'Open', 'Read', 'ReadWrite')
      if (\$fs2.Length -gt \$errPos) {
        \$fs2.Seek(\$errPos, 'Begin') | Out-Null
        \$sr2 = New-Object System.IO.StreamReader(\$fs2, [System.Text.Encoding]::UTF8)
        \$text2 = \$sr2.ReadToEnd()
        \$errPos = \$fs2.Position
        if (\$text2.Length -gt 0) {
          [Console]::Out.Write(\$text2)
          [Console]::Out.Flush()
        }
      }
      \$fs2.Close()
    }

    \$running = Get-Process -Name \$appName -ErrorAction SilentlyContinue
    if (\$running) {
      \$started = \$true
    } elseif (\$started) {
      break
    } else {
      \$waitCount++
      if (\$waitCount -gt 150) { break }
    }
    Start-Sleep -Milliseconds 100
  }
} finally {
  Remove-Item "\$dir\\running.lock" -Force -ErrorAction SilentlyContinue
}
''';
  }

  /// Generates `uninstall.ps1` invoked before `install` to clean old `flutter_assets`
  /// and record the active `${appName}` in `active_app.txt`.
  static String uninstallScript({
    required String remoteBaseDir,
    required String defaultAppName,
  }) {
    return '''
\$ErrorActionPreference = "SilentlyContinue"
\$dir = "$remoteBaseDir"
\$appName = if (\$args.Count -gt 0 -and \$args[0]) { \$args[0] } else { "$defaultAppName" }
\$appName | Set-Content -Path "\$dir\\active_app.txt" -Encoding Ascii
Remove-Item "\$dir\\running.lock" -Force -ErrorAction SilentlyContinue
Stop-Process -Name \$appName -Force -ErrorAction SilentlyContinue
foreach (\$target in @("\$dir\\runners\\\$appName\\data\\flutter_assets", "\$dir\\\$appName\\data\\flutter_assets")) {
  if (Test-Path \$target) {
    Remove-Item -Recurse -Force \$target -ErrorAction SilentlyContinue
  }
}
exit 0
''';
  }

  /// Generates `forward_port.ps1` invoked by Flutter custom-devices `forwardPort`.
  static String forwardPortScript() {
    return '''
[Console]::Out.WriteLine("Port forwarding success")
[Console]::Out.Flush()
while (\$true) {
  Start-Sleep -Seconds 60
}
''';
  }

  /// Generates `screenshot_session1.ps1` which runs in Session 1 (Interactive Desktop)
  /// with DPI awareness enabled and captures ONLY the target Flutter application's window
  /// using Win32 `PrintWindow(PW_RENDERFULLCONTENT)` and `DwmGetWindowAttribute`.
  /// Refuses to capture if the target Flutter app is not running or is minimized.
  static String screenshotSession1Script({
    required String remoteBaseDir,
  }) {
    return '''
\$ErrorActionPreference = "SilentlyContinue"
\$dir = "$remoteBaseDir"
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;

public class WinCapture {
  [StructLayout(LayoutKind.Sequential)]
  public struct RECT {
    public int Left;
    public int Top;
    public int Right;
    public int Bottom;
  }

  [DllImport("user32.dll")]
  public static extern bool SetProcessDPIAware();

  [DllImport("user32.dll")]
  public static extern bool IsIconic(IntPtr hWnd);

  [DllImport("user32.dll")]
  public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

  [DllImport("user32.dll")]
  public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdcBlt, uint nFlags);

  [DllImport("dwmapi.dll")]
  public static extern int DwmGetWindowAttribute(IntPtr hwnd, int dwAttribute, out RECT pvAttribute, int cbAttribute);
}
"@
[WinCapture]::SetProcessDPIAware() | Out-Null

\$appName = ""
if (Test-Path "\$dir\\screenshot_target.txt") {
  \$t = (Get-Content "\$dir\\screenshot_target.txt" -Raw).Trim()
  if (\$t.Length -gt 0) { \$appName = \$t }
}
if (\$appName.Length -eq 0 -and (Test-Path "\$dir\\active_app.txt")) {
  \$t = (Get-Content "\$dir\\active_app.txt" -Raw).Trim()
  if (\$t.Length -gt 0) { \$appName = \$t }
}

\$proc = \$null
if (Test-Path "\$dir\\active_app.pid") {
  \$pidStr = (Get-Content "\$dir\\active_app.pid" -Raw).Trim()
  if (\$pidStr -match "^\\d+\$") {
    \$candidate = Get-Process -Id ([int]\$pidStr) -ErrorAction SilentlyContinue
    if (\$candidate -and \$candidate.MainWindowHandle -ne [IntPtr]::Zero) {
      if (\$appName.Length -eq 0 -or \$candidate.ProcessName -eq \$appName) {
        \$proc = \$candidate
      }
    }
  }
}
if (\$null -eq \$proc -and \$appName.Length -gt 0) {
  \$proc = Get-Process -Name \$appName -ErrorAction SilentlyContinue |
    Where-Object { \$_.MainWindowHandle -ne [IntPtr]::Zero } |
    Select-Object -First 1
}

if (\$null -eq \$proc -or \$proc.MainWindowHandle -eq [IntPtr]::Zero) {
  "ERR_NO_APP: Target Flutter application (\$appName) is not running or has no active window. Desktop capture blocked for privacy." | Set-Content -Path "\$dir\\screenshot.status" -Encoding Ascii
  "done" | Set-Content -Path "\$dir\\screenshot.done" -Encoding Ascii
  exit 0
}

\$hWnd = \$proc.MainWindowHandle
if ([WinCapture]::IsIconic(\$hWnd)) {
  "ERR_MINIMIZED: Target Flutter application (\$appName) window is minimized. Desktop capture blocked for privacy." | Set-Content -Path "\$dir\\screenshot.status" -Encoding Ascii
  "done" | Set-Content -Path "\$dir\\screenshot.done" -Encoding Ascii
  exit 0
}

\$rect = New-Object WinCapture+RECT
[WinCapture]::GetWindowRect(\$hWnd, [ref]\$rect) | Out-Null
\$w = \$rect.Right - \$rect.Left
\$h = \$rect.Bottom - \$rect.Top
if (\$w -le 0 -or \$h -le 0) {
  "ERR_BOUNDS: Invalid window dimensions for \$appName." | Set-Content -Path "\$dir\\screenshot.status" -Encoding Ascii
  "done" | Set-Content -Path "\$dir\\screenshot.done" -Encoding Ascii
  exit 0
}

\$bmp = New-Object System.Drawing.Bitmap(\$w, \$h)
\$g = [System.Drawing.Graphics]::FromImage(\$bmp)
\$hdc = \$g.GetHdc()
# PW_RENDERFULLCONTENT = 2 renders DirectComposition/Flutter surface directly from DWM
[WinCapture]::PrintWindow(\$hWnd, \$hdc, 2) | Out-Null
\$g.ReleaseHdc(\$hdc)
\$g.Dispose()

# Crop invisible Windows 10/11 drop-shadow resize borders using DWMWA_EXTENDED_FRAME_BOUNDS (9)
\$dwmRect = New-Object WinCapture+RECT
\$hr = [WinCapture]::DwmGetWindowAttribute(\$hWnd, 9, [ref]\$dwmRect, [System.Runtime.InteropServices.Marshal]::SizeOf(\$dwmRect))
\$finalBmp = \$bmp
if (\$hr -eq 0) {
  \$cropX = [Math]::Max(0, \$dwmRect.Left - \$rect.Left)
  \$cropY = [Math]::Max(0, \$dwmRect.Top - \$rect.Top)
  \$cropW = [Math]::Min(\$w - \$cropX, \$dwmRect.Right - \$dwmRect.Left)
  \$cropH = [Math]::Min(\$h - \$cropY, \$dwmRect.Bottom - \$dwmRect.Top)
  if (\$cropW -gt 0 -and \$cropH -gt 0 -and (\$cropW -ne \$w -or \$cropH -ne \$h)) {
    \$cropRect = New-Object System.Drawing.Rectangle(\$cropX, \$cropY, \$cropW, \$cropH)
    \$finalBmp = \$bmp.Clone(\$cropRect, \$bmp.PixelFormat)
    \$bmp.Dispose()
  }
}

\$finalBmp.Save("\$dir\\screenshot.png", [System.Drawing.Imaging.ImageFormat]::Png)
\$finalBmp.Dispose()
"CAPTURED" | Set-Content -Path "\$dir\\screenshot.status" -Encoding Ascii
"done" | Set-Content -Path "\$dir\\screenshot.done" -Encoding Ascii
''';
  }

  /// Generates the local macOS/Linux `postBuild` smart hook script that checks
  /// whether native Windows C++ plugins, `windows/` runner sources, or Flutter
  /// engine revision changed. If changed (or never built for this `appName`),
  /// automatically syncs and builds the Windows runner on the remote device!
  static String macPostBuildHookScript({
    required String host,
    required String user,
    required String remoteBaseDir,
    required String remoteBaseDirScp,
  }) {
    return '''#!/bin/sh
set -e
APP_NAME="\$1"
ENGINE_REV="\$2"

if [ -z "\$APP_NAME" ]; then
  exit 0
fi

mkdir -p .dart_tool
HASH_FILE=".dart_tool/remote_win_\${APP_NAME}.hash"

# Compute fingerprint of windows/ directory, .flutter-plugins-dependencies, and engine revision
CURRENT_HASH=\$( (
  echo "engine:\$ENGINE_REV"
  if [ -f .flutter-plugins-dependencies ]; then
    cat .flutter-plugins-dependencies
  fi
  if [ -d windows ]; then
    find windows -type f \\( -name "*.cpp" -o -name "*.cc" -o -name "*.h" -o -name "CMakeLists.txt" -o -name "*.rc" \\) -exec shasum {} + 2>/dev/null | sort
  fi
) | shasum | awk '{print \$1}' )

OLD_HASH=""
if [ -f "\$HASH_FILE" ]; then
  OLD_HASH=\$(cat "\$HASH_FILE")
fi

# Check if the runner exe already exists on the remote Windows machine
REMOTE_EXISTS=\$(ssh -o BatchMode=yes $user@$host "powershell -NoProfile -Command \\"if ((Test-Path '$remoteBaseDir\\\\runners\\\\\$APP_NAME\\\\\$APP_NAME.exe') -or (Test-Path '$remoteBaseDir\\\\\$APP_NAME\\\\\$APP_NAME.exe')) { Write-Output 'YES' } else { Write-Output 'NO' }\\"" | tr -d '\\r\\n')

if [ "\$CURRENT_HASH" = "\$OLD_HASH" ] && [ "\$REMOTE_EXISTS" = "YES" ]; then
  exit 0
fi

echo "[flutter-remote-windows] Native Windows runner change detected for \$APP_NAME. Syncing and building on $host..."

ssh -o BatchMode=yes $user@$host "powershell -NoProfile -Command \\"New-Item -Force -ItemType Directory '$remoteBaseDir\\\\projects\\\\\$APP_NAME' | Out-Null; New-Item -Force -ItemType Directory '$remoteBaseDir\\\\runners\\\\\$APP_NAME' | Out-Null; New-Item -Force -ItemType Directory '$remoteBaseDir\\\\\$APP_NAME' | Out-Null\\""

ITEMS="pubspec.yaml lib windows"
[ -f l10n.yaml ] && ITEMS="\$ITEMS l10n.yaml"
[ -d assets ] && ITEMS="\$ITEMS assets"

scp -r -o BatchMode=yes \$ITEMS $user@$host:$remoteBaseDirScp/projects/\$APP_NAME/

TARGET="lib/main.dart"
if [ ! -f "lib/main.dart" ] && [ -f "lib/main_development.dart" ]; then
  TARGET="lib/main_development.dart"
fi

ssh -o BatchMode=yes $user@$host "powershell -NoProfile -Command \\"Set-Location '$remoteBaseDir\\\\projects\\\\\$APP_NAME'; \\\$fl = if (Test-Path '\\\$env:USERPROFILE\\\\fvm\\\\default\\\\bin\\\\flutter.bat') { '\\\$env:USERPROFILE\\\\fvm\\\\default\\\\bin\\\\flutter.bat' } else { 'flutter.bat' }; & \\\$fl build windows --debug -t \$TARGET; Copy-Item -Recurse -Force '$remoteBaseDir\\\\projects\\\\\$APP_NAME\\\\build\\\\windows\\\\x64\\\\runner\\\\Debug\\\\*' '$remoteBaseDir\\\\runners\\\\\$APP_NAME'; Copy-Item -Recurse -Force '$remoteBaseDir\\\\projects\\\\\$APP_NAME\\\\build\\\\windows\\\\x64\\\\runner\\\\Debug\\\\*' '$remoteBaseDir\\\\\$APP_NAME'\\""

echo "\$CURRENT_HASH" > "\$HASH_FILE"
echo "[flutter-remote-windows] Windows runner for \$APP_NAME updated successfully!"
''';
  }
}
