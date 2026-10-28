# flutter-remote-windows-mcp

Model Context Protocol (MCP) server built in pure Dart for developing and debugging **Flutter Windows Desktop** apps wirelessly from **macOS / Linux** (ideal for handhelds like **ASUS ROG Ally**, **Lenovo Legion Go**, or remote Windows PCs).

## Features & MCP Tools

1. **`generate_ssh_pairing`**: Generates a one-line PowerShell pairing command (`irm http://<MAC_IP>:8765 | iex`) that configures passwordless SSH on Windows 11 (including Microsoft Account / Windows Hello PIN setups and locale-independent Administrator ACLs `*S-1-5-32-544`).
2. **`check_remote_windows`**: Inspects the remote Windows machine over SSH (OS version, disk space, Git, FVM, Sidekick, Flutter SDK, and Visual Studio C++ Build Tools).
3. **`install_windows_toolchain`**: Remotely installs FVM, Sidekick, Flutter SDK (`stable`), and Microsoft Visual Studio 2022 C++ Build Tools (`VCTools`) via SSH.
4. **`setup_flutter_custom_device`**: Configures `flutter custom-devices`, `~/.ssh/config`, `.vscode/launch.json`, and deploys the Windows Interactive Desktop (`Session 1`) Task Scheduler bridge (`FlutterRemoteRun`, `session1_runner.ps1`, `run_debug.ps1`) with automatic `FLUTTER_ENGINE_SWITCHES` forwarding and `running.lock` lifecycle management.
5. **`sync_and_rebuild_windows_runner`**: Syncs your Flutter project's `pubspec.yaml`, `lib/`, and `windows/` directory to the Windows device and runs `flutter build windows --debug` remotely to update the `.exe` and C++ plugin `.dll` files.
6. **`remote_app_control`**: Manages the remote device (`status`, `logs`, `stop`, and `update_ip` when the Windows device's Wi-Fi IP changes).

## Installation

```bash
dart pub global activate --source path .
```

## MCP Configuration (`mcp_config.json`)

```json
{
  "mcpServers": {
    "flutter-remote-windows": {
      "command": "flutter-remote-windows-mcp",
      "args": []
    }
  }
}
```
