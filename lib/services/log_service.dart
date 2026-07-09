import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'log_export_stub.dart' if (dart.library.html) 'log_export_web.dart';

/// Structured log entry for AI call tracing.
class LogEntry {
  final String t; // ISO8601 UTC timestamp
  final String phase; // chatCompletion | chatCompletionWithTools | judgeFillBlankAnswer | app
  final String level; // info | warn | error
  final String msg; // Human-readable message
  final Map<String, dynamic>? data; // Optional structured payload

  LogEntry({
    required this.phase,
    required this.level,
    required this.msg,
    this.data,
  }) : t = DateTime.now().toUtc().toIso8601String();

  Map<String, dynamic> toJson() => {
        't': t,
        'phase': phase,
        'level': level,
        'msg': msg,
        if (data != null) 'data': data,
      };
}

/// In-memory ring buffer logger for AI call tracing.
///
/// Captures structured log entries during AI operations. Export via [export] —
/// web triggers browser download, non-web saves to application documents dir.
class LogService {
  LogService._();
  static final LogService instance = LogService._();

  static const int defaultCapacity = 500;
  final List<LogEntry> _buffer = [];
  int _capacity = defaultCapacity;

  /// Change ring buffer capacity (default 500).
  void setCapacity(int capacity) => _capacity = capacity;

  /// Add a log entry. Auto-evicts oldest when over capacity.
  void log(String phase, String level, String message, [Map<String, dynamic>? data]) {
    final entry = LogEntry(phase: phase, level: level, msg: message, data: data);
    _buffer.add(entry);
    if (_buffer.length > _capacity) {
      _buffer.removeAt(0);
    }
    // Mirror to console for dev mode visibility
    debugPrint('[${entry.t}] [$phase] [$level] $message${data != null ? ' $data' : ''}');
  }

  /// Get all log entries (unmodifiable).
  List<LogEntry> getAll() => List.unmodifiable(_buffer);

  /// Clear all log entries.
  void clear() => _buffer.clear();

  /// Export all entries as JSONL (one JSON object per line).
  String exportJsonl() {
    return _buffer.map((e) => jsonEncode(e.toJson())).join('\n');
  }

  /// Export logs to file. Returns filename on success, null on failure.
  Future<String?> export() async {
    final content = exportJsonl();
    final ts = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final filename = 'logs_$ts.jsonl';
    try {
      return await exportPlatformFile(content, filename);
    } catch (e) {
      debugPrint('Log export failed: $e');
      return null;
    }
  }
}
