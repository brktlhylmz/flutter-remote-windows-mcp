import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_remote_windows_mcp/flutter_remote_windows_mcp.dart';

Future<void> main(List<String> arguments) async {
  final tools = WindowsRemoteTools();
  final lines = stdin.transform(utf8.decoder).transform(const LineSplitter());

  await for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;

    Object? decoded;
    try {
      decoded = jsonDecode(trimmed);
    } on Object {
      continue;
    }

    if (decoded is! Map<String, Object?>) continue;

    final id = decoded['id'];
    final method = decoded['method'] as String?;
    final params =
        (decoded['params'] as Map<String, Object?>?) ?? <String, Object?>{};

    if (method == null) continue;

    // Notifications (no id) do not expect a response
    if (id == null) {
      continue;
    }

    try {
      switch (method) {
        case 'initialize':
          _sendResult(id, <String, Object?>{
            'protocolVersion': '2024-11-05',
            'capabilities': <String, Object?>{
              'tools': <String, Object?>{},
            },
            'serverInfo': <String, Object?>{
              'name': 'flutter-remote-windows-mcp',
              'version': '0.1.0',
            },
          });

        case 'ping':
          _sendResult(id, <String, Object?>{});

        case 'tools/list':
          _sendResult(id, <String, Object?>{
            'tools': tools.getToolDefinitions(),
          });

        case 'tools/call':
          final toolName = params['name'] as String?;
          final toolArgs = (params['arguments'] as Map<String, Object?>?) ??
              <String, Object?>{};
          if (toolName == null) {
            _sendError(id, -32602, 'Missing tool name');
            continue;
          }
          try {
            final output = await tools.callTool(toolName, toolArgs);
            _sendResult(id, <String, Object?>{
              'content': <Object?>[
                <String, Object?>{
                  'type': 'text',
                  'text': output,
                },
              ],
              'isError': false,
            });
          } on Object catch (e) {
            _sendResult(id, <String, Object?>{
              'content': <Object?>[
                <String, Object?>{
                  'type': 'text',
                  'text': 'Error: $e',
                },
              ],
              'isError': true,
            });
          }

        default:
          _sendError(id, -32601, 'Method not found: $method');
      }
    } on Object catch (e) {
      _sendError(id, -32603, 'Internal error: $e');
    }
  }
}

void _sendResult(Object id, Map<String, Object?> result) {
  final msg = jsonEncode(<String, Object?>{
    'jsonrpc': '2.0',
    'id': id,
    'result': result,
  });
  stdout.writeln(msg);
}

void _sendError(Object id, int code, String message) {
  final msg = jsonEncode(<String, Object?>{
    'jsonrpc': '2.0',
    'id': id,
    'error': <String, Object?>{
      'code': code,
      'message': message,
    },
  });
  stdout.writeln(msg);
}
