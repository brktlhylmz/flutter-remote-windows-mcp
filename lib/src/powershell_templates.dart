/// PowerShell script templates for Windows OpenSSH pairing and Session 1 GUI execution.
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
Write-Host "BASARILI! SSH eslestirmesi tamamlandi!" -ForegroundColor Green
Write-Host ("Kullanici: " + (whoami)) -ForegroundColor Cyan
''';
  }

  /// Generates `session1_runner.ps1` which runs in Windows Interactive Session 1
  /// via Task Scheduler (`/IT`), sets `FLUTTER_ENGINE_SWITCHES`, and keeps the
  /// Task Scheduler Job Object alive until `running.lock` is removed or the app exits.
  static String session1RunnerScript({
    required String remoteBaseDir,
    required String appName,
  }) {
    return '''
\$ErrorActionPreference = "SilentlyContinue"
\$dir = "$remoteBaseDir"
\$appDir = "\$dir\\$appName"
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

\$proc = Start-Process -FilePath "\$appDir\\$appName.exe" `
  -WorkingDirectory \$appDir `
  -RedirectStandardOutput \$outLog `
  -RedirectStandardError \$errLog `
  -WindowStyle Normal `
  -PassThru

while ((Test-Path "\$dir\\running.lock") -and (!\$proc.HasExited)) {
  Start-Sleep -Milliseconds 500
}

if (!\$proc.HasExited) {
  Stop-Process -Id \$proc.Id -Force -ErrorAction SilentlyContinue
}
''';
  }

  /// Generates `run_debug.ps1` invoked over SSH by Flutter custom-devices `runDebug`.
  /// Triggers the Session 1 scheduled task and streams `app_out.log` / `app_err.log`
  /// back to the host's `flutter run` process.
  static String runDebugScript({
    required String remoteBaseDir,
    required String appName,
    required String scheduledTaskName,
  }) {
    return '''
\$ErrorActionPreference = "SilentlyContinue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
\$dir = "$remoteBaseDir"
\$outLog = "\$dir\\app_out.log"
\$errLog = "\$dir\\app_err.log"

Remove-Item "\$dir\\running.lock" -Force -ErrorAction SilentlyContinue
Stop-Process -Name "$appName" -Force -ErrorAction SilentlyContinue
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

    \$running = Get-Process -Name "$appName" -ErrorAction SilentlyContinue
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

  /// Generates `uninstall.ps1` invoked before `install` to clean old `flutter_assets`.
  static String uninstallScript({
    required String remoteBaseDir,
    required String appName,
  }) {
    return '''
\$ErrorActionPreference = "SilentlyContinue"
Remove-Item "$remoteBaseDir\\running.lock" -Force -ErrorAction SilentlyContinue
Stop-Process -Name "$appName" -Force -ErrorAction SilentlyContinue
if (Test-Path "$remoteBaseDir\\$appName\\data\\flutter_assets") {
  Remove-Item -Recurse -Force "$remoteBaseDir\\$appName\\data\\flutter_assets" -ErrorAction SilentlyContinue
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
}
