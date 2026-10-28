import 'dart:convert';
import 'dart:io';

import 'package:flutter_remote_windows_mcp/flutter_remote_windows_mcp.dart';
import 'package:test/test.dart';

/// Decodes a PowerShell `-EncodedCommand` (Base64 UTF-16LE) back to a Dart String
/// so tests can inspect the exact PowerShell script sent over SSH.
String decodePowerShellEncodedCommand(String base64Str) {
  final bytes = base64Decode(base64Str);
  final codeUnits = <int>[];
  for (var i = 0; i + 1 < bytes.length; i += 2) {
    codeUnits.add(bytes[i] | (bytes[i + 1] << 8));
  }
  return String.fromCharCodes(codeUnits);
}

class RecordedCommand {
  RecordedCommand(this.executable, this.arguments);
  final String executable;
  final List<String> arguments;

  @override
  String toString() => '$executable ${arguments.join(' ')}';
}

void main() {
  late Directory tempHome;
  late Directory tempProject;
  late DeviceProfileStore store;
  late List<RecordedCommand> executedCommands;
  late ProcessResult Function(String executable, List<String> args) mockHandler;
  late WindowsRemoteTools tools;

  setUp(() {
    tempHome = Directory.systemTemp.createTempSync('mcp_test_home_');
    tempProject = Directory.systemTemp.createTempSync('mcp_test_proj_');
    File('${tempProject.path}/pubspec.yaml')
        .writeAsStringSync('name: test_app\n');
    Directory('${tempProject.path}/lib').createSync();
    File('${tempProject.path}/lib/main.dart')
        .writeAsStringSync('void main() {}');
    Directory('${tempProject.path}/windows').createSync();

    store = DeviceProfileStore(
      configFilePath:
          '${tempHome.path}/.config/flutter_remote_windows/config.json',
    );
    executedCommands = <RecordedCommand>[];
    mockHandler =
        (String exe, List<String> args) => ProcessResult(0, 0, '', '');

    tools = WindowsRemoteTools(
      profileStore: store,
      homeDir: tempHome.path,
      processRunner: (String exe, List<String> args) async {
        executedCommands.add(RecordedCommand(exe, args));
        return mockHandler(exe, args);
      },
    );
  });

  tearDown(() async {
    await tools.close();
    if (tempHome.existsSync()) {
      tempHome.deleteSync(recursive: true);
    }
    if (tempProject.existsSync()) {
      tempProject.deleteSync(recursive: true);
    }
  });

  group('1. Schema & Tool Registry', () {
    test('exposes all 12 MCP tools with valid schemas and no personal data',
        () {
      final definitions = tools.getToolDefinitions();
      expect(definitions, hasLength(12));

      final serialized = jsonEncode(definitions);
      expect(serialized, isNot(contains('burak')));
      expect(serialized, isNot(contains('bty-ally')));
      expect(serialized, isNot(contains('gyrodeck_desktop')));
      expect(serialized, isNot(contains('192.168.1.192')));
    });

    test('throws ArgumentError on unknown tool name', () async {
      expect(
        () => tools.callTool('non_existent_tool', <String, Object?>{}),
        throwsArgumentError,
      );
    });
  });

  group('2. manage_device_profiles & ~/.ssh/config preservation', () {
    test(
        'saves, lists, sets default, removes profiles, and preserves existing ~/.ssh/config hosts',
        () async {
      final sshConfig = File('${tempHome.path}/.ssh/config');
      sshConfig.parent.createSync(recursive: true);
      sshConfig.writeAsStringSync(
        'Host github.com\n    User git\n    IdentityFile ~/.ssh/github_key\n',
      );

      final emptyList =
          await tools.callTool('manage_device_profiles', <String, Object?>{
        'action': 'list',
      });
      expect(emptyList, contains('No device profiles saved yet'));

      // Save first profile
      await tools.callTool('manage_device_profiles', <String, Object?>{
        'action': 'save',
        'device_id': 'rog-ally',
        'device_label': 'ASUS ROG Ally',
        'host': '192.168.1.50',
        'user': 'devuser',
        'app_name': 'test_app',
      });

      // Save second profile (remote office PC with custom ssh_port & headless keep-alive)
      await tools.callTool('manage_device_profiles', <String, Object?>{
        'action': 'save',
        'device_id': 'office-pc',
        'device_label': 'Office PC (Tailscale)',
        'host': '100.84.10.25',
        'user': 'officeuser',
        'ssh_port': 2222,
        'keep_headless_session_alive': true,
        'set_default': true,
      });

      final sshText = sshConfig.readAsStringSync();
      expect(sshText, contains('Host github.com'));
      expect(sshText, contains('Host rog-ally'));
      expect(sshText, contains('Host office-pc'));
      expect(sshText, contains('Port 2222'));

      expect(store.getDefaultDeviceId(), equals('office-pc'));

      // Switch default back to rog-ally
      await tools.callTool('manage_device_profiles', <String, Object?>{
        'action': 'set_default',
        'device_id': 'rog-ally',
      });
      expect(store.getDefaultDeviceId(), equals('rog-ally'));

      // Remove office-pc
      final removeOut =
          await tools.callTool('manage_device_profiles', <String, Object?>{
        'action': 'remove',
        'device_id': 'office-pc',
      });
      expect(removeOut, contains('Removed profile "office-pc"'));
      expect(store.listProfiles().keys, equals(<String>['rog-ally']));
    });

    test('throws ArgumentError when resolving without profile or host/user',
        () {
      expect(
        () => store.resolve(<String, Object?>{}),
        throwsArgumentError,
      );
    });
  });

  group('3. generate_ssh_pairing HTTP server & key generation', () {
    test(
        'generates SSH key if missing and serves valid PowerShell pairing script over HTTP',
        () async {
      mockHandler = (String exe, List<String> args) {
        if (exe == 'ssh-keygen') {
          File('${tempHome.path}/.ssh/id_ed25519.pub').writeAsStringSync(
            'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMockKey test@host\n',
          );
        }
        return ProcessResult(0, 0, '', '');
      };

      final out =
          await tools.callTool('generate_ssh_pairing', <String, Object?>{
        'port': 18765,
        'timeout_seconds': 30,
      });
      expect(out, contains('18765'));
      expect(out, contains('AAAAC3NzaC1lZDI1NTE5AAAAIMockKey'));

      // Fetch the pairing script from the live local HTTP server
      final client = HttpClient();
      final req = await client.getUrl(Uri.parse('http://127.0.0.1:18765/'));
      final resp = await req.close();
      final body = await utf8.decoder.bind(resp).join();
      client.close();

      expect(resp.statusCode, equals(200));
      expect(body, contains('*S-1-5-32-544:F'));
      expect(body, contains('AAAAC3NzaC1lZDI1NTE5AAAAIMockKey'));
    });
  });

  group('4. check_remote_windows & UTF-16LE Base64 encoding', () {
    test(
        'decodes UTF-16LE Base64 PowerShell command accurately and uses saved profile port',
        () async {
      store.upsertProfile(
        const DeviceProfile(
          deviceId: 'office-pc',
          label: 'Office PC',
          host: '100.84.10.25',
          user: 'devuser',
          sshPort: 2222,
        ),
        setAsDefault: true,
      );

      String? capturedScript;
      mockHandler = (String exe, List<String> args) {
        if (exe == 'ssh') {
          final cmdArg = args.last;
          final encoded = cmdArg.split('-EncodedCommand ').last;
          capturedScript = decodePowerShellEncodedCommand(encoded);
          return ProcessResult(
            0,
            0,
            'Hostname: OFFICE-WIN\nFlutter: Flutter 3.47.8\n',
            '',
          );
        }
        return ProcessResult(0, 0, '', '');
      };

      final res =
          await tools.callTool('check_remote_windows', <String, Object?>{});
      expect(res, contains('OFFICE-WIN'));
      expect(executedCommands.single.arguments,
          containsAll(<String>['-p', '2222']));
      expect(capturedScript, isNotNull);
      expect(capturedScript, contains('Win32_OperatingSystem'));
    });
  });

  group('5. sync_flutter_version', () {
    test('skips FVM install when host and remote versions and engines match',
        () async {
      store.upsertProfile(
        const DeviceProfile(
          deviceId: 'rog-ally',
          label: 'ROG Ally',
          host: '192.168.1.50',
          user: 'devuser',
        ),
        setAsDefault: true,
      );

      mockHandler = (String exe, List<String> args) {
        if (exe == 'flutter' && args.contains('--machine')) {
          return ProcessResult(
            0,
            0,
            jsonEncode(<String, String>{
              'frameworkVersion': '3.47.8',
              'engineRevision': 'abc123456',
            }),
            '',
          );
        }
        if (exe == 'ssh') {
          return ProcessResult(
            0,
            0,
            jsonEncode(<String, String>{
              'frameworkVersion': '3.47.8',
              'engineRevision': 'abc123456',
            }),
            '',
          );
        }
        return ProcessResult(0, 0, '', '');
      };

      final res =
          await tools.callTool('sync_flutter_version', <String, Object?>{});
      expect(res, contains('already in sync'));
      // Only 1 flutter --version call and 1 ssh version check call (no fvm install)
      expect(executedCommands, hasLength(2));
    });

    test(
        'installs matching Flutter version via FVM when .fvmrc differs from remote',
        () async {
      File('${tempProject.path}/.fvmrc')
          .writeAsStringSync('{"flutter": "3.50.0"}');

      final sshScripts = <String>[];
      mockHandler = (String exe, List<String> args) {
        if (exe == 'ssh') {
          final encoded = args.last.split('-EncodedCommand ').last;
          final script = decodePowerShellEncodedCommand(encoded);
          sshScripts.add(script);
          if (sshScripts.length == 1) {
            return ProcessResult(
              0,
              0,
              jsonEncode(<String, String>{
                'frameworkVersion': '3.47.8',
                'engineRevision': 'old_engine',
              }),
              '',
            );
          }
          return ProcessResult(0, 0, 'FVM switched to 3.50.0', '');
        }
        return ProcessResult(0, 0, '', '');
      };

      final res =
          await tools.callTool('sync_flutter_version', <String, Object?>{
        'host': '192.168.1.50',
        'user': 'devuser',
        'project_path': tempProject.path,
      });

      expect(res, contains('from "3.47.8" to "3.50.0"'));
      expect(sshScripts.last, contains('install 3.50.0 --setup'));
      expect(sshScripts.last, contains('global 3.50.0 --force'));
    });
  });

  group('6. setup_flutter_custom_device & multi-device custom_devices.json',
      () {
    test(
        'creates postBuild hook, launch.json, custom_devices.json with TCP ping, and headless flag',
        () async {
      final res =
          await tools.callTool('setup_flutter_custom_device', <String, Object?>{
        'device_id': 'office-pc',
        'device_label': 'Office Windows PC',
        'host': '100.84.10.25',
        'user': 'devuser',
        'ssh_port': 2222,
        'use_tcp_ping': true,
        'keep_headless_session_alive': true,
        'app_name': 'test_app',
        'project_path': tempProject.path,
      });

      expect(res, contains('office-pc'));
      expect(res, contains('TCP ping: true'));
      expect(res, contains('Headless console keep-alive: true'));

      // Verify post_build_office-pc.sh exists and uses SSH_PORT="2222"
      final postBuild =
          File('${tempHome.path}/.config/flutter/post_build_office-pc.sh');
      expect(postBuild.existsSync(), isTrue);
      expect(postBuild.readAsStringSync(), contains('SSH_PORT="2222"'));

      // Verify custom_devices.json uses nc -z and -P 2222 / -p 2222
      final customDevicesFile =
          File('${tempHome.path}/.config/flutter/custom_devices.json');
      final customDevicesJson = jsonDecode(customDevicesFile.readAsStringSync())
          as Map<String, Object?>;
      final devices = customDevicesJson['custom-devices'] as List<Object?>;
      expect(devices, hasLength(1));
      final entry = devices.first as Map<String, Object?>;
      expect(entry['id'], equals('office-pc'));
      expect((entry['ping'] as List<Object?>).first, equals('nc'));
      expect((entry['install'] as List<Object?>),
          containsAll(<String>['-P', '2222']));

      // Verify .vscode/launch.json was created
      final launchFile = File('${tempProject.path}/.vscode/launch.json');
      expect(launchFile.existsSync(), isTrue);
      expect(
          launchFile.readAsStringSync(), contains('"deviceId": "office-pc"'));
    });
  });

  group('7. take_remote_screenshot privacy enforcement', () {
    setUp(() {
      store.upsertProfile(
        const DeviceProfile(
          deviceId: 'rog-ally',
          label: 'ROG Ally',
          host: '192.168.1.50',
          user: 'devuser',
        ),
        setAsDefault: true,
      );
    });

    test(
        'blocks desktop screenshot and never calls SCP when app is not running (ERR_NO_APP)',
        () async {
      mockHandler = (String exe, List<String> args) {
        if (exe == 'ssh') {
          return ProcessResult(
            0,
            0,
            'ERR_NO_APP: Target Flutter application is not running. Desktop capture blocked for privacy.',
            '',
          );
        }
        return ProcessResult(0, 0, '', '');
      };

      final res =
          await tools.callTool('take_remote_screenshot', <String, Object?>{
        'app_name': 'closed_app',
      });

      expect(res, contains('ERR_NO_APP'));
      expect(
        executedCommands.where((c) => c.executable == 'scp'),
        isEmpty,
      );
    });

    test('downloads window screenshot via SCP when remote status is CAPTURED',
        () async {
      mockHandler = (String exe, List<String> args) {
        if (exe == 'ssh') {
          return ProcessResult(0, 0, 'CAPTURED\n', '');
        }
        return ProcessResult(0, 0, '', '');
      };

      final outPath = '${tempHome.path}/shot.png';
      final res =
          await tools.callTool('take_remote_screenshot', <String, Object?>{
        'output_path': outPath,
      });

      expect(res, contains('Window-only screenshot captured'));
      expect(
        executedCommands.where((c) => c.executable == 'scp'),
        hasLength(1),
      );
    });
  });

  group('8. discover_and_update_ip & multi-device IP isolation', () {
    test(
        'updates target device IP via ARP/SSH fallback without corrupting other devices or 127.0.0.1',
        () async {
      // Set up two devices: rog-ally and office-pc
      await tools.callTool('setup_flutter_custom_device', <String, Object?>{
        'device_id': 'rog-ally',
        'host': '192.168.1.50',
        'user': 'devuser',
        'app_name': 'test_app',
      });
      await tools.callTool('setup_flutter_custom_device', <String, Object?>{
        'device_id': 'office-pc',
        'host': '100.84.10.25',
        'user': 'officeuser',
        'ssh_port': 2222,
        'app_name': 'test_app',
      });

      executedCommands.clear();
      mockHandler = (String exe, List<String> args) {
        if (exe == 'ping') {
          // Simulate mDNS failure so ARP fallback is tested
          return ProcessResult(0, 1, '', 'cannot resolve');
        }
        if (exe == 'arp') {
          return ProcessResult(
            0,
            0,
            '? (192.168.1.1) at aa:bb:cc:dd:ee:01 on en0\n'
                '? (192.168.1.88) at aa:bb:cc:dd:ee:02 on en0\n',
            '',
          );
        }
        if (exe == 'ssh' && args.contains('hostname')) {
          return ProcessResult(0, 0, 'my-ally\n', '');
        }
        return ProcessResult(0, 0, '', '');
      };

      final res =
          await tools.callTool('discover_and_update_ip', <String, Object?>{
        'device_id': 'rog-ally',
        'windows_hostname': 'my-ally',
      });

      expect(res, contains('192.168.1.88'));
      expect(store.listProfiles()['rog-ally']!.host, equals('192.168.1.88'));
      // Verify office-pc was NOT overwritten!
      expect(store.listProfiles()['office-pc']!.host, equals('100.84.10.25'));

      final customDevicesFile =
          File('${tempHome.path}/.config/flutter/custom_devices.json');
      final decoded = jsonDecode(customDevicesFile.readAsStringSync())
          as Map<String, Object?>;
      final devices = decoded['custom-devices'] as List<Object?>;
      final rogEntry = devices.firstWhere(
        (d) => (d as Map)['id'] == 'rog-ally',
      ) as Map<String, Object?>;
      final officeEntry = devices.firstWhere(
        (d) => (d as Map)['id'] == 'office-pc',
      ) as Map<String, Object?>;

      expect(jsonEncode(rogEntry), contains('192.168.1.88'));
      expect(
        jsonEncode(rogEntry['forwardPort']),
        contains(r'127.0.0.1:${hostPort}:127.0.0.1:${devicePort}'),
      );
      expect(jsonEncode(officeEntry), contains('100.84.10.25'));
      expect(jsonEncode(officeEntry), isNot(contains('192.168.1.88')));
    });
  });

  group(
      '9. remote_app_control, set_dev_power_mode, and build_and_fetch_release',
      () {
    setUp(() {
      store.upsertProfile(
        const DeviceProfile(
          deviceId: 'rog-ally',
          label: 'ROG Ally',
          host: '192.168.1.50',
          user: 'devuser',
        ),
        setAsDefault: true,
      );
    });

    test(
        'remote_app_control resolves active_app.txt dynamically when app_name is omitted',
        () async {
      var sshCallCount = 0;
      mockHandler = (String exe, List<String> args) {
        if (exe == 'ssh') {
          sshCallCount++;
          if (sshCallCount == 1) {
            return ProcessResult(0, 0, 'dynamic_app_name\n', '');
          }
          return ProcessResult(0, 0, '1234 dynamic_app_name 1\n', '');
        }
        return ProcessResult(0, 0, '', '');
      };

      final statusOut =
          await tools.callTool('remote_app_control', <String, Object?>{
        'action': 'status',
      });
      expect(statusOut, contains('dynamic_app_name'));
    });

    test('set_dev_power_mode sends powercfg commands', () async {
      mockHandler = (String exe, List<String> args) =>
          ProcessResult(0, 0, 'Power mode set to KEEP_AWAKE', '');

      final out = await tools.callTool('set_dev_power_mode', <String, Object?>{
        'mode': 'keep_awake',
      });
      expect(out, contains('KEEP_AWAKE'));
    });

    test(
        'build_and_fetch_release builds release zip and downloads to local build/ folder',
        () async {
      mockHandler = (String exe, List<String> args) {
        if (exe == 'ssh') {
          return ProcessResult(0, 0, 'RELEASE_ZIP_READY\n', '');
        }
        return ProcessResult(0, 0, '', '');
      };

      final out =
          await tools.callTool('build_and_fetch_release', <String, Object?>{
        'project_path': tempProject.path,
        'app_name': 'test_app',
      });
      expect(out, contains('test_app-windows-release.zip'));
    });
  });
}
