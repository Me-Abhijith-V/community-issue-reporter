import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/status_update_model.dart';
import '../providers/auth_provider.dart';

class IssueService {
  static const String baseUrl =
      'http://127.0.0.1:8000/api';

  final AuthProvider authProvider;

  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      headers: {
        'Accept': 'application/json',
      },
    ),
  );

  IssueService({
    required this.authProvider,
  });

  // ============================================================
  // TOKEN REFRESH
  // ============================================================

  Future<Response<dynamic>> _requestWithTokenRefresh({
    required Future<Response<dynamic>> Function(
        String accessToken,
        ) request,
  }) async {
    String? accessToken = authProvider.accessToken;

    if (accessToken == null || accessToken.isEmpty) {
      throw Exception('You are not logged in.');
    }

    try {
      return await request(accessToken);
    } on DioException catch (e) {
      if (e.response?.statusCode != 401) {
        rethrow;
      }

      final refreshed =
      await authProvider.refreshAccessToken();

      if (!refreshed) {
        throw Exception(
          'Your session has expired. Please login again.',
        );
      }

      accessToken = authProvider.accessToken;

      if (accessToken == null || accessToken.isEmpty) {
        throw Exception(
          'Unable to get a new access token.',
        );
      }

      return await request(accessToken);
    }
  }

  // ============================================================
  // CREATE ISSUE
  // ============================================================

  Future<Map<String, dynamic>> createIssue({
    required String description,
    required File photo,
    required double latitude,
    required double longitude,
    required bool wasVoiceInput,
  }) async {
    try {
      final formData = FormData.fromMap({
        'original_description': description,
        'latitude': latitude.toString(),
        'longitude': longitude.toString(),
        'was_voice_input': wasVoiceInput.toString(),
        'photo': await MultipartFile.fromFile(
          photo.path,
          filename: photo.path.split(
            Platform.pathSeparator,
          ).last,
        ),
      });

      final response =
      await _requestWithTokenRefresh(
        request: (token) {
          return _dio.post(
            '/issues/',
            data: formData,
            options: Options(
              headers: {
                'Authorization': 'Bearer $token',
                'Content-Type': 'multipart/form-data',
              },
            ),
          );
        },
      );

      if (response.statusCode == 200 ||
          response.statusCode == 201) {
        if (response.data is Map) {
          return Map<String, dynamic>.from(
            response.data as Map,
          );
        }

        throw Exception(
          'Unexpected response from server.',
        );
      }

      throw Exception(
        'Unable to create issue.',
      );
    } on DioException catch (e) {
      debugPrint(
        'Create issue failed: ${e.response?.data}',
      );

      final data = e.response?.data;

      if (data is Map) {
        final detail =
            data['detail'] ??
                data['error'] ??
                data['message'];

        if (detail != null) {
          throw Exception(detail.toString());
        }

        final errors = data.entries
            .map(
              (entry) =>
          '${entry.key}: ${entry.value}',
        )
            .join('\n');

        if (errors.isNotEmpty) {
          throw Exception(errors);
        }
      }

      throw Exception(
        'Failed to submit issue. '
            'Please check your connection.',
      );
    }
  }

  // ============================================================
  // MY ISSUES
  // ============================================================

  Future<List<Map<String, dynamic>>> getMyIssues({
    required String accessToken,
  }) async {
    try {
      final response =
      await _requestWithTokenRefresh(
        request: (token) {
          return _dio.get(
            '/issues/',
            queryParameters: {
              'mine': 'true',
              'ordering': '-created_at',
            },
            options: Options(
              headers: {
                'Authorization': 'Bearer $token',
              },
            ),
          );
        },
      );

      return _extractList(response.data);
    } on DioException catch (e) {
      debugPrint(
        'Fetching my issues failed: '
            '${e.response?.data}',
      );

      _throwDioException(
        e,
        fallback: 'Failed to load your reports.',
      );
      rethrow;
    }
  }

  // ============================================================
  // ALL COMMUNITY ISSUES
  // ============================================================

  Future<List<Map<String, dynamic>>> getAllIssues({
    required String accessToken,
    String? category,
    String? status,
    String? ordering,
  }) async {
    try {
      final queryParameters = <String, dynamic>{};

      if (category != null &&
          category.isNotEmpty &&
          category != 'all') {
        queryParameters['category'] = category;
      }

      if (status != null &&
          status.isNotEmpty &&
          status != 'all') {
        queryParameters['status'] = status;
      }

      if (ordering != null && ordering.isNotEmpty) {
        queryParameters['ordering'] = ordering;
      }

      final response =
      await _requestWithTokenRefresh(
        request: (token) {
          return _dio.get(
            '/issues/',
            queryParameters: queryParameters,
            options: Options(
              headers: {
                'Authorization': 'Bearer $token',
              },
            ),
          );
        },
      );

      return _extractList(response.data);
    } on DioException catch (e) {
      debugPrint(
        'Fetching all issues failed: '
            '${e.response?.data}',
      );

      _throwDioException(
        e,
        fallback: 'Failed to load community issues.',
      );
      rethrow;
    }
  }

  // ============================================================
  // NEARBY ISSUES
  // ============================================================

  Future<List<Map<String, dynamic>>> getNearbyIssues({
    required double latitude,
    required double longitude,
    double radiusKm = 0.5,
  }) async {
    try {
      final response =
      await _requestWithTokenRefresh(
        request: (token) {
          return _dio.get(
            '/issues/',
            queryParameters: {
              'latitude': latitude,
              'longitude': longitude,
              'radius': radiusKm,
            },
            options: Options(
              headers: {
                'Authorization': 'Bearer $token',
              },
            ),
          );
        },
      );

      return _extractList(response.data);
    } on DioException catch (e) {
      debugPrint(
        'Fetching nearby issues failed: '
            '${e.response?.data}',
      );

      return [];
    } catch (e) {
      debugPrint(
        'Unexpected nearby issues error: $e',
      );

      return [];
    }
  }

  // ============================================================
  // CLASSIFY ISSUE (AI pre-submit analysis)
  // ============================================================

  /// Calls /issues/classify/ to get AI analysis before
  /// submitting. Returns category, severity, language,
  /// translation, and duplicate detection results.
  Future<Map<String, dynamic>> classifyIssue({
    required String description,
    double? nearbyLatitude,
    double? nearbyLongitude,
    double radiusKm = 0.5,
  }) async {
    try {
      // Fetch nearby issue IDs for duplicate detection
      List<int> nearbyIds = [];

      if (nearbyLatitude != null && nearbyLongitude != null) {
        try {
          final nearby = await getNearbyIssues(
            latitude: nearbyLatitude,
            longitude: nearbyLongitude,
            radiusKm: radiusKm,
          );
          nearbyIds = nearby
              .map((i) => int.tryParse(i['id']?.toString() ?? ''))
              .whereType<int>()
              .toList();
        } catch (_) {
          nearbyIds = [];
        }
      }

      final response =
      await _requestWithTokenRefresh(
        request: (token) {
          return _dio.post(
            '/issues/classify/',
            data: {
              'description': description,
              'nearby_issue_ids': nearbyIds,
            },
            options: Options(
              headers: {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
              },
            ),
          );
        },
      );

      if (response.data is Map) {
        return Map<String, dynamic>.from(
          response.data as Map,
        );
      }

      throw Exception(
        'Unexpected response from classify endpoint.',
      );
    } on DioException catch (e) {
      debugPrint(
        'Classify issue failed: ${e.response?.data}',
      );

      _throwDioException(
        e,
        fallback: 'AI classification failed.',
      );
      rethrow;
    }
  }

  // ============================================================
  // MAP ISSUES
  // ============================================================

  Future<List<Map<String, dynamic>>> getMapIssues() async {
    try {
      final response =
      await _requestWithTokenRefresh(
        request: (token) {
          return _dio.get(
            '/issues/map/',
            options: Options(
              headers: {
                'Authorization': 'Bearer $token',
              },
            ),
          );
        },
      );

      return _extractList(response.data);
    } on DioException catch (e) {
      debugPrint(
        'Fetching map issues failed: '
            '${e.response?.data}',
      );

      _throwDioException(
        e,
        fallback: 'Failed to load map issues.',
      );
      rethrow;
    }
  }

  // ============================================================
  // UPVOTE
  // ============================================================

  Future<Map<String, dynamic>> upvoteIssue({
    required int issueId,
  }) async {
    try {
      final response =
      await _requestWithTokenRefresh(
        request: (token) {
          return _dio.post(
            '/issues/$issueId/upvote/',
            options: Options(
              headers: {
                'Authorization': 'Bearer $token',
              },
            ),
          );
        },
      );

      if (response.data is Map) {
        return Map<String, dynamic>.from(
          response.data as Map,
        );
      }

      throw Exception(
        'Unexpected response from server.',
      );
    } on DioException catch (e) {
      debugPrint(
        'Upvote request failed: '
            '${e.response?.data}',
      );

      _throwDioException(
        e,
        fallback: 'Failed to update upvote.',
      );
      rethrow;
    }
  }

  // ============================================================
  // REMOVE UPVOTE
  // ============================================================

  Future<Map<String, dynamic>> removeUpvote({
    required int issueId,
  }) async {
    try {
      final response =
      await _requestWithTokenRefresh(
        request: (token) {
          return _dio.delete(
            '/issues/$issueId/upvote/',
            options: Options(
              headers: {
                'Authorization': 'Bearer $token',
              },
            ),
          );
        },
      );

      if (response.data is Map) {
        return Map<String, dynamic>.from(
          response.data as Map,
        );
      }

      throw Exception(
        'Unexpected response from server.',
      );
    } on DioException catch (e) {
      debugPrint(
        'Remove upvote failed: '
            '${e.response?.data}',
      );

      _throwDioException(
        e,
        fallback: 'Failed to remove upvote.',
      );
      rethrow;
    }
  }

  // ============================================================
  // UPVOTED ISSUES (issues this user has upvoted)
  // ============================================================

  Future<List<Map<String, dynamic>>> getUpvotedIssues() async {
    try {
      final response = await _requestWithTokenRefresh(
        request: (token) {
          return _dio.get(
            '/issues/',
            queryParameters: {
              'upvoted': 'true',
              'ordering': '-created_at',
            },
            options: Options(
              headers: {'Authorization': 'Bearer $token'},
            ),
          );
        },
      );
      return _extractList(response.data);
    } on DioException catch (e) {
      debugPrint('Fetching upvoted issues failed: ${e.response?.data}');
      _throwDioException(e, fallback: 'Failed to load upvoted issues.');
      rethrow;
    }
  }

  // ============================================================
  // GET SINGLE ISSUE
  // ============================================================

  Future<Map<String, dynamic>> getIssueById({
    required int issueId,
  }) async {
    try {
      final response =
      await _requestWithTokenRefresh(
        request: (token) {
          return _dio.get(
            '/issues/$issueId/',
            options: Options(
              headers: {
                'Authorization': 'Bearer $token',
              },
            ),
          );
        },
      );

      if (response.data is Map) {
        return Map<String, dynamic>.from(
          response.data as Map,
        );
      }

      throw Exception(
        'Unexpected response from server.',
      );
    } on DioException catch (e) {
      debugPrint(
        'Fetching issue $issueId failed: '
            '${e.response?.data}',
      );

      _throwDioException(
        e,
        fallback: 'Failed to load issue.',
      );
      rethrow;
    }
  }

  // ============================================================
  // STATUS HISTORY
  // ============================================================

  Future<List<StatusUpdateModel>> getStatusHistory({
    required int issueId,
  }) async {
    try {
      final response =
      await _requestWithTokenRefresh(
        request: (token) {
          return _dio.get(
            '/issues/$issueId/status-history/',
            options: Options(
              headers: {
                'Authorization': 'Bearer $token',
              },
            ),
          );
        },
      );

      final data = response.data;

      if (data is List) {
        return data
            .whereType<Map>()
            .map(
              (item) => StatusUpdateModel.fromJson(
            Map<String, dynamic>.from(item),
          ),
        )
            .toList();
      }

      if (data is Map &&
          data['results'] is List) {
        return (data['results'] as List)
            .whereType<Map>()
            .map(
              (item) => StatusUpdateModel.fromJson(
            Map<String, dynamic>.from(item),
          ),
        )
            .toList();
      }

      throw Exception(
        'Unexpected response from server.',
      );
    } on DioException catch (e) {
      debugPrint(
        'Fetching status history failed: '
            '${e.response?.data}',
      );

      _throwDioException(
        e,
        fallback: 'Failed to load status history.',
      );
      rethrow;
    }
  }

  // ============================================================
  // EXTRACT LIST
  // ============================================================

  List<Map<String, dynamic>> _extractList(
      dynamic data,
      ) {
    if (data is List) {
      return data
          .whereType<Map>()
          .map(
            (item) => Map<String, dynamic>.from(item),
      )
          .toList();
    }

    if (data is Map &&
        data['results'] is List) {
      return (data['results'] as List)
          .whereType<Map>()
          .map(
            (item) => Map<String, dynamic>.from(item),
      )
          .toList();
    }

    throw Exception(
      'Unexpected response from server.',
    );
  }

  // ============================================================
  // COMMON DIO ERROR HANDLER
  // ============================================================

  Never _throwDioException(
      DioException e, {
        required String fallback,
      }) {
    if (e.response != null) {
      final data = e.response?.data;

      if (data is Map) {
        final detail =
            data['detail'] ??
                data['error'] ??
                data['message'];

        if (detail != null) {
          throw Exception(detail.toString());
        }

        final errors = data.entries
            .map(
              (entry) =>
          '${entry.key}: ${entry.value}',
        )
            .join('\n');

        if (errors.isNotEmpty) {
          throw Exception(errors);
        }
      }

      throw Exception(
        data?.toString() ?? fallback,
      );
    }

    throw Exception(
      'Unable to connect to the server. '
          'Make sure Django is running.',
    );
  }
}