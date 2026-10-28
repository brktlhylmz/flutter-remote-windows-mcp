import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'powershell_templates.dart';

/// Implements the MCP tools for managing wireless Flutter Windows devices.
class WindowsRemoteTools {
  HttpServer? _pairingServer;
  Timer? _pairingTimeout;

  /// Returns the MCP tool definitions for `tools/list`.
  List<Map<String, Object?>> getToolDefinitions() {
    return <Map<String, Object?>>[
      <String, Object?>{
        'name': 'generate_ssh_pairing',
        'description':
            'Starts a temporary HTTP pairing server on the host and returns a short 1-line PowerShell command (irm http://<HOST_IP>:8765 | iex) to run on the Windows device (e.g. ASUS ROG Ally) to enable OpenSSH Server and authorize the host SSH key without typing passwords.',
        'inputSchema': <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'port': <String, Object?>{
              'type': 'integer',
              'description': 'Local HTTP port for serving the pairing script (default: 8765).',
            },
            'timeout_seconds': <String, Object?>{
              'type': 'integer',
              'description': 'How long to keep the pairing server alive in seconds (default: 300).',
            },
          },
        },
      },
      <String, Object?>{
        'name': 'check_remote_windows',
        'description':
            'Connects to the remote Windows device over SSH and checks OS version, free disk space, Git, FVM, Sidekick, Flutter SDK, and Visual Studio 2022 C++ Build Tools status.',
        'inputSchema': <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'host': <String, Object?>{
              'type': 'string',
              'description': 'IP address or hostname of the Windows device (e.g. 192.168.1.192).',
            },
            'user': <String, Object?>{
              'type': 'string',
              'description': 'Windows SSH username (e.g. burak).',
            },
          },
          'required': <String>['host', 'user'],
        },
      },
      <String, Object?>{
        'name': 'install_windows_toolchain',
        'description':
            'Remotely installs FVM, Sidekick (from GitHub Releases with Desktop shortcut), Flutter SDK via FVM, and/or Microsoft Visual Studio 2022 C++ Build Tools on the Windows device over SSH.',
        'inputSchema': <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'host': <String, Object?>{
              'type': 'string',
              'description': 'IP address or hostname of the Windows device.',
            },
            'user': <String, Object?>{
              'type': 'string',
              'description': 'Windows SSH username.',
            },
            'install_fvm': <String, Object?>{
              'type': 'boolean',
              'description': 'Install FVM CLI from GitHub Releases (default: true).',
            },
            'install_sidekick': <String, Object?>{
              'type': 'boolean',
              'description': 'Install Sidekick GUI from GitHub Releases and create Desktop shortcut (default: true).',
            },
            'flutter_channel': <String, Object?>{
              'type': 'string',
              'description': 'Flutter channel or version to install via FVM (default: "stable", pass "" to skip).',
            },
            'install_vs_buildtools': <String, Object?>{
              'type': 'boolean',
              'description': 'Install Microsoft Visual Studio 2022 Build Tools with VCTools workload via winget (default: false).',
            },
          },
          'required': <String>['host', 'user'],
        },
      },
      <String, Object?>{
        'name': 'setup_flutter_custom_device',
        'description':
            'Configures Flutter custom-devices on the host (~/.config/flutter/custom_devices.json), updates ~/.ssh/config, deploys Session 1 GUI launcher scripts (session1_runner.ps1, run_debug.ps1, FLUTTER_ENGINE_SWITCHES, running.lock) to the Windows device, and optionally adds a launch configuration to .vscode/launch.json.',
        'inputSchema': <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'device_id': <String, Object?>{
              'type': 'string',
              'description': 'Short device ID for flutter run -d <device_id> (e.g. "rog-ally").',
            },
            'device_label': <String, Object?>{
              'type': 'string',
              'description': 'Display name in flutter devices (e.g. "ASUS ROG Ally (Wireless)").',
            },
            'host': <String, Object?>{
              'type': 'string',
              'description': 'IP address of the Windows device (e.g. 192.168.1.192).',
            },
            'user': <String, Object?>{
              'type': 'string',
              'description': 'Windows SSH username (e.g. burak).',
            },
            'app_name': <String, Object?>{
              'type': 'string',
              'description': 'Flutter application binary name from pubspec.yaml (e.g. "gyrodeck_desktop").',
            },
            'project_path': <String, Object?>{
              'type': 'string',
              'description': 'Optional absolute path to the local Flutter project to update .vscode/launch.json.',
            },
            'target': <String, Object?>{
              'type': 'string',
              'description': 'Optional Dart entrypoint for .vscode/launch.json (default: "lib/main.dart").',
            },
          },
          'required': <String>['device_id', 'host', 'user', 'app_name'],
        },
      },
      <String, Object?>{
        'name': 'sync_and_rebuild_windows_runner',
        'description':
            'Syncs the local Flutter project (pubspec.yaml, lib/, windows/, l10n.yaml) to the remote Windows device, runs "flutter build windows --debug" remotely using Visual Studio Build Tools, and updates the Session 1 runner directory. Call this once per project or whenever you add/change native Windows C++ plugins.',
        'inputSchema': <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'host': <String, Object?>{
              'type': 'string',
              'description': 'IP address of the Windows device.',
            },
            'user': <String, Object?>{
              'type': 'string',
              'description': 'Windows SSH username.',
            },
            'project_path': <String, Object?>{
              'type': 'string',
              'description': 'Absolute path to the Flutter project on the local machine.',
            },
            'app_name': <String, Object?>{
              'type': 'string',
              'description': 'Binary name of the Flutter app (e.g. "gyrodeck_desktop").',
            },
            'target': <String, Object?>{
              'type': 'string',
              'description': 'Dart entrypoint file (default: "lib/main.dart", e.g. "lib/main_development.dart").',
            },
          },
          'required': <String>['host', 'user', 'project_path', 'app_name'],
        },
      },
      <String, Object?>{
        'name': 'remote_app_control',
        'description':
            'Controls and diagnoses the remote Windows device: check running app status in Session 1, read stdout/stderr logs, stop running app, test launch in Session 1, or update the device IP address across ~/.ssh/config and custom_devices.json.',
        'inputSchema': <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'action': <String, Object?>{
              'type': 'string',
              'enum': <String>['status', 'logs', 'stop', 'launch_test', 'update_ip'],
              'description': 'Action to perform.',
            },
            'host': <String, Object?>{
              'type': 'string',
              'description': 'Current IP address of the Windows device.',
            },
            'user': <String, Object?>{
              'type': 'string',
              'description': 'Windows SSH username.',
            },
            'app_name': <String, Object?>{
              'type': 'string',
              'description': 'Flutter app binary name (default: "gyrodeck_desktop").',
            },
            'device_id': <String, Object?>{
              'type': 'string',
              'description': 'Device ID in custom_devices.json (used with update_ip, default: "rog-ally").',
            },
            'new_ip': <String, Object?>{
              'type': 'string',
              'description': 'New IP address when action is "update_ip".',
            },
          },
          'required': <String>['action', 'host', 'user'],
        },
      },
    ];
  }

  /// Dispatches a `tools/call` invocation by name.
  Future<String> callTool(String name, Map<String, Object?> args) async {
    switch (name) {
      case 'generate_ssh_pairing':
        return _generateSshPairing(args);
      case 'check_remote_windows':
        return _checkRemoteWindows(args);
      case 'install_windows_toolchain':
        return _installWindowsToolchain(args);
      case 'setup_flutter_custom_device':
        return _setupFlutterCustomDevice(args);
      case 'sync_and_rebuild_windows_runner':
        return _syncAndRebuildWindowsRunner(args);
      case 'remote_app_control':
        return _remoteAppControl(args);
      default:
        throw ArgumentError('Unknown tool: $name');
    }
  }

  Future<String> _generateSshPairing(Map<String, Object?> args) async {
    final port = (args['port'] as int?) ?? 8765;
    final timeoutSeconds = (args['timeout_seconds'] as int?) ?? 300;
    final home = Platform.environment['HOME'] ?? '';
    final sshDir = Directory('$home/.ssh');
    if (!sshDir.existsSync()) {
      sshDir.createSync(recursive: true);
    }

    final pubKeyFile = File('$home/.ssh/id_ed25519.pub');
    if (!pubKeyFile.existsSync()) {
      await Process.run('ssh-keygen', <String>[
        '-t',
        'ed25519',
        '-N',
        '',
        '-f',
        '$home/.ssh/id_ed25519',
      ]);
    }
    final pubKey = pubKeyFile.readAsStringSync().trim();
    final script = PowerShellTemplates.sshPairingScript(pubKey);

    await _pairingServer?.close(force: true);
    _pairingTimeout?.cancel();

    _pairingServer = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _pairingServer!.listen((HttpRequest req) async {
      req.response.headers.contentType = ContentType.text;
      req.response.write(script);
      await req.response.close();
    });
    _pairingTimeout = Timer(Duration(seconds: timeoutSeconds), () {
      _pairingServer?.close(force: true);
      _pairingServer = null;
    });

    final localIp = await _getLocalIpAddress();
    return '''
SSH Pairing Server started on port $port (active for ${timeoutSeconds}s).

Run this 1-line command in Administrator PowerShell on the Windows device:
```powershell
irm http://$localIp:$port | iex
```

Or if OpenSSH is not started yet, run the full script directly in Administrator PowerShell:
```powershell
$script
```
''';
  }

  Future<String> _checkRemoteWindows(Map<String, Object?> args) async {
    final host = args['host'] as String;
    final user = args['user'] as String;

    const psCheck = r'''
$os = (Get-CimInstance Win32_OperatingSystem).Caption
$freeGb = [math]::Round((Get-PSDrive C).Free / 1GB, 2)
$git = (where.exe git 2>$null) -join ", "
$fvm = (Get-ChildItem -Path "$env:LOCALAPPDATA\fvm" -Filter fvm.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
$sidekick = (Get-ChildItem -Path "$env:LOCALAPPDATA\Sidekick" -Filter sidekick.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
$vswhere = "C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe"
$vs = if (Test-Path $vswhere) { (& $vswhere -products * -Property catalog_productDisplayVersion) -join ", " } else { "Not Installed" }
$flutterBin = "$env:USERPROFILE\fvm\default\bin\flutter.bat"
$flutterVer = if (Test-Path $flutterBin) { (& $flutterBin --version | Select-Object -First 1) } else { "Not Installed" }

Write-Output "OS: $os"
Write-Output "Free Disk (C:): $freeGb GB"
Write-Output "Git: $(if ($git) { $git } else { 'Not Installed' })"
Write-Output "FVM: $(if ($fvm) { $fvm } else { 'Not Installed' })"
Write-Output "Sidekick: $(if ($sidekick) { $sidekick } else { 'Not Installed' })"
Write-Output "Flutter: $flutterVer"
Write-Output "Visual Studio Build Tools: $vs"
''';

    final res = await _runSshPowerShell(host, user, psCheck);
    if (res.exitCode != 0) {
      return 'Failed to connect via SSH to $user@$host (exit ${res.exitCode}):\n${res.stderr}\n${res.stdout}';
    }
    return 'Remote Windows Status ($user@$host):\n${res.stdout}';
  }

  Future<String> _installWindowsToolchain(Map<String, Object?> args) async {
    final host = args['host'] as String;
    final user = args['user'] as String;
    final installFvm = (args['install_fvm'] as bool?) ?? true;
    final installSidekick = (args['install_sidekick'] as bool?) ?? true;
    final flutterChannel = (args['flutter_channel'] as String?) ?? 'stable';
    final installVs = (args['install_vs_buildtools'] as bool?) ?? false;

    final logs = StringBuffer();

    if (installFvm) {
      const fvmScript = r'''
$rel = Invoke-RestMethod 'https://api.github.com/repos/leoafarias/fvm/releases/latest'
$asset = $rel.assets | Where-Object { $_.name -match 'windows-x64\.zip$' } | Select-Object -First 1
New-Item -Force -ItemType Directory "$env:LOCALAPPDATA\fvm" | Out-Null
curl.exe -sL $asset.browser_download_url -o "$env:USERPROFILE\Downloads\fvm.zip"
Expand-Archive -Force -Path "$env:USERPROFILE\Downloads\fvm.zip" -DestinationPath "$env:LOCALAPPDATA\fvm"
$fvmExe = Get-ChildItem -Path "$env:LOCALAPPDATA\fvm" -Filter fvm.exe -Recurse | Select-Object -First 1
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($userPath -notlike '*AppData\Local\fvm*') {
  [Environment]::SetEnvironmentVariable('Path', $userPath + ';' + $fvmExe.DirectoryName + ";$env:USERPROFILE\fvm\default\bin", 'User')
}
Write-Output ("FVM installed: " + (& $fvmExe.FullName --version))
''';
      final res = await _runSshPowerShell(host, user, fvmScript);
      logs.writeln(res.stdout.toString().trim());
    }

    if (installSidekick) {
      const sidekickScript = r'''
$rel = Invoke-RestMethod 'https://api.github.com/repos/fluttertools/sidekick/releases/latest'
$asset = $rel.assets | Where-Object { $_.name -match '^windows-.*\.zip$' } | Select-Object -First 1
curl.exe -sL $asset.browser_download_url -o "$env:USERPROFILE\Downloads\sidekick.zip"
Expand-Archive -Force -Path "$env:USERPROFILE\Downloads\sidekick.zip" -DestinationPath "$env:LOCALAPPDATA\Sidekick"
$exe = Get-ChildItem -Path "$env:LOCALAPPDATA\Sidekick" -Filter sidekick.exe -Recurse | Select-Object -First 1
$desk = [Environment]::GetFolderPath('Desktop')
$ws = New-Object -ComObject WScript.Shell
$sc = $ws.CreateShortcut($desk + '\Sidekick.lnk')
$sc.TargetPath = $exe.FullName
$sc.WorkingDirectory = $exe.DirectoryName
$sc.Save()
Write-Output ("Sidekick installed with Desktop shortcut: " + $exe.FullName)
''';
      final res = await _runSshPowerShell(host, user, sidekickScript);
      logs.writeln(res.stdout.toString().trim());
    }

    if (flutterChannel.isNotEmpty) {
      final flutterScript = '''
\$fvm = (Get-ChildItem -Path "\$env:LOCALAPPDATA\\fvm" -Filter fvm.exe -Recurse | Select-Object -First 1).FullName
& \$fvm install $flutterChannel --setup
& \$fvm global $flutterChannel --force
''';
      final res = await _runSshPowerShell(host, user, flutterScript);
      logs.writeln(res.stdout.toString().trim());
    }

    if (installVs) {
      const vsCmd =
          'winget install --id=Microsoft.VisualStudio.2022.BuildTools -e --source winget --accept-source-agreements --accept-package-agreements --override "--quiet --wait --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"';
      final res = await Process.run('ssh', <String>[
        '-o',
        'BatchMode=yes',
        '$user@$host',
        vsCmd,
      ]);
      logs.writeln(res.stdout.toString().trim());
    }

    return logs.toString();
  }

  Future<String> _setupFlutterCustomDevice(Map<String, Object?> args) async {
    final deviceId = args['device_id'] as String;
    final deviceLabel =
        (args['device_label'] as String?) ?? '$deviceId (Wireless Windows)';
    final host = args['host'] as String;
    final user = args['user'] as String;
    final appName = args['app_name'] as String;
    final projectPath = args['project_path'] as String?;
    final target = (args['target'] as String?) ?? 'lib/main.dart';

    final remoteBaseDir = 'C:\\Users\\$user\\flutter_remote';
    final remoteBaseDirScp = 'C:/Users/$user/flutter_remote';
    const scheduledTaskName = 'FlutterRemoteRun';

    // 1. Update ~/.ssh/config
    _upsertSshConfig(deviceId: deviceId, host: host, user: user);

    // 2. Enable custom-devices in Flutter
    await Process.run('flutter', <String>['config', '--enable-custom-devices']);

    // 3. Create remote directories and upload Session 1 scripts
    final tempDir = Directory.systemTemp.createTempSync('flutter_remote_mcp_');
    try {
      final s1File = File('${tempDir.path}/session1_runner.ps1')
        ..writeAsStringSync(
          PowerShellTemplates.session1RunnerScript(
            remoteBaseDir: remoteBaseDir,
            appName: appName,
          ),
        );
      final rdFile = File('${tempDir.path}/run_debug.ps1')
        ..writeAsStringSync(
          PowerShellTemplates.runDebugScript(
            remoteBaseDir: remoteBaseDir,
            appName: appName,
            scheduledTaskName: scheduledTaskName,
          ),
        );
      final unFile = File('${tempDir.path}/uninstall.ps1')
        ..writeAsStringSync(
          PowerShellTemplates.uninstallScript(
            remoteBaseDir: remoteBaseDir,
            appName: appName,
          ),
        );
      final fpFile = File('${tempDir.path}/forward_port.ps1')
        ..writeAsStringSync(PowerShellTemplates.forwardPortScript());

      await _runSshPowerShell(
        host,
        user,
        'New-Item -Force -ItemType Directory "$remoteBaseDir\\$appName\\data" | Out-Null',
      );

      await Process.run('scp', <String>[
        '-o',
        'BatchMode=yes',
        s1File.path,
        rdFile.path,
        unFile.path,
        fpFile.path,
        '$user@$host:$remoteBaseDirScp/',
      ]);

      await Process.run('ssh', <String>[
        '-o',
        'BatchMode=yes',
        '$user@$host',
        'schtasks /Create /TN $scheduledTaskName /TR "powershell.exe -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File $remoteBaseDir\\session1_runner.ps1" /SC ONCE /ST 00:00 /IT /F',
      ]);
    } finally {
      tempDir.deleteSync(recursive: true);
    }

    // 4. Upsert ~/.config/flutter/custom_devices.json
    _upsertCustomDevicesJson(
      deviceId: deviceId,
      deviceLabel: deviceLabel,
      host: host,
      user: user,
      appName: appName,
      remoteBaseDir: remoteBaseDir,
      remoteBaseDirScp: remoteBaseDirScp,
    );

    // 5. Optionally update .vscode/launch.json
    if (projectPath != null && projectPath.isNotEmpty) {
      _upsertLaunchJson(
        projectPath: projectPath,
        deviceId: deviceId,
        deviceLabel: deviceLabel,
        target: target,
      );
    }

    return '''
Successfully configured Flutter Custom Device "$deviceId" ($deviceLabel) at $user@$host!
- Session 1 interactive scheduled task ($scheduledTaskName) deployed to $remoteBaseDir
- Updated ~/.config/flutter/custom_devices.json
- Updated ~/.ssh/config
${projectPath != null ? '- Updated $projectPath/.vscode/launch.json' : ''}
''';
  }

  Future<String> _syncAndRebuildWindowsRunner(Map<String, Object?> args) async {
    final host = args['host'] as String;
    final user = args['user'] as String;
    final projectPath = args['project_path'] as String;
    final appName = args['app_name'] as String;
    final target = (args['target'] as String?) ?? 'lib/main.dart';

    final remoteBaseDir = 'C:\\Users\\$user\\flutter_remote';
    final remoteProjectScp = 'C:/Users/$user/flutter_remote/project';

    await _runSshPowerShell(
      host,
      user,
      'Remove-Item "$remoteBaseDir\\running.lock" -Force -ErrorAction SilentlyContinue; '
      'Stop-Process -Name "$appName" -Force -ErrorAction SilentlyContinue; '
      'New-Item -Force -ItemType Directory "$remoteBaseDir\\project" | Out-Null; '
      'New-Item -Force -ItemType Directory "$remoteBaseDir\\$appName" | Out-Null',
    );

    final itemsToCopy = <String>[];
    for (final item in <String>[
      'pubspec.yaml',
      'l10n.yaml',
      'lib',
      'windows',
      'assets',
    ]) {
      final path = '$projectPath/$item';
      if (FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound) {
        itemsToCopy.add(path);
      }
    }

    final scpRes = await Process.run('scp', <String>[
      '-r',
      '-o',
      'BatchMode=yes',
      ...itemsToCopy,
      '$user@$host:$remoteProjectScp/',
    ]);
    if (scpRes.exitCode != 0) {
      return 'Failed to copy project files via SCP:\n${scpRes.stderr}';
    }

    final buildPs = '''
Set-Location "$remoteBaseDir\\project"
\$flutter = if (Test-Path "\$env:USERPROFILE\\fvm\\default\\bin\\flutter.bat") { "\$env:USERPROFILE\\fvm\\default\\bin\\flutter.bat" } else { "flutter.bat" }
& \$flutter build windows --debug -t $target
if (\$LASTEXITCODE -ne 0) { exit \$LASTEXITCODE }
Copy-Item -Recurse -Force "$remoteBaseDir\\project\\build\\windows\\x64\\runner\\Debug\\*" "$remoteBaseDir\\$appName"
Write-Output "Runner updated in $remoteBaseDir\\$appName"
''';

    final buildRes = await _runSshPowerShell(host, user, buildPs);
    if (buildRes.exitCode != 0) {
      return 'Remote Windows build failed (exit ${buildRes.exitCode}):\n${buildRes.stdout}\n${buildRes.stderr}';
    }

    return 'Successfully synced and rebuilt Windows debug runner ($appName.exe):\n${buildRes.stdout}';
  }

  Future<String> _remoteAppControl(Map<String, Object?> args) async {
    final action = args['action'] as String;
    final host = args['host'] as String;
    final user = args['user'] as String;
    final appName = (args['app_name'] as String?) ?? 'gyrodeck_desktop';
    final deviceId = (args['device_id'] as String?) ?? 'rog-ally';
    final remoteBaseDir = 'C:\\Users\\$user\\flutter_remote';

    switch (action) {
      case 'status':
        final res = await _runSshPowerShell(
          host,
          user,
          'Get-Process -Name "$appName" -ErrorAction SilentlyContinue | Select-Object Id, ProcessName, SessionId; '
          'Get-ScheduledTaskInfo -TaskName FlutterRemoteRun',
        );
        return res.stdout.toString().trim().isEmpty
            ? '$appName is not currently running on $host.'
            : res.stdout.toString();

      case 'logs':
        final res = await _runSshPowerShell(
          host,
          user,
          'Write-Output "=== STDOUT ==="; Get-Content "$remoteBaseDir\\app_out.log" -ErrorAction SilentlyContinue; '
          'Write-Output "=== STDERR ==="; Get-Content "$remoteBaseDir\\app_err.log" -ErrorAction SilentlyContinue',
        );
        return res.stdout.toString();

      case 'stop':
        await _runSshPowerShell(
          host,
          user,
          'Remove-Item "$remoteBaseDir\\running.lock" -Force -ErrorAction SilentlyContinue; '
          'Stop-Process -Name "$appName" -Force -ErrorAction SilentlyContinue',
        );
        return 'Stopped $appName on $host.';

      case 'launch_test':
        final res = await _runSshPowerShell(
          host,
          user,
          'Remove-Item "$remoteBaseDir\\running.lock" -Force -ErrorAction SilentlyContinue; '
          'Stop-Process -Name "$appName" -Force -ErrorAction SilentlyContinue; '
          'Start-Sleep -Milliseconds 300; '
          'Remove-Item "$remoteBaseDir\\app_out.log","$remoteBaseDir\\app_err.log" -Force -ErrorAction SilentlyContinue; '
          '"running" | Set-Content -Path "$remoteBaseDir\\running.lock" -Encoding Ascii; '
          'schtasks /Run /TN FlutterRemoteRun | Out-Null; '
          'Start-Sleep -Seconds 3; '
          'Get-Process -Name "$appName" -ErrorAction SilentlyContinue | Select-Object Id, ProcessName, SessionId; '
          'Get-Content "$remoteBaseDir\\app_out.log" -ErrorAction SilentlyContinue; '
          'Get-Content "$remoteBaseDir\\app_err.log" -ErrorAction SilentlyContinue',
        );
        return res.stdout.toString();

      case 'update_ip':
        final newIp = args['new_ip'] as String?;
        if (newIp == null || newIp.isEmpty) {
          throw ArgumentError('new_ip is required when action is "update_ip".');
        }
        _upsertSshConfig(deviceId: deviceId, host: newIp, user: user);
        _updateIpInCustomDevicesJson(deviceId: deviceId, oldIp: host, newIp: newIp);
        return 'Updated IP address for "$deviceId" from $host to $newIp in ~/.ssh/config and ~/.config/flutter/custom_devices.json.';

      default:
        throw ArgumentError('Unsupported action: $action');
    }
  }

  Future<ProcessResult> _runSshPowerShell(
    String host,
    String user,
    String script,
  ) {
    final encoded = base64Encode(
       _encodeUtf16Le(script),
    );
    return Process.run('ssh', <String>[
      '-o',
      'BatchMode=yes',
      '$user@$host',
      'powershell -NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded',
    ]);
  }

  List<int> _encodeUtf16Le(String text) {
    final units = text.codeUnits;
    final bytes = <int>[];
    for (final unit in units) {
      bytes.add(unit & 0xFF);
      bytes.add((unit >> 8) & 0xFF);
    }
    return bytes;
  }

  Future<String> _getLocalIpAddress() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        if (addr.address.startsWith('192.168.') ||
            addr.address.startsWith('10.') ||
            addr.address.startsWith('172.')) {
          return addr.address;
        }
      }
    }
    return '127.0.0.1';
  }

  void _upsertSshConfig({
    required String deviceId,
    required String host,
    required String user,
  }) {
    final home = Platform.environment['HOME'] ?? '';
    final configFile = File('$home/.ssh/config');
    if (!configFile.parent.existsSync()) {
      configFile.parent.createSync(recursive: true);
    }
    final existing = configFile.existsSync() ? configFile.readAsStringSync() : '';
    final block = '''
Host $deviceId
    HostName $host
    User $user
    Port 22
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking accept-new
''';
    final regex = RegExp(
      r'Host\s+' + RegExp.escape(deviceId) + r'\n(?:\s+.*\n)*',
    );
    final updated = regex.hasMatch(existing)
        ? existing.replaceFirst(regex, block)
        : '$existing\n$block';
    configFile.writeAsStringSync(updated);
  }

  void _upsertCustomDevicesJson({
    required String deviceId,
    required String deviceLabel,
    required String host,
    required String user,
    required String appName,
    required String remoteBaseDir,
    required String remoteBaseDirScp,
  }) {
    final home = Platform.environment['HOME'] ?? '';
    final file = File('$home/.config/flutter/custom_devices.json');
    if (!file.parent.existsSync()) {
      file.parent.createSync(recursive: true);
    }

    var root = <String, Object?>{'custom-devices': <Object?>[]};
    if (file.existsSync()) {
      try {
        final decoded = jsonDecode(file.readAsStringSync());
        if (decoded is Map<String, Object?>) {
          root = Map<String, Object?>.from(decoded);
        }
      } on Object {
        // Re-initialize if malformed
      }
    }

    final devices = (root['custom-devices'] as List<Object?>?)?.toList() ?? <Object?>[];
    devices.removeWhere(
      (Object? d) => d is Map && d['id'] == deviceId,
    );

    final pingCmd = Platform.isMacOS
        ? <String>['ping', '-c', '1', '-t', '1', host]
        : <String>['ping', '-c', '1', '-W', '1', host];

    devices.add(<String, Object?>{
      'id': deviceId,
      'label': deviceLabel,
      'sdkNameAndVersion': 'Windows 11 x64 ($host)',
      'platform': 'linux-x64',
      'enabled': true,
      'ping': pingCmd,
      'pingSuccessRegex': null,
      'postBuild': null,
      'install': <String>[
        'scp',
        '-r',
        '-o',
        'BatchMode=yes',
        r'${localPath}',
        '$user@$host:$remoteBaseDirScp/$appName/data/flutter_assets',
      ],
      'uninstall': <String>[
        'ssh',
        '-o',
        'BatchMode=yes',
        '$user@$host',
        'powershell -NoProfile -ExecutionPolicy Bypass -File $remoteBaseDir\\uninstall.ps1',
      ],
      'runDebug': <String>[
        'ssh',
        '-o',
        'BatchMode=yes',
        '$user@$host',
        r'powershell -NoProfile -ExecutionPolicy Bypass -File ' +
            '$remoteBaseDir\\run_debug.ps1 ' +
            r'${engineOptions}',
      ],
      'forwardPort': <String>[
        'ssh',
        '-o',
        'BatchMode=yes',
        '-o',
        'ExitOnForwardFailure=yes',
        '-L',
        r'127.0.0.1:${hostPort}:127.0.0.1:${devicePort}',
        '$user@$host',
        'powershell -NoProfile -ExecutionPolicy Bypass -File $remoteBaseDir\\forward_port.ps1',
      ],
      'forwardPortSuccessRegex': 'Port forwarding success',
      'screenshot': null,
      'readLogs': null,
    });

    root['custom-devices'] = devices;
    const encoder = JsonEncoder.withIndent('  ');
    file.writeAsStringSync('${encoder.convert(root)}\n');
  }

  void _updateIpInCustomDevicesJson({
    required String deviceId,
    required String oldIp,
    required String newIp,
  }) {
    final home = Platform.environment['HOME'] ?? '';
    final file = File('$home/.config/flutter/custom_devices.json');
    if (!file.existsSync()) return;
    final content = file.readAsStringSync().replaceAll(oldIp, newIp);
    file.writeAsStringSync(content);
  }

  void _upsertLaunchJson({
    required String projectPath,
    required String deviceId,
    required String deviceLabel,
    required String target,
  }) {
    final file = File('$projectPath/.vscode/launch.json');
    if (!file.parent.existsSync()) {
      file.parent.createSync(recursive: true);
    }
    if (!file.existsSync()) {
      const encoder = JsonEncoder.withIndent('  ');
      file.writeAsStringSync(
        '${encoder.convert(<String, Object?>{
          'version': '0.2.0',
          'configurations': <Object?>[
            <String, Object?>{
              'name': 'Launch $deviceLabel',
              'request': 'launch',
              'type': 'dart',
              'deviceId': deviceId,
              'program': target,
            },
          ],
        })}\n',
      );
    }
  }
}
