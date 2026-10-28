# flutter-remote-windows-mcp

Model Context Protocol (MCP) server built in pure Dart for developing and debugging **Flutter Windows Desktop** apps wirelessly from **macOS / Linux** (ideal for handhelds like **ASUS ROG Ally**, **Lenovo Legion Go**, or remote Windows PCs).

## Features & 11 MCP Tools

1. **`generate_ssh_pairing`**: Starts a local HTTP server and generates a 1-line PowerShell pairing command (`irm http://<MAC_IP>:8765 | iex`) that configures passwordless SSH on Windows 11 (including Microsoft Account / Windows Hello PIN setups and locale-independent Administrator ACLs `*S-1-5-32-544`).
2. **`check_remote_windows`**: Inspects the remote Windows machine over SSH (Hostname, OS version, disk space, Git, FVM, Sidekick, Flutter SDK version, and Visual Studio C++ Build Tools).
3. **`install_windows_toolchain`**: Remotely installs FVM, Sidekick (with Desktop shortcut), Flutter SDK (`stable`), and Microsoft Visual Studio 2022 C++ Build Tools (`VCTools`) via SSH.
4. **`sync_flutter_version`**: Reads the active Flutter SDK version on the Mac (or `.fvmrc`) and syncs the Windows device to the **exact same Flutter version** via FVM so Dart VM `kernel_blob.bin` snapshots always match.
5. **`setup_flutter_custom_device`**: Configures `flutter custom-devices`, `~/.ssh/config`, `.vscode/launch.json`, the **smart `postBuild` hook** (which automatically rebuilds the Windows C++ runner whenever native plugins or `windows/` files change!), and deploys the Windows Interactive Desktop (`Session 1`) Task Scheduler bridge (`FlutterRemoteRun` & `FlutterRemoteScreenshot`).
6. **`sync_and_rebuild_windows_runner`**: Syncs your Flutter project to an isolated project folder (`projects/<appName>`) on the Windows device, ensures Flutter version parity, and runs `flutter build windows --debug` remotely to update the `.exe` and C++ plugin `.dll` files.
7. **`take_remote_screenshot`**: Privacy-safe window-only screenshot tool: captures **only** the running Flutter application window (`PrintWindow` + `DWMWA_EXTENDED_FRAME_BOUNDS`) in `Session 1` without exposing the Windows desktop, taskbar, or personal apps, and fails closed if the target app is not running.
8. **`set_dev_power_mode`**: Prevents the Windows handheld/PC from turning off its screen or entering sleep (`keep_awake` / `restore_default`) during wireless development.
9. **`discover_and_update_ip`**: Automatically discovers the Windows device's new IP address on the local Wi-Fi network (via mDNS `.local` or ARP/SSH scan) and updates all config files.
10. **`build_and_fetch_release`**: Builds a production Windows Release bundle (`flutter build windows --release`) on the remote Windows machine and downloads `<appName>-windows-release.zip` directly to your Mac's `build/` folder.
11. **`remote_app_control`**: Manages the remote device (`status`, `logs`, `stop`, `launch_test`, and `update_ip`).
