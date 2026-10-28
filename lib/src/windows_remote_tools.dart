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
            'Connects to the remote Windows device over SSH and checks OS version, hostname, free disk space, Git, FVM, Sidekick, Flutter SDK version, and Visual Studio 2022 C++ Build Tools status.',
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
        'name': 'sync_flutter_version',
        'description':
            'Checks the active Flutter SDK version on the Mac (or project .fvmrc) and compares it with the remote Windows device. If they differ, uses FVM on Windows to install and activate the exact same Flutter version so Dart VM kernel snapshots match 100%.',
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
              'description': 'Optional local project path to check .fvmrc and rebuild runner if version changed.',
            },
            'app_name': <String, Object?>{
              'type': 'string',
              'description': 'Optional app binary name to rebuild runner if version changed.',
            },
            'force': <String, Object?>{
              'type': 'boolean',
              'description': 'Force reinstall/activate on Windows even if versions appear identical (default: false).',
            },
          },
          'required': <String>['host', 'user'],
        },
      },
      <String, Object?>{
        'name': 'setup_flutter_custom_device',
        'description':
            'Configures Flutter custom-devices on the host (~/.config/flutter/custom_devices.json) including the smart postBuild hook (auto-rebuilds Windows C++ runner when plugins change), updates ~/.ssh/config, deploys Session 1 GUI & screenshot scripts to the Windows device, and updates .vscode/launch.json.',
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
              'description': 'Default Flutter application binary name (e.g. "gyrodeck_desktop").',
            },
            'enable_auto_post_build': <String, Object?>{
              'type': 'boolean',
              'description': 'Enable the smart postBuild hook that automatically rebuilds the Windows C++ runner when plugins or windows/ files change (default: true).',
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
            'Syncs the local Flutter project to an isolated project folder on the remote Windows device, verifies Flutter version parity, runs "flutter build windows --debug" remotely using Visual Studio Build Tools, and updates the Session 1 runner directory.',
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
              'description': 'Dart entrypoint file (default: auto-detected from lib/main.dart or lib/main_development.dart).',
            },
          },
          'required': <String>['host', 'user', 'project_path', 'app_name'],
        },
      },
      <String, Object?>{
        'name': 'take_remote_screenshot',
        'description':
            'Privacy-safe window-only screenshot tool: captures ONLY the target Flutter application window (using Win32 PrintWindow + DWMWA_EXTENDED_FRAME_BOUNDS) in Interactive Session 1 and downloads it to the local machine. Never captures the Windows desktop, taskbar, or other personal windows, and refuses to capture if the target Flutter app is not running.',
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
            'app_name': <String, Object?>{
              'type': 'string',
              'description': 'Optional Flutter binary name (e.g. "gyrodeck_desktop"). Defaults to the currently active remote Flutter app.',
            },
            'output_path': <String, Object?>{
              'type': 'string',
              'description': 'Local path on Mac to save the PNG screenshot (default: "/tmp/windows_remote_screenshot.png").',
            },
          },
          'required': <String>['host', 'user'],
        },
      },
      <String, Object?>{
        'name': 'set_dev_power_mode',
        'description':
            'Prevents the Windows handheld/PC from turning off its display or entering Modern Standby sleep during wireless development, or restores default power timeouts.',
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
            'mode': <String, Object?>{
              'type': 'string',
              'enum': <String>['keep_awake', 'restore_default'],
              'description': '"keep_awake" disables sleep/display timeouts on AC & battery; "restore_default" sets 15m/30m timeouts.',
            },
          },
          'required': <String>['host', 'user', 'mode'],
        },
      },
      <String, Object?>{
        'name': 'discover_and_update_ip',
        'description':
            'Automatically finds the Windows device IP address on the local Wi-Fi network (via mDNS hostname like "bty-ally.local" or ARP/SSH scan) and updates ~/.ssh/config, custom_devices.json, and postBuild scripts.',
        'inputSchema': <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'user': <String, Object?>{
              'type': 'string',
              'description': 'Windows SSH username (e.g. burak).',
            },
            'windows_hostname': <String, Object?>{
              'type': 'string',
              'description': 'Windows machine hostname (default: "bty-ally").',
            },
            'device_id': <String, Object?>{
              'type': 'string',
              'description': 'Device ID in custom_devices.json (default: "rog-ally").',
            },
          },
          'required': <String>['user'],
        },
      },
      <String, Object?>{
        'name': 'build_and_fetch_release',
        'description':
            'Syncs the local Flutter project to the Windows device, builds a production Windows Release bundle (flutter build windows --release), packages the Release folder into a .zip archive, and downloads it back to the local Mac project directory.',
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
              'description': 'Absolute path to the local Flutter project.',
            },
            'app_name': <String, Object?>{
              'type': 'string',
              'description': 'Binary name of the Flutter app.',
            },
            'target': <String, Object?>{
              'type': 'string',
              'description': 'Dart entrypoint file for release build (default: auto-detected from lib/main_production.dart or lib/main.dart).',
            },
          },
          'required': <String>['host', 'user', 'project_path', 'app_name'],
        },
      },
      <String, Object?>{
        'name': 'remote_app_control',
        'description':
            'Controls and diagnoses the remote Windows device: check running app status in Session 1, read stdout/stderr logs, stop running app, test launch in Session 1, or manually update the device IP address.',
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
      case 'sync_flutter_version':
        return _syncFlutterVersion(args);
      case 'setup_flutter_custom_device':
        return _setupFlutterCustomDevice(args);
      case 'sync_and_rebuild_windows_runner':
        return _syncAndRebuildWindowsRunner(args);
      case 'take_remote_screenshot':
        return _takeRemoteScreenshot(args);
      case 'set_dev_power_mode':
        return _setDevPowerMode(args);
      case 'discover_and_update_ip':
        return _discoverAndUpdateIp(args);
      case 'build_and_fetch_release':
        return _buildAndFetchRelease(args);
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
$hostname = hostname
$freeGb = [math]::Round((Get-PSDrive C).Free / 1GB, 2)
$git = (where.exe git 2>$null) -join ", "
$fvm = (Get-ChildItem -Path "$env:LOCALAPPDATA\fvm" -Filter fvm.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
$sidekick = (Get-ChildItem -Path "$env:LOCALAPPDATA\Sidekick" -Filter sidekick.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
$vswhere = "C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe"
$vs = if (Test-Path $vswhere) { (& $vswhere -products * -Property catalog_productDisplayVersion) -join ", " } else { "Not Installed" }
$flutterBin = "$env:USERPROFILE\fvm\default\bin\flutter.bat"
$flutterVer = if (Test-Path $flutterBin) { (& $flutterBin --version | Select-Object -First 1) } else { "Not Installed" }

Write-Output "Hostname: $hostname"
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

  Future<String> _syncFlutterVersion(Map<String, Object?> args) async {
    final host = args['host'] as String;
    final user = args['user'] as String;
    final projectPath = args['project_path'] as String?;
    final appName = args['app_name'] as String?;
    final force = (args['force'] as bool?) ?? false;

    final localInfo = await _getLocalFlutterVersionInfo(projectPath: projectPath);
    final localVersion = localInfo['frameworkVersion'] ?? 'stable';
    final localEngine = localInfo['engineRevision'] ?? '';

    const remoteVerPs = r'''
$flutterBin = "$env:USERPROFILE\fvm\default\bin\flutter.bat"
if (Test-Path $flutterBin) {
  & $flutterBin --version --machine
} else {
  Write-Output "{}"
}
''';
    final remoteRes = await _runSshPowerShell(host, user, remoteVerPs);
    var remoteVersion = '';
    var remoteEngine = '';
    try {
      final decoded = jsonDecode(remoteRes.stdout.toString().trim());
      if (decoded is Map<String, Object?>) {
        remoteVersion = (decoded['frameworkVersion'] as String?) ?? '';
        remoteEngine = (decoded['engineRevision'] as String?) ?? '';
      }
    } on Object {
      // Ignore parse errors
    }

    if (!force &&
        localVersion.isNotEmpty &&
        localVersion == remoteVersion &&
        (localEngine.isEmpty || localEngine == remoteEngine)) {
      return 'Flutter versions are already in sync! Both Mac and Windows ($host) are on Flutter $localVersion (engine: $localEngine).';
    }

    final syncPs = '''
\$fvm = (Get-ChildItem -Path "\$env:LOCALAPPDATA\\fvm" -Filter fvm.exe -Recurse | Select-Object -First 1).FullName
& \$fvm install $localVersion --setup
& \$fvm global $localVersion --force
''';
    final syncRes = await _runSshPowerShell(host, user, syncPs);
    final buf = StringBuffer()
      ..writeln(
        'Synced Windows ($host) Flutter version from "${remoteVersion.isEmpty ? 'none' : remoteVersion}" to "$localVersion":',
      )
      ..writeln(syncRes.stdout.toString().trim());

    if (projectPath != null &&
        projectPath.isNotEmpty &&
        appName != null &&
        appName.isNotEmpty) {
      final rebuildOut = await _syncAndRebuildWindowsRunner(<String, Object?>{
        'host': host,
        'user': user,
        'project_path': projectPath,
        'app_name': appName,
      });
      buf.writeln('\nRebuilt runner with new Flutter engine:\n$rebuildOut');
    }

    return buf.toString();
  }

  Future<String> _setupFlutterCustomDevice(Map<String, Object?> args) async {
    final deviceId = args['device_id'] as String;
    final deviceLabel =
        (args['device_label'] as String?) ?? '$deviceId (Wireless Windows)';
    final host = args['host'] as String;
    final user = args['user'] as String;
    final appName = args['app_name'] as String;
    final enableAutoPostBuild = (args['enable_auto_post_build'] as bool?) ?? true;
    final projectPath = args['project_path'] as String?;
    final target = (args['target'] as String?) ?? 'lib/main.dart';

    final remoteBaseDir = 'C:\\Users\\$user\\flutter_remote';
    final remoteBaseDirScp = 'C:/Users/$user/flutter_remote';
    const scheduledTaskName = 'FlutterRemoteRun';
    const screenshotTaskName = 'FlutterRemoteScreenshot';

    // 1. Update ~/.ssh/config
    _upsertSshConfig(deviceId: deviceId, host: host, user: user);

    // 2. Enable custom-devices in Flutter
    await Process.run('flutter', <String>['config', '--enable-custom-devices']);

    // 3. Create local postBuild smart hook script
    final home = Platform.environment['HOME'] ?? '';
    final postBuildScriptPath = '$home/.config/flutter/post_build_$deviceId.sh';
    final postBuildFile = File(postBuildScriptPath);
    if (!postBuildFile.parent.existsSync()) {
      postBuildFile.parent.createSync(recursive: true);
    }
    postBuildFile.writeAsStringSync(
      PowerShellTemplates.macPostBuildHookScript(
        host: host,
        user: user,
        remoteBaseDir: remoteBaseDir,
        remoteBaseDirScp: remoteBaseDirScp,
      ),
    );
    await Process.run('chmod', <String>['+x', postBuildScriptPath]);

    // 4. Create remote directories and upload Session 1 scripts
    final tempDir = Directory.systemTemp.createTempSync('flutter_remote_mcp_');
    try {
      final s1File = File('${tempDir.path}/session1_runner.ps1')
        ..writeAsStringSync(
          PowerShellTemplates.session1RunnerScript(
            remoteBaseDir: remoteBaseDir,
            defaultAppName: appName,
          ),
        );
      final rdFile = File('${tempDir.path}/run_debug.ps1')
        ..writeAsStringSync(
          PowerShellTemplates.runDebugScript(
            remoteBaseDir: remoteBaseDir,
            defaultAppName: appName,
            scheduledTaskName: scheduledTaskName,
          ),
        );
      final unFile = File('${tempDir.path}/uninstall.ps1')
        ..writeAsStringSync(
          PowerShellTemplates.uninstallScript(
            remoteBaseDir: remoteBaseDir,
            defaultAppName: appName,
          ),
        );
      final fpFile = File('${tempDir.path}/forward_port.ps1')
        ..writeAsStringSync(PowerShellTemplates.forwardPortScript());
      final ssFile = File('${tempDir.path}/screenshot_session1.ps1')
        ..writeAsStringSync(
          PowerShellTemplates.screenshotSession1Script(
            remoteBaseDir: remoteBaseDir,
          ),
        );

      await _runSshPowerShell(
        host,
        user,
        'New-Item -Force -ItemType Directory "$remoteBaseDir\\$appName\\data" | Out-Null; '
        'New-Item -Force -ItemType Directory "$remoteBaseDir\\runners\\$appName\\data" | Out-Null; '
        'New-Item -Force -ItemType Directory "$remoteBaseDir\\projects" | Out-Null',
      );

      await Process.run('scp', <String>[
        '-o',
        'BatchMode=yes',
        s1File.path,
        rdFile.path,
        unFile.path,
        fpFile.path,
        ssFile.path,
        '$user@$host:$remoteBaseDirScp/',
      ]);

      await Process.run('ssh', <String>[
        '-o',
        'BatchMode=yes',
        '$user@$host',
        'schtasks /Create /TN $scheduledTaskName /TR "powershell.exe -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File $remoteBaseDir\\session1_runner.ps1" /SC ONCE /ST 00:00 /IT /F && '
        'schtasks /Create /TN $screenshotTaskName /TR "powershell.exe -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File $remoteBaseDir\\screenshot_session1.ps1" /SC ONCE /ST 00:00 /IT /F',
      ]);
    } finally {
      tempDir.deleteSync(recursive: true);
    }

    // 5. Upsert ~/.config/flutter/custom_devices.json
    _upsertCustomDevicesJson(
      deviceId: deviceId,
      deviceLabel: deviceLabel,
      host: host,
      user: user,
      appName: appName,
      remoteBaseDir: remoteBaseDir,
      remoteBaseDirScp: remoteBaseDirScp,
      postBuildScriptPath: enableAutoPostBuild ? postBuildScriptPath : null,
    );

    // 6. Optionally update .vscode/launch.json
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
- Session 1 interactive scheduled tasks ($scheduledTaskName & $screenshotTaskName) deployed to $remoteBaseDir
- Smart postBuild hook: ${enableAutoPostBuild ? postBuildScriptPath : 'disabled'}
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
    final explicitTarget = args['target'] as String?;
    final target = explicitTarget ?? _detectDefaultTarget(projectPath);

    final remoteBaseDir = 'C:\\Users\\$user\\flutter_remote';
    final remoteProjectDir = '$remoteBaseDir\\projects\\$appName';
    final remoteProjectScp = 'C:/Users/$user/flutter_remote/projects/$appName';

    // Ensure Flutter version parity first
    await _syncFlutterVersion(<String, Object?>{
      'host': host,
      'user': user,
      'project_path': projectPath,
    });

    await _runSshPowerShell(
      host,
      user,
      'Remove-Item "$remoteBaseDir\\running.lock" -Force -ErrorAction SilentlyContinue; '
      'Stop-Process -Name "$appName" -Force -ErrorAction SilentlyContinue; '
      'New-Item -Force -ItemType Directory "$remoteProjectDir" | Out-Null; '
      'New-Item -Force -ItemType Directory "$remoteBaseDir\\runners\\$appName" | Out-Null; '
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
Set-Location "$remoteProjectDir"
\$flutter = if (Test-Path "\$env:USERPROFILE\\fvm\\default\\bin\\flutter.bat") { "\$env:USERPROFILE\\fvm\\default\\bin\\flutter.bat" } else { "flutter.bat" }
& \$flutter build windows --debug -t $target
if (\$LASTEXITCODE -ne 0) { exit \$LASTEXITCODE }
Copy-Item -Recurse -Force "$remoteProjectDir\\build\\windows\\x64\\runner\\Debug\\*" "$remoteBaseDir\\runners\\$appName"
Copy-Item -Recurse -Force "$remoteProjectDir\\build\\windows\\x64\\runner\\Debug\\*" "$remoteBaseDir\\$appName"
Write-Output "Runner updated in $remoteBaseDir\\runners\\$appName"
''';

    final buildRes = await _runSshPowerShell(host, user, buildPs);
    if (buildRes.exitCode != 0) {
      return 'Remote Windows build failed (exit ${buildRes.exitCode}):\n${buildRes.stdout}\n${buildRes.stderr}';
    }

    return 'Successfully synced and rebuilt Windows debug runner ($appName.exe):\n${buildRes.stdout}';
  }

  Future<String> _takeRemoteScreenshot(Map<String, Object?> args) async {
    final host = args['host'] as String;
    final user = args['user'] as String;
    final appName = (args['app_name'] as String?)?.trim() ?? '';
    final outputPath =
        (args['output_path'] as String?) ?? '/tmp/windows_remote_screenshot.png';
    final remoteBaseDir = 'C:\\Users\\$user\\flutter_remote';
    final remoteBaseDirScp = 'C:/Users/$user/flutter_remote';

    final setTargetCmd = appName.isNotEmpty
        ? '"$appName" | Set-Content -Path "$remoteBaseDir\\screenshot_target.txt" -Encoding Ascii'
        : 'Remove-Item "$remoteBaseDir\\screenshot_target.txt" -Force -ErrorAction SilentlyContinue';

    final capturePs = '''
$setTargetCmd
Remove-Item "$remoteBaseDir\\screenshot.png","$remoteBaseDir\\screenshot.done","$remoteBaseDir\\screenshot.status" -Force -ErrorAction SilentlyContinue
schtasks /Run /TN FlutterRemoteScreenshot | Out-Null
\$count = 0
while (!(Test-Path "$remoteBaseDir\\screenshot.done") -and (\$count -lt 50)) {
  Start-Sleep -Milliseconds 100
  \$count++
}
if (Test-Path "$remoteBaseDir\\screenshot.status") {
  Get-Content "$remoteBaseDir\\screenshot.status" -Raw
} elseif (Test-Path "$remoteBaseDir\\screenshot.png") {
  Write-Output "CAPTURED"
} else {
  Write-Output "FAILED"
}
''';

    final res = await _runSshPowerShell(host, user, capturePs);
    final statusOut = res.stdout.toString().trim();
    if (!statusOut.contains('CAPTURED')) {
      return 'Screenshot blocked or failed on $host: $statusOut';
    }

    final scpRes = await Process.run('scp', <String>[
      '-o',
      'BatchMode=yes',
      '$user@$host:$remoteBaseDirScp/screenshot.png',
      outputPath,
    ]);
    if (scpRes.exitCode != 0) {
      return 'Failed to download screenshot via SCP:\n${scpRes.stderr}';
    }

    return 'Window-only screenshot captured from $host (Session 1) and saved to: $outputPath';
  }

  Future<String> _setDevPowerMode(Map<String, Object?> args) async {
    final host = args['host'] as String;
    final user = args['user'] as String;
    final mode = args['mode'] as String;

    final ps = mode == 'keep_awake'
        ? '''
powercfg /change monitor-timeout-ac 0
powercfg /change monitor-timeout-dc 0
powercfg /change standby-timeout-ac 0
powercfg /change standby-timeout-dc 0
Write-Output "Power mode set to KEEP_AWAKE (monitor and standby timeouts disabled on AC & battery)."
'''
        : '''
powercfg /change monitor-timeout-ac 15
powercfg /change monitor-timeout-dc 5
powercfg /change standby-timeout-ac 30
powercfg /change standby-timeout-dc 15
Write-Output "Power mode restored to default timeouts."
''';

    final res = await _runSshPowerShell(host, user, ps);
    return res.stdout.toString().trim();
  }

  Future<String> _discoverAndUpdateIp(Map<String, Object?> args) async {
    final user = args['user'] as String;
    final windowsHostname =
        ((args['windows_hostname'] as String?) ?? 'bty-ally').toLowerCase();
    final deviceId = (args['device_id'] as String?) ?? 'rog-ally';

    String? discoveredIp;

    // 1. Try mDNS (.local) or direct hostname resolution via ping
    for (final candidate in <String>[
      '$windowsHostname.local',
      windowsHostname,
    ]) {
      final pingRes = await Process.run('ping', <String>[
        '-c',
        '1',
        '-t',
        '2',
        candidate,
      ]);
      if (pingRes.exitCode == 0) {
        final match = RegExp(r'\((\d+\.\d+\.\d+\.\d+)\)').firstMatch(
          pingRes.stdout.toString(),
        );
        if (match != null) {
          discoveredIp = match.group(1);
          break;
        }
      }
    }

    // 2. Fallback: check ARP table entries on local network
    if (discoveredIp == null) {
      final arpRes = await Process.run('arp', <String>['-a']);
      final matches = RegExp(r'\((\d+\.\d+\.\d+\.\d+)\)').allMatches(
        arpRes.stdout.toString(),
      );
      for (final m in matches) {
        final ip = m.group(1);
        if (ip == null || ip.endsWith('.255') || ip.endsWith('.1')) continue;
        final sshCheck = await Process.run('ssh', <String>[
          '-o',
          'BatchMode=yes',
          '-o',
          'ConnectTimeout=1',
          '$user@$ip',
          'hostname',
        ]);
        if (sshCheck.exitCode == 0 &&
            sshCheck.stdout.toString().trim().toLowerCase() ==
                windowsHostname) {
          discoveredIp = ip;
          break;
        }
      }
    }

    if (discoveredIp == null) {
      return 'Could not automatically discover IP for hostname "$windowsHostname" on the local network.';
    }

    _upsertSshConfig(deviceId: deviceId, host: discoveredIp, user: user);
    _replaceDeviceIpInConfigs(
      deviceId: deviceId,
      user: user,
      newIp: discoveredIp,
    );

    return 'Discovered "$windowsHostname" at IP $discoveredIp and updated ~/.ssh/config, custom_devices.json, and postBuild hook!';
  }

  Future<String> _buildAndFetchRelease(Map<String, Object?> args) async {
    final host = args['host'] as String;
    final user = args['user'] as String;
    final projectPath = args['project_path'] as String;
    final appName = args['app_name'] as String;
    final explicitTarget = args['target'] as String?;
    final target = explicitTarget ?? _detectReleaseTarget(projectPath);

    final remoteBaseDir = 'C:\\Users\\$user\\flutter_remote';
    final remoteProjectDir = '$remoteBaseDir\\projects\\$appName';
    final remoteProjectScp = 'C:/Users/$user/flutter_remote/projects/$appName';
    final remoteZipPath = '$remoteBaseDir\\$appName-windows-release.zip';
    final remoteZipScp = 'C:/Users/$user/flutter_remote/$appName-windows-release.zip';

    await _runSshPowerShell(
      host,
      user,
      'New-Item -Force -ItemType Directory "$remoteProjectDir" | Out-Null',
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

    await Process.run('scp', <String>[
      '-r',
      '-o',
      'BatchMode=yes',
      ...itemsToCopy,
      '$user@$host:$remoteProjectScp/',
    ]);

    final releasePs = '''
Set-Location "$remoteProjectDir"
\$flutter = if (Test-Path "\$env:USERPROFILE\\fvm\\default\\bin\\flutter.bat") { "\$env:USERPROFILE\\fvm\\default\\bin\\flutter.bat" } else { "flutter.bat" }
& \$flutter build windows --release -t $target
if (\$LASTEXITCODE -ne 0) { exit \$LASTEXITCODE }
Remove-Item "$remoteZipPath" -Force -ErrorAction SilentlyContinue
Compress-Archive -Path "$remoteProjectDir\\build\\windows\\x64\\runner\\Release\\*" -DestinationPath "$remoteZipPath" -Force
Write-Output "RELEASE_ZIP_READY"
''';

    final res = await _runSshPowerShell(host, user, releasePs);
    if (!res.stdout.toString().contains('RELEASE_ZIP_READY')) {
      return 'Release build failed on $host:\n${res.stdout}\n${res.stderr}';
    }

    final localBuildDir = Directory('$projectPath/build');
    if (!localBuildDir.existsSync()) {
      localBuildDir.createSync(recursive: true);
    }
    final localZipPath = '${localBuildDir.path}/$appName-windows-release.zip';

    final scpRes = await Process.run('scp', <String>[
      '-o',
      'BatchMode=yes',
      '$user@$host:$remoteZipScp',
      localZipPath,
    ]);
    if (scpRes.exitCode != 0) {
      return 'Failed to download Release zip via SCP:\n${scpRes.stderr}';
    }

    return 'Windows Release built on $host and downloaded to: $localZipPath';
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
          '"$appName" | Set-Content -Path "$remoteBaseDir\\active_app.txt" -Encoding Ascii; '
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
        _replaceDeviceIpInConfigs(
          deviceId: deviceId,
          user: user,
          newIp: newIp,
        );
        return 'Updated IP address for "$deviceId" to $newIp in ~/.ssh/config, custom_devices.json, and postBuild hook.';

      default:
        throw ArgumentError('Unsupported action: $action');
    }
  }

  Future<Map<String, String>> _getLocalFlutterVersionInfo({
    String? projectPath,
  }) async {
    // Check .fvmrc if projectPath is provided
    if (projectPath != null && projectPath.isNotEmpty) {
      final fvmrc = File('$projectPath/.fvmrc');
      if (fvmrc.existsSync()) {
        try {
          final decoded = jsonDecode(fvmrc.readAsStringSync());
          if (decoded is Map<String, Object?> && decoded['flutter'] is String) {
            final ver = decoded['flutter'] as String;
            if (ver != 'stable' && ver != 'beta' && ver != 'master') {
              return <String, String>{'frameworkVersion': ver};
            }
          }
        } on Object {
          // Fallback to flutter --version --machine
        }
      }
    }

    final res = await Process.run('flutter', <String>['--version', '--machine']);
    if (res.exitCode == 0) {
      try {
        final decoded = jsonDecode(res.stdout.toString().trim());
        if (decoded is Map<String, Object?>) {
          return <String, String>{
            'frameworkVersion': (decoded['frameworkVersion'] as String?) ?? 'stable',
            'engineRevision': (decoded['engineRevision'] as String?) ?? '',
          };
        }
      } on Object {
        // Fallback
      }
    }
    return <String, String>{'frameworkVersion': 'stable'};
  }

  String _detectDefaultTarget(String projectPath) {
    if (File('$projectPath/lib/main.dart').existsSync()) {
      return 'lib/main.dart';
    }
    if (File('$projectPath/lib/main_development.dart').existsSync()) {
      return 'lib/main_development.dart';
    }
    return 'lib/main.dart';
  }

  String _detectReleaseTarget(String projectPath) {
    if (File('$projectPath/lib/main_production.dart').existsSync()) {
      return 'lib/main_production.dart';
    }
    return _detectDefaultTarget(projectPath);
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
    String? postBuildScriptPath,
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

    final postBuildCmd = postBuildScriptPath != null
        ? <String>[
            'sh',
            postBuildScriptPath,
            r'${appName}',
            r'${engineRevision}',
          ]
        : null;

    devices.add(<String, Object?>{
      'id': deviceId,
      'label': deviceLabel,
      'sdkNameAndVersion': 'Windows 11 x64 ($host)',
      'platform': 'linux-x64',
      'enabled': true,
      'ping': pingCmd,
      'pingSuccessRegex': null,
      'postBuild': postBuildCmd,
      'install': <String>[
        'scp',
        '-r',
        '-o',
        'BatchMode=yes',
        r'${localPath}',
        r'$user@$host:$remoteBaseDirScp/runners/${appName}/data/flutter_assets'
            .replaceFirst(r'$user', user)
            .replaceFirst(r'$host', host)
            .replaceFirst(r'$remoteBaseDirScp', remoteBaseDirScp),
      ],
      'uninstall': <String>[
        'ssh',
        '-o',
        'BatchMode=yes',
        '$user@$host',
        r'powershell -NoProfile -ExecutionPolicy Bypass -File ' +
            '$remoteBaseDir\\uninstall.ps1 ' +
            r'${appName}',
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

  void _replaceDeviceIpInConfigs({
    required String deviceId,
    required String user,
    required String newIp,
  }) {
    final home = Platform.environment['HOME'] ?? '';
    final ipRegex = RegExp(r'\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b');

    final customDevicesFile = File('$home/.config/flutter/custom_devices.json');
    if (customDevicesFile.existsSync()) {
      final updated = customDevicesFile
          .readAsStringSync()
          .replaceAllMapped(ipRegex, (Match m) {
        final ip = m.group(0)!;
        return ip == '127.0.0.1' ? ip : newIp;
      });
      customDevicesFile.writeAsStringSync(updated);
    }

    final postBuildFile = File('$home/.config/flutter/post_build_$deviceId.sh');
    if (postBuildFile.existsSync()) {
      final updated = postBuildFile.readAsStringSync().replaceAllMapped(
        RegExp(RegExp.escape(user) + r'@\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}'),
        (_) => '$user@$newIp',
      );
      postBuildFile.writeAsStringSync(updated);
    }
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
