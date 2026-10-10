import 'package:dio/dio.dart';

class AuthService {
  static const String baseUrl = 'http://127.0.0.1:8000/api';

  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      headers: {
        'Content-Type': 'application/json',
      },
    ),
  );

  // ─── Login ────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _dio.post(
        '/auth/login/',
        data: {
          'email': email,
          'password': password,
        },
      );

      return Map<String, dynamic>.from(response.data);
    } on DioException catch (e) {
      if (e.response != null) {
        final data = e.response?.data;

        // Handle our custom pending/rejected error codes.
        if (data is Map) {
          final errorCode = data['error_code']?.toString();
          final detail = data['detail']?.toString();

          if (errorCode == 'pending_approval') {
            throw PendingApprovalException(
              detail ??
                  'Your registration is waiting for authority approval.',
            );
          }

          if (errorCode == 'registration_rejected') {
            final reason = data['rejection_reason']?.toString();
            throw RegistrationRejectedException(
              detail ??
                  'Your registration has been rejected by the authority.',
              rejectionReason: (reason != null && reason.trim().isNotEmpty)
                  ? reason.trim()
                  : null,
            );
          }

          // DRF ValidationError wraps errors in a list under 'non_field_errors'
          // or as a nested map. Flatten for display.
          if (detail != null) {
            throw Exception(detail);
          }
        }

        throw Exception(
          e.response?.data?.toString() ?? 'Login failed',
        );
      }

      throw Exception(
        'Unable to connect to the server. '
        'Make sure Django is running.',
      );
    }
  }

  // ─── Register ─────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> register({
    required String fullName,
    required String email,
    required String password,
    String phone = '',
    String preferredLanguage = 'en',
  }) async {
    try {
      final response = await _dio.post(
        '/auth/register/',
        data: {
          'full_name': fullName,
          'email': email,
          'password': password,
          if (phone.isNotEmpty) 'phone': phone,
          'preferred_language': preferredLanguage,
        },
      );

      return Map<String, dynamic>.from(response.data);
    } on DioException catch (e) {
      if (e.response != null) {
        final data = e.response?.data;

        // DRF field validation errors are a Map<field, List<String>>
        if (data is Map) {
          final messages = <String>[];
          data.forEach((key, value) {
            if (value is List) {
              messages.addAll(value.map((v) => v.toString()));
            } else {
              messages.add(value.toString());
            }
          });
          if (messages.isNotEmpty) {
            throw Exception(messages.join('\n'));
          }
        }

        throw Exception(
          e.response?.data?.toString() ?? 'Registration failed',
        );
      }

      throw Exception(
        'Unable to connect to the server. '
        'Make sure Django is running.',
      );
    }
  }

  // ─── Token refresh ────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> refreshAccessToken({
    required String refreshToken,
  }) async {
    try {
      final response = await _dio.post(
        '/auth/token/refresh/',
        data: {
          'refresh': refreshToken,
        },
      );

      return Map<String, dynamic>.from(response.data);
    } on DioException catch (e) {
      if (e.response != null) {
        throw Exception(
          e.response?.data?.toString() ??
              'Token refresh failed',
        );
      }

      throw Exception(
        'Unable to connect to the server.',
      );
    }
  }
}

// ─── Custom exceptions ────────────────────────────────────────────────────────

class PendingApprovalException implements Exception {
  final String message;
  const PendingApprovalException(this.message);

  @override
  String toString() => message;
}

class RegistrationRejectedException implements Exception {
  final String message;
  final String? rejectionReason;
  const RegistrationRejectedException(this.message, {this.rejectionReason});

  @override
  String toString() => message;
}