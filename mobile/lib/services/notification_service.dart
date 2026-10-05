import 'dart:async';

import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../providers/auth_provider.dart';

class NotificationService {
  static const String baseUrl =
      'http://127.0.0.1:8000/api';

  static const AndroidNotificationChannel notificationChannel =
  AndroidNotificationChannel(
    'community_issue_notifications',
    'Community Issue Notifications',
    description: 'Notifications for community issues.',
    importance: Importance.high,
  );

  final AuthProvider authProvider;

  static final FlutterLocalNotificationsPlugin _localNotifications =
  FlutterLocalNotificationsPlugin();

  // Callback used when a foreground local notification is tapped.
  static Future<void> Function(String issueId)?
  _onNotificationTap;

  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      headers: {
        'Accept': 'application/json',
      },
    ),
  );

  NotificationService({
    required this.authProvider,
  });

  // Connects notification taps to the app's navigation logic.
  static void setNotificationTapHandler(
      Future<void> Function(String issueId) handler,
      ) {
    _onNotificationTap = handler;
  }

  // Handles taps on foreground local notifications.
  static void _handleLocalNotificationTap(
      NotificationResponse response,
      ) {
    final issueId = response.payload;

    if (issueId == null || issueId.isEmpty) {
      debugPrint(
        'Local notification has no issue ID.',
      );
      return;
    }

    debugPrint(
      'Local notification tapped. Issue ID: $issueId',
    );

    final handler = _onNotificationTap;

    if (handler == null) {
      debugPrint(
        'Notification tap handler is not registered.',
      );
      return;
    }

    unawaited(
      handler(issueId),
    );
  }

  static Future<void> createNotificationChannel() async {
    const androidInitializationSettings =
    AndroidInitializationSettings('@mipmap/ic_launcher');

    const initializationSettings = InitializationSettings(
      android: androidInitializationSettings,
    );

    await _localNotifications.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse:
      _handleLocalNotificationTap,
    );

    final androidPlugin =
    _localNotifications
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    // Request Android 13+ notification permission.
    final permissionGranted =
    await androidPlugin?.requestNotificationsPermission();

    debugPrint(
      'Local notification permission: $permissionGranted',
    );

    await androidPlugin?.createNotificationChannel(
      notificationChannel,
    );

    debugPrint(
      'Notification channel created successfully.',
    );
  }

  Future<Response<dynamic>> _requestWithTokenRefresh({
    required Future<Response<dynamic>> Function(
        String accessToken,
        ) request,
  }) async {
    String? accessToken = authProvider.accessToken;

    if (accessToken == null || accessToken.isEmpty) {
      throw Exception(
        'You are not logged in.',
      );
    }

    try {
      return await request(accessToken);
    } on DioException catch (e) {
      if (e.response?.statusCode != 401) {
        rethrow;
      }

      debugPrint(
        'Notification request token expired. Refreshing...',
      );

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

  Future<List<Map<String, dynamic>>> getNotifications() async {
    try {
      final response =
      await _requestWithTokenRefresh(
        request: (token) {
          return _dio.get(
            '/notifications/',
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
            .map(
              (item) =>
          Map<String, dynamic>.from(item),
        )
            .toList();
      }

      if (data is Map && data['results'] is List) {
        return (data['results'] as List)
            .map(
              (item) =>
          Map<String, dynamic>.from(item),
        )
            .toList();
      }

      throw Exception(
        'Unexpected notification response.',
      );
    } on DioException catch (e) {
      debugPrint(
        'Loading notifications failed: '
            '${e.response?.data}',
      );

      if (e.response != null) {
        throw Exception(
          e.response?.data?.toString() ??
              'Failed to load notifications.',
        );
      }

      throw Exception(
        'Unable to connect to the server.',
      );
    }
  }

  Future<void> markAsRead(
      int notificationId,
      ) async {
    try {
      await _requestWithTokenRefresh(
        request: (token) {
          return _dio.patch(
            '/notifications/$notificationId/read/',
            options: Options(
              headers: {
                'Authorization': 'Bearer $token',
              },
            ),
          );
        },
      );
    } on DioException catch (e) {
      debugPrint(
        'Mark notification as read failed: '
            '${e.response?.data}',
      );

      if (e.response != null) {
        throw Exception(
          e.response?.data?.toString() ??
              'Failed to mark notification as read.',
        );
      }

      throw Exception(
        'Unable to connect to the server.',
      );
    }
  }

  Future<String?> getFcmToken() async {
    try {
      final token =
      await FirebaseMessaging.instance.getToken();

      debugPrint(
        'FCM TOKEN: $token',
      );

      return token;
    } catch (e) {
      debugPrint(
        'Failed to get FCM token: $e',
      );

      return null;
    }
  }

  Future<void> registerFcmToken() async {
    try {
      final fcmToken =
      await FirebaseMessaging.instance.getToken();

      if (fcmToken == null || fcmToken.isEmpty) {
        debugPrint(
          'FCM token is unavailable.',
        );
        return;
      }

      await _requestWithTokenRefresh(
        request: (accessToken) {
          return _dio.post(
            '/notifications/device-token/',
            data: {
              'fcm_token': fcmToken,
            },
            options: Options(
              headers: {
                'Authorization':
                'Bearer $accessToken',
                'Content-Type':
                'application/json',
              },
            ),
          );
        },
      );

      debugPrint(
        'FCM token registered successfully.',
      );
    } on DioException catch (e) {
      debugPrint(
        'FCM token registration failed: '
            '${e.response?.data}',
      );
    } catch (e) {
      debugPrint(
        'FCM token registration error: $e',
      );
    }
  }

  Future<void> showForegroundNotification(
      RemoteMessage message,
      ) async {
    debugPrint(
      'Showing foreground local notification...',
    );

    final notification = message.notification;

    if (notification == null) {
      debugPrint(
        'No notification payload found.',
      );
      return;
    }

    const androidDetails =
    AndroidNotificationDetails(
      'community_issue_notifications',
      'Community Issue Notifications',
      channelDescription:
      'Notifications for community issues.',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      icon: '@mipmap/ic_launcher',
    );

    const notificationDetails =
    NotificationDetails(
      android: androidDetails,
    );

    await _localNotifications.show(
      id: notification.hashCode,
      title: notification.title,
      body: notification.body,
      notificationDetails: notificationDetails,

      // Pass the issue ID to the local notification.
      payload:
      message.data['issue_id']?.toString(),
    );

    debugPrint(
      'Foreground local notification show() completed.',
    );
  }
}