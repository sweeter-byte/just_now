/// Just Now - Intent Service
/// Handles API communication with the backend.
/// Now includes user location in requests for LBS integration.
/// Supports voice upload via Record & Upload architecture (Route B).

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:geolocator/geolocator.dart';
import '../models/genui_models.dart';

/// Service for managing device location
class LocationService {
  /// Cached position (updated periodically or on demand)
  static Position? _cachedPosition;

  /// Check if location services are available and get current position
  static Future<Position?> getCurrentPosition() async {
    try {
      // Check if location services are enabled
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        // Location services are disabled
        return null;
      }

      // Check and request permission
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          // Permission denied
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        // Permissions permanently denied
        return null;
      }

      // Get current position with reasonable accuracy
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      _cachedPosition = position;
      return position;
    } catch (e) {
      // Return cached position if available, otherwise null
      return _cachedPosition;
    }
  }

  /// Get cached position (doesn't make new request)
  static Position? getCachedPosition() => _cachedPosition;

  /// Update cached position in background
  static Future<void> refreshPosition() async {
    await getCurrentPosition();
  }
}

class IntentService {
  // Android Emulator: 10.0.2.2 maps to host localhost
  // Physical device: Use your machine's IP address
  static const String _baseUrl = 'http://192.168.1.57:8000'; // lastest ip 10.0.2.2

  /// Process user intent and get GenUI response.
  /// Automatically includes user location if available.
  static Future<GenUIResponse> processIntent({
    required String textInput,
    String? mockScenario,
    double? currentLat,
    double? currentLng,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/v1/intent/process');

    // Try to get location if not provided
    double? lat = currentLat;
    double? lng = currentLng;

    if (lat == null || lng == null) {
      final position = await LocationService.getCurrentPosition();
      if (position != null) {
        lat = position.latitude;
        lng = position.longitude;
      }
    }

    // Build request body with location data
    final Map<String, dynamic> bodyMap = {
      'text_input': textInput,
    };

    if (mockScenario != null) {
      bodyMap['mock_scenario'] = mockScenario;
    }

    // Include location if available
    if (lat != null && lng != null) {
      bodyMap['current_lat'] = lat;
      bodyMap['current_lng'] = lng;
    }

    final body = jsonEncode(bodyMap);

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
        const Duration(seconds: 60),
        onTimeout: () {
          throw IntentServiceException(
            code: 'TIMEOUT',
            message: 'Request timed out after 60 seconds',
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

  /// Process intent with explicit location override
  static Future<GenUIResponse> processIntentWithLocation({
    required String textInput,
    required double latitude,
    required double longitude,
    String? mockScenario,
  }) async {
    return processIntent(
      textInput: textInput,
      mockScenario: mockScenario,
      currentLat: latitude,
      currentLng: longitude,
    );
  }

  /// Send voice command by uploading audio file to backend.
  /// Uses Route B: Record & Upload architecture.
  ///
  /// The backend will:
  /// 1. Receive the audio file
  /// 2. Transcribe using Whisper model
  /// 3. Process intent and return GenUI response
  static Future<GenUIResponse> sendVoiceCommand({
    required String filePath,
    double? currentLat,
    double? currentLng,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/v1/voice');

    // Try to get location if not provided
    double? lat = currentLat;
    double? lng = currentLng;

    if (lat == null || lng == null) {
      final position = await LocationService.getCurrentPosition();
      if (position != null) {
        lat = position.latitude;
        lng = position.longitude;
      }
    }

    try {
      // Create multipart request
      final request = http.MultipartRequest('POST', uri);

      // Add headers
      request.headers['X-Device-Id'] = 'demo-device-001';
      if (lat != null) {
        request.headers['X-Current-Lat'] = lat.toString();
      }
      if (lng != null) {
        request.headers['X-Current-Lng'] = lng.toString();
      }

      // Determine content type based on file extension
      final file = File(filePath);
      final extension = filePath.split('.').last.toLowerCase();
      MediaType contentType;
      switch (extension) {
        case 'm4a':
          contentType = MediaType('audio', 'm4a');
          break;
        case 'aac':
          contentType = MediaType('audio', 'aac');
          break;
        case 'mp3':
          contentType = MediaType('audio', 'mpeg');
          break;
        case 'wav':
        default:
          contentType = MediaType('audio', 'wav');
          break;
      }

      // Add the audio file
      request.files.add(
        await http.MultipartFile.fromPath(
          'audio',
          filePath,
          contentType: contentType,
          filename: 'voice_input.$extension',
        ),
      );

      // Send request
      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 120),
        onTimeout: () {
          throw IntentServiceException(
            code: 'TIMEOUT',
            message: '语音处理超时，请重试',
          );
        },
      );

      // Parse response
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return GenUIResponse.fromJson(json);
      } else {
        // Parse error response
        try {
          final errorJson = jsonDecode(response.body) as Map<String, dynamic>;
          throw IntentServiceException(
            code: errorJson['error_code'] as String? ?? 'UNKNOWN',
            message: errorJson['message'] as String? ?? '未知错误',
            userTip: errorJson['user_tip'] as String?,
          );
        } catch (e) {
          if (e is IntentServiceException) rethrow;
          throw IntentServiceException(
            code: 'SERVER_ERROR',
            message: '服务器错误: ${response.statusCode}',
          );
        }
      }
    } on SocketException catch (e) {
      throw IntentServiceException(
        code: 'NETWORK_ERROR',
        message: '网络连接失败: $e',
      );
    } on FormatException catch (e) {
      throw IntentServiceException(
        code: 'PARSE_ERROR',
        message: '响应解析失败: $e',
      );
    } on http.ClientException catch (e) {
      throw IntentServiceException(
        code: 'NETWORK_ERROR',
        message: '网络错误: $e',
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
