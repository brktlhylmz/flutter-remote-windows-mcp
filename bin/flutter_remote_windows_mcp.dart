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

    final Object? decoded;
    try {
      decoded = jsonDecode(trimmed);
    } on Object {
      continue;
    }

    // Match JSON-RPC 2.0 requests that carry both an "id" and a "method"
    if (decoded case {'id': final Object id, 'method': final String method}) {
      final params = switch (decoded['params']) {
        final Map<String, Object?> p => p,
        _ => const <String, Object?>{},
      };

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
                'version': '0.3.0',
              },
            });

          case 'ping':
            _sendResult(id, const <String, Object?>{});

          case 'tools/list':
            _sendResult(id, <String, Object?>{
              'tools': tools.getToolDefinitions(),
            });

          case 'tools/call':
            final toolName = switch (params['name']) {
              final String s when s.isNotEmpty => s,
              _ => null,
            };
            final toolArgs = switch (params['arguments']) {
              final Map<String, Object?> a => a,
              _ => const <String, Object?>{},
            };
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
}

void _sendResult(Object id, Map<String, Object?> result) {
  stdout.writeln(
    jsonEncode(<String, Object?>{
      'jsonrpc': '2.0',
      'id': id,
      'result': result,
    }),
  );
}

void _sendError(Object id, int code, String message) {
  stdout.writeln(
    jsonEncode(<String, Object?>{
      'jsonrpc': '2.0',
      'id': id,
      'error': <String, Object?>{
        'code': code,
        'message': message,
      },
    }),
  );
}
