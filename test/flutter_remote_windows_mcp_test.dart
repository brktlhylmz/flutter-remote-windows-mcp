import 'dart:io';

import 'package:flutter_remote_windows_mcp/flutter_remote_windows_mcp.dart';
import 'package:test/test.dart';

void main() {
  group('WindowsRemoteTools & DeviceProfileStore', () {
    late Directory tempDir;
    late DeviceProfileStore store;
    late WindowsRemoteTools tools;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('flutter_remote_test_');
      store = DeviceProfileStore(
        configFilePath: '${tempDir.path}/config.json',
      );
      tools = WindowsRemoteTools(profileStore: store);
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('exposes all 12 MCP tools with valid inputSchemas', () {
      final definitions = tools.getToolDefinitions();
      expect(definitions, hasLength(12));

      final names = definitions.map((d) => d['name'] as String).toList();
      expect(
        names,
        containsAll(<String>[
          'manage_device_profiles',
          'generate_ssh_pairing',
          'check_remote_windows',
          'install_windows_toolchain',
          'sync_flutter_version',
          'setup_flutter_custom_device',
          'sync_and_rebuild_windows_runner',
          'take_remote_screenshot',
          'set_dev_power_mode',
          'discover_and_update_ip',
          'build_and_fetch_release',
          'remote_app_control',
        ]),
      );

      for (final def in definitions) {
        expect(def['description'], isA<String>());
        expect((def['description'] as String).isNotEmpty, isTrue);
        expect(def['inputSchema'], isA<Map<String, Object?>>());
      }
    });

    test('saves, resolves, and switches default device profiles in config.json',
        () {
      store.upsertProfile(
        const DeviceProfile(
          deviceId: 'rog-ally',
          label: 'ASUS ROG Ally',
          host: '192.168.1.50',
          user: 'devuser',
        ),
        setAsDefault: true,
      );
      store.upsertProfile(
        const DeviceProfile(
          deviceId: 'office-pc',
          label: 'Office Windows PC (Tailscale)',
          host: '100.84.10.25',
          user: 'officeuser',
          sshPort: 2222,
          keepHeadlessSessionAlive: true,
        ),
      );

      // Resolves default profile when no args are passed
      final resolvedDefault = store.resolve(<String, Object?>{});
      expect(resolvedDefault.deviceId, equals('rog-ally'));
      expect(resolvedDefault.host, equals('192.168.1.50'));
      expect(resolvedDefault.sshPort, equals(22));

      // Resolves specific profile by device_id without repeating host/user/ssh_port
      final resolvedOffice = store.resolve(<String, Object?>{
        'device_id': 'office-pc',
      });
      expect(resolvedOffice.host, equals('100.84.10.25'));
      expect(resolvedOffice.user, equals('officeuser'));
      expect(resolvedOffice.sshPort, equals(2222));
      expect(resolvedOffice.keepHeadlessSessionAlive, isTrue);
    });
  });

  group('PowerShellTemplates', () {
    test('sshPairingScript uses locale-independent SIDs', () {
      final script = PowerShellTemplates.sshPairingScript(
        'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKey user@host',
      );
      expect(script, contains('*S-1-5-32-544:F'));
      expect(script, contains('*S-1-5-18:F'));
      expect(script, contains('administrators_authorized_keys'));
    });

    test('session1RunnerScript sets FLUTTER_ENGINE_SWITCHES and tracks PID',
        () {
      final script = PowerShellTemplates.session1RunnerScript(
        remoteBaseDir: r'C:\Users\dev\flutter_remote',
        defaultAppName: 'my_flutter_app',
      );
      expect(script, contains('FLUTTER_ENGINE_SWITCHES'));
      expect(script, contains('active_app.pid'));
      expect(script, contains('running.lock'));
    });

    test('runDebugScript re-attaches disconnected RDP/VM sessions via tscon',
        () {
      final script = PowerShellTemplates.runDebugScript(
        remoteBaseDir: r'C:\Users\dev\flutter_remote',
        defaultAppName: 'my_flutter_app',
        scheduledTaskName: 'FlutterRemoteRun',
      );
      expect(script, contains('keep_headless.flag'));
      expect(script, contains('tscon.exe'));
    });

    test(
        'screenshotSession1Script enforces window-only PrintWindow and fail-closed privacy',
        () {
      final script = PowerShellTemplates.screenshotSession1Script(
        remoteBaseDir: r'C:\Users\dev\flutter_remote',
      );
      expect(script, contains('PrintWindow'));
      expect(script, contains('DwmGetWindowAttribute'));
      expect(script, contains('ERR_NO_APP'));
      expect(script, contains('ERR_MINIMIZED'));
      expect(script, isNot(contains('CopyFromScreen')));
    });
  });
}
