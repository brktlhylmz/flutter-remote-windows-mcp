import 'package:flutter_remote_windows_mcp/flutter_remote_windows_mcp.dart';
import 'package:test/test.dart';

void main() {
  group('WindowsRemoteTools', () {
    late WindowsRemoteTools tools;

    setUp(() {
      tools = WindowsRemoteTools();
    });

    test('exposes all 11 MCP tools with valid inputSchemas', () {
      final definitions = tools.getToolDefinitions();
      expect(definitions, hasLength(11));

      final names = definitions.map((d) => d['name'] as String).toList();
      expect(
        names,
        containsAll(<String>[
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
