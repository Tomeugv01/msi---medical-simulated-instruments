import 'package:flutter/foundation.dart';

enum LogLevel { debug, info, warning, error }

class LoggerService {
  static bool enableFileLogging = false;
  static final List<String> _logBuffer = [];
  static final List<String> _errorBuffer = [];

  static void log(String message, {LogLevel level = LogLevel.debug}) {
    debugPrint(message);
    _logBuffer.add(message);
    if (level == LogLevel.error) {
      _errorBuffer.add(message);
    }
  }

  static List<String> getLogs() => List.unmodifiable(_logBuffer);
  static List<String> getErrors() => List.unmodifiable(_errorBuffer);
  static void clearLogs() {
    _logBuffer.clear();
    _errorBuffer.clear();
  }
}
