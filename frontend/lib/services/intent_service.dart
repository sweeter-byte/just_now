/// Just Now - Intent Service
/// Handles API communication with the backend.

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/genui_models.dart';

class IntentService {
  // Android Emulator: 10.0.2.2 maps to host localhost
  // Physical device: Use your machine's IP address
  static const String _baseUrl = 'http://10.0.2.2:8000';

  /// Process user intent and get GenUI response.
  static Future<GenUIResponse> processIntent({
    required String textInput,
    String? mockScenario,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/v1/intent/process');

    final body = jsonEncode({
      'text_input': textInput,
      if (mockScenario != null) 'mock_scenario': mockScenario,
    });

    try {
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          // Demo headers (signature skipped per guardrails)
          'X-Device-Id': 'demo-device-001',
        },
        body: body,
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw IntentServiceException(
            code: 'TIMEOUT',
            message: 'Request timed out after 10 seconds',
          );
        },
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return GenUIResponse.fromJson(json);
      } else {
        // Parse error response
        final errorJson = jsonDecode(response.body) as Map<String, dynamic>;
        throw IntentServiceException(
          code: errorJson['error_code'] as String? ?? 'UNKNOWN',
          message: errorJson['message'] as String? ?? 'Unknown error',
          userTip: errorJson['user_tip'] as String?,
        );
      }
    } on FormatException catch (e) {
      throw IntentServiceException(
        code: 'PARSE_ERROR',
        message: 'Failed to parse response: $e',
      );
    } on http.ClientException catch (e) {
      throw IntentServiceException(
        code: 'NETWORK_ERROR',
        message: 'Network error: $e',
      );
    }
  }
}

class IntentServiceException implements Exception {
  final String code;
  final String message;
  final String? userTip;

  IntentServiceException({
    required this.code,
    required this.message,
    this.userTip,
  });

  @override
  String toString() => 'IntentServiceException($code): $message';
}
