import 'dart:convert';
import 'dart:io';

/// Represents a saved remote Windows device profile in
/// `~/.config/flutter_remote_windows/config.json`.
class DeviceProfile {
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
      deviceId: (json['device_id'] as String?) ?? 'windows-remote',
      label: (json['label'] as String?) ?? 'Windows Remote Device',
      host: (json['host'] as String?) ?? '',
      user: (json['user'] as String?) ?? '',
      sshPort: (json['ssh_port'] as int?) ?? 22,
      useTcpPing: (json['use_tcp_ping'] as bool?) ?? true,
      keepHeadlessSessionAlive:
          (json['keep_headless_session_alive'] as bool?) ?? false,
      defaultAppName: json['default_app_name'] as String?,
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
      if (defaultAppName != null && defaultAppName!.isNotEmpty)
        'default_app_name': defaultAppName,
    };
  }
}

/// Manages reading and writing `~/.config/flutter_remote_windows/config.json`.
class DeviceProfileStore {
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
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is Map<String, Object?>) {
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

  String? getDefaultDeviceId() {
    final raw = _readRaw();
    return raw['default_device'] as String?;
  }

  Map<String, DeviceProfile> listProfiles() {
    final raw = _readRaw();
    final devicesMap = raw['devices'];
    final result = <String, DeviceProfile>{};
    if (devicesMap is Map<String, Object?>) {
      for (final entry in devicesMap.entries) {
        if (entry.value is Map<String, Object?>) {
          result[entry.key] = DeviceProfile.fromJson(
            Map<String, Object?>.from(entry.value! as Map<String, Object?>),
          );
        }
      }
    }
    return result;
  }

  void upsertProfile(DeviceProfile profile, {bool setAsDefault = false}) {
    final raw = _readRaw();
    final devices = (raw['devices'] is Map<String, Object?>)
        ? Map<String, Object?>.from(raw['devices']! as Map<String, Object?>)
        : <String, Object?>{};
    devices[profile.deviceId] = profile.toJson();
    raw['devices'] = devices;
    if (setAsDefault || raw['default_device'] == null) {
      raw['default_device'] = profile.deviceId;
    }
    _writeRaw(raw);
  }

  bool setDefaultDevice(String deviceId) {
    final raw = _readRaw();
    final devices = (raw['devices'] is Map<String, Object?>)
        ? Map<String, Object?>.from(raw['devices']! as Map<String, Object?>)
        : <String, Object?>{};
    if (!devices.containsKey(deviceId)) {
      return false;
    }
    raw['default_device'] = deviceId;
    _writeRaw(raw);
    return true;
  }

  bool removeProfile(String deviceId) {
    final raw = _readRaw();
    final devices = (raw['devices'] is Map<String, Object?>)
        ? Map<String, Object?>.from(raw['devices']! as Map<String, Object?>)
        : <String, Object?>{};
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

    DeviceProfile? base;
    if (requestedId != null &&
        requestedId.isNotEmpty &&
        profiles.containsKey(requestedId)) {
      base = profiles[requestedId];
    } else if (requestedId == null &&
        defaultId != null &&
        profiles.containsKey(defaultId)) {
      base = profiles[defaultId];
    } else if (requestedId == null && profiles.length == 1) {
      base = profiles.values.first;
    }

    final host = ((args['host'] as String?)?.trim().isNotEmpty == true)
        ? (args['host'] as String).trim()
        : (base?.host ?? '');
    final user = ((args['user'] as String?)?.trim().isNotEmpty == true)
        ? (args['user'] as String).trim()
        : (base?.user ?? '');
    final sshPort = (args['ssh_port'] as int?) ?? (base?.sshPort ?? 22);
    final deviceId = (requestedId != null && requestedId.isNotEmpty)
        ? requestedId
        : (base?.deviceId ?? defaultId ?? 'rog-ally');
    final label = ((args['device_label'] as String?)?.trim().isNotEmpty == true)
        ? (args['device_label'] as String).trim()
        : (base?.label ?? '$deviceId (Wireless Windows)');
    final useTcpPing =
        (args['use_tcp_ping'] as bool?) ?? (base?.useTcpPing ?? true);
    final keepHeadlessSessionAlive =
        (args['keep_headless_session_alive'] as bool?) ??
            (base?.keepHeadlessSessionAlive ?? false);
    final appName = ((args['app_name'] as String?)?.trim().isNotEmpty == true)
        ? (args['app_name'] as String).trim()
        : base?.defaultAppName;

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
