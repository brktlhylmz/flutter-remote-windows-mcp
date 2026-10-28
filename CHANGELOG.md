# Changelog

All notable changes to this project will be documented in this file.

## 0.3.0

- **Device Profiles (`~/.config/flutter_remote_windows/config.json` & `manage_device_profiles`)**: Save multiple Windows device profiles (e.g., `rog-ally`, `office-pc`, `cloud-vm`) so you never have to repeat `host`, `user`, or `ssh_port` across tool calls.
- **Remote Office PCs & Cloud VMs Support**:
  - **Custom `ssh_port`**: Full support for non-standard SSH ports (`ssh -p` and `scp -P`) across all tools and the `postBuild` hook.
  - **TCP Ping (`use_tcp_ping`)**: Uses `nc -z` against the SSH port instead of ICMP `ping` so cloud VMs (AWS/Azure/GCP) and firewalled office PCs that block ICMP echo requests appear online in `flutter devices`.
  - **Headless VM / Disconnected RDP Console Keep-Alive (`keep_headless_session_alive`)**: Automatically re-attaches disconnected RDP sessions (`Disc`) to the physical/virtual console via `tscon.exe <SessionId> /dest:console` before launching the Flutter app or taking a window screenshot.

## 0.2.0

- **Privacy-Safe Window-Only Screenshots (`take_remote_screenshot`)**: Uses Win32 `PrintWindow` (`PW_RENDERFULLCONTENT`) and `DwmGetWindowAttribute` (`DWMWA_EXTENDED_FRAME_BOUNDS`) to capture **only** the running Flutter application window without exposing the Windows desktop, taskbar, notifications, or personal windows. Fails closed (`ERR_NO_APP` / `ERR_MINIMIZED`) when the target app is not running.
- **Flutter Version Parity (`sync_flutter_version`)**: Automatically checks the host's active Flutter version (or `.fvmrc`) and syncs the remote Windows device via FVM so Dart VM `kernel_blob.bin` snapshots always match.
- **Smart `postBuild` Auto-Rebuild Hook**: Fingerprints `windows/`, `.flutter-plugins-dependencies`, and engine revision on every `F5` / `flutter run`, automatically rebuilding the remote Windows C++ runner only when native plugins or C++ sources change.
- **Multi-Project Isolation**: Caches compiled Windows runners per project (`runners/<appName>`) and dynamically switches based on `${appName}`.
- **Power & Network Utilities**: Added `set_dev_power_mode`, `discover_and_update_ip`, and `build_and_fetch_release`.

## 0.1.0

- Initial release with core MCP tools (`generate_ssh_pairing`, `check_remote_windows`, `install_windows_toolchain`, `setup_flutter_custom_device`, `sync_and_rebuild_windows_runner`, `remote_app_control`).
