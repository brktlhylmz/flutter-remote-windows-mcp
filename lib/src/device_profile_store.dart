import 'dart:convert';
import 'dart:io';

/// Represents a saved remote Windows device profile in
/// `~/.config/flutter_remote_windows/config.json`.
final class DeviceProfile {
  const DeviceProfile({
    required this.deviceId,
    required this.label,
    required this.host,
    required this.user,
    this.sshPort = 22,
    this.useTcpPing = true,
    this.keepHeadlessSessionAlive = false,
    this.defaultAppName,
  });

  factory DeviceProfile.fromJson(Map<String, Object?> json) {
    return DeviceProfile(
      deviceId: switch (json['device_id']) {
        final String s when s.isNotEmpty => s,
        _ => 'windows-remote',
      },
      label: switch (json['label']) {
        final String s when s.isNotEmpty => s,
        _ => 'Windows Remote Device',
      },
      host: switch (json['host']) {
        final String s => s,
        _ => '',
      },
      user: switch (json['user']) {
        final String s => s,
        _ => '',
      },
      sshPort: switch (json['ssh_port']) {
        final int p => p,
        _ => 22,
      },
      useTcpPing: switch (json['use_tcp_ping']) {
        final bool b => b,
        _ => true,
      },
      keepHeadlessSessionAlive: switch (json['keep_headless_session_alive']) {
        final bool b => b,
        _ => false,
      },
      defaultAppName: switch (json['default_app_name']) {
        final String s when s.isNotEmpty => s,
        _ => null,
      },
    );
  }

  final String deviceId;
  final String label;
  final String host;
  final String user;
  final int sshPort;
  final bool useTcpPing;
  final bool keepHeadlessSessionAlive;
  final String? defaultAppName;

  DeviceProfile copyWith({
    String? deviceId,
    String? label,
    String? host,
    String? user,
    int? sshPort,
    bool? useTcpPing,
    bool? keepHeadlessSessionAlive,
    String? defaultAppName,
  }) {
    return DeviceProfile(
      deviceId: deviceId ?? this.deviceId,
      label: label ?? this.label,
      host: host ?? this.host,
      user: user ?? this.user,
      sshPort: sshPort ?? this.sshPort,
      useTcpPing: useTcpPing ?? this.useTcpPing,
      keepHeadlessSessionAlive:
          keepHeadlessSessionAlive ?? this.keepHeadlessSessionAlive,
      defaultAppName: defaultAppName ?? this.defaultAppName,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'device_id': deviceId,
      'label': label,
      'host': host,
      'user': user,
      'ssh_port': sshPort,
      'use_tcp_ping': useTcpPing,
      'keep_headless_session_alive': keepHeadlessSessionAlive,
      if (defaultAppName case final String app when app.isNotEmpty)
        'default_app_name': app,
    };
  }
}

/// Manages reading and writing `~/.config/flutter_remote_windows/config.json`.
final class DeviceProfileStore {
  DeviceProfileStore({String? configFilePath})
      : _configFilePath = configFilePath ?? _defaultConfigPath();

  final String _configFilePath;

  static String _defaultConfigPath() {
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '';
    return '$home/.config/flutter_remote_windows/config.json';
  }

  String get configFilePath => _configFilePath;

  Map<String, Object?> _readRaw() {
    final file = File(_configFilePath);
    if (!file.existsSync()) {
      return <String, Object?>{
        'default_device': null,
        'devices': <String, Object?>{},
      };
    }
    try {
      if (jsonDecode(file.readAsStringSync())
          case final Map<String, Object?> decoded) {
        return Map<String, Object?>.from(decoded);
      }
    } on Object {
      // Fall back to empty config on parse error
    }
    return <String, Object?>{
      'default_device': null,
      'devices': <String, Object?>{},
    };
  }

  void _writeRaw(Map<String, Object?> data) {
    final file = File(_configFilePath);
    if (!file.parent.existsSync()) {
      file.parent.createSync(recursive: true);
    }
    const encoder = JsonEncoder.withIndent('  ');
    file.writeAsStringSync('${encoder.convert(data)}\n');
  }

  String? getDefaultDeviceId() => switch (_readRaw()['default_device']) {
        final String s when s.isNotEmpty => s,
        _ => null,
      };

  Map<String, DeviceProfile> listProfiles() {
    final raw = _readRaw();
    final result = <String, DeviceProfile>{};
    if (raw['devices'] case final Map<String, Object?> devicesMap) {
      for (final MapEntry(:key, :value) in devicesMap.entries) {
        if (value case final Map<String, Object?> profileJson) {
          result[key] = DeviceProfile.fromJson(profileJson);
        }
      }
    }
    return result;
  }

  void upsertProfile(DeviceProfile profile, {bool setAsDefault = false}) {
    final raw = _readRaw();
    final devices = switch (raw['devices']) {
      final Map<String, Object?> m => Map<String, Object?>.from(m),
      _ => <String, Object?>{},
    };
    devices[profile.deviceId] = profile.toJson();
    raw['devices'] = devices;
    if (setAsDefault || raw['default_device'] == null) {
      raw['default_device'] = profile.deviceId;
    }
    _writeRaw(raw);
  }

  bool setDefaultDevice(String deviceId) {
    final raw = _readRaw();
    final devices = switch (raw['devices']) {
      final Map<String, Object?> m => Map<String, Object?>.from(m),
      _ => <String, Object?>{},
    };
    if (!devices.containsKey(deviceId)) {
      return false;
    }
    raw['default_device'] = deviceId;
    _writeRaw(raw);
    return true;
  }

  bool removeProfile(String deviceId) {
    final raw = _readRaw();
    final devices = switch (raw['devices']) {
      final Map<String, Object?> m => Map<String, Object?>.from(m),
      _ => <String, Object?>{},
    };
    final removed = devices.remove(deviceId) != null;
    raw['devices'] = devices;
    if (raw['default_device'] == deviceId) {
      raw['default_device'] =
          devices.keys.isNotEmpty ? devices.keys.first : null;
    }
    _writeRaw(raw);
    return removed;
  }

  /// Resolves connection parameters (`host`, `user`, `sshPort`, `deviceId`, etc.)
  /// by merging explicit tool arguments with the saved profile in `config.json`.
  DeviceProfile resolve(Map<String, Object?> args) {
    final profiles = listProfiles();
    final requestedId = (args['device_id'] as String?)?.trim();
    final defaultId = getDefaultDeviceId();

    final base = switch ((requestedId, defaultId)) {
      (final String req?, _) when req.isNotEmpty && profiles.containsKey(req) =>
        profiles[req],
      (null, final String def?) when profiles.containsKey(def) => profiles[def],
      (null, _) when profiles.length == 1 => profiles.values.first,
      _ => null,
    };

    final host = switch (args['host']) {
      final String s when s.trim().isNotEmpty => s.trim(),
      _ => base?.host ?? '',
    };
    final user = switch (args['user']) {
      final String s when s.trim().isNotEmpty => s.trim(),
      _ => base?.user ?? '',
    };
    final sshPort = switch (args['ssh_port']) {
      final int p => p,
      _ => base?.sshPort ?? 22,
    };
    final deviceId = (requestedId != null && requestedId.isNotEmpty)
        ? requestedId
        : (base?.deviceId ?? defaultId ?? 'rog-ally');
    final label = switch (args['device_label']) {
      final String s when s.trim().isNotEmpty => s.trim(),
      _ => base?.label ?? '$deviceId (Wireless Windows)',
    };
    final useTcpPing = switch (args['use_tcp_ping']) {
      final bool b => b,
      _ => base?.useTcpPing ?? true,
    };
    final keepHeadlessSessionAlive =
        switch (args['keep_headless_session_alive']) {
      final bool b => b,
      _ => base?.keepHeadlessSessionAlive ?? false,
    };
    final appName = switch (args['app_name']) {
      final String s when s.trim().isNotEmpty => s.trim(),
      _ => base?.defaultAppName,
    };

    if (host.isEmpty || user.isEmpty) {
      throw ArgumentError(
        'Missing "host" or "user". Either pass them explicitly or save a device profile in $_configFilePath using setup_flutter_custom_device / manage_device_profiles.',
      );
    }

    return DeviceProfile(
      deviceId: deviceId,
      label: label,
      host: host,
      user: user,
      sshPort: sshPort,
      useTcpPing: useTcpPing,
      keepHeadlessSessionAlive: keepHeadlessSessionAlive,
      defaultAppName: appName,
    );
  }
}
