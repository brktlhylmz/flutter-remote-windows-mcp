# Contributing to flutter-remote-windows-mcp

Thank you for your interest in contributing to **flutter-remote-windows-mcp**!

## Development Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/brktlhylmz/flutter-remote-windows-mcp.git
   cd flutter-remote-windows-mcp
   ```
2. Install dependencies:
   ```bash
   dart pub get
   ```
3. Run static analysis and tests:
   ```bash
   dart analyze
   dart test
   ```

## Guidelines

- **Zero External Runtime Dependencies**: Keep the MCP server lightweight using pure `dart:io`, `dart:convert`, and `dart:async` so users can install and run it instantly with `dart pub global activate`.
- **Privacy & Security First**: Any tool interacting with the remote Windows interactive desktop (`Session 1`) must respect user privacy (e.g., window-only capture via `PrintWindow`, fail-closed when the target Flutter app is not running, and locale-independent SIDs for SSH ACLs).
- **Formatting & Lints**: Ensure `dart format --output=none --set-exit-if-changed .` and `dart analyze` pass with zero warnings before opening a Pull Request.
