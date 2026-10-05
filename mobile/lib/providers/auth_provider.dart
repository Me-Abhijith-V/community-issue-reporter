import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../services/auth_service.dart';
import '../services/notification_service.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();

  final FlutterSecureStorage _secureStorage =
  const FlutterSecureStorage();

  bool _isLoading = false;
  bool _isInitialized = false;
  bool _isAuthenticated = false;

  String? _accessToken;
  String? _refreshToken;

  bool get isLoading => _isLoading;
  bool get isInitialized => _isInitialized;
  bool get isAuthenticated => _isAuthenticated;

  String? get accessToken => _accessToken;
  String? get refreshToken => _refreshToken;

  Future<void> _saveToken({
    required String key,
    required String value,
  }) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();

      await prefs.setString(key, value);
    } else {
      await _secureStorage.write(
        key: key,
        value: value,
      );
    }
  }

  Future<String?> _getToken(String key) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();

      return prefs.getString(key);
    }

    return await _secureStorage.read(
      key: key,
    );
  }

  Future<void> _deleteToken(String key) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();

      await prefs.remove(key);
    } else {
      await _secureStorage.delete(
        key: key,
      );
    }
  }

  Future<bool> login({
    required String email,
    required String password,
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      final result = await _authService.login(
        email: email,
        password: password,
      );

      final access = result['access']?.toString();
      final refresh = result['refresh']?.toString();

      if (access == null || access.isEmpty) {
        throw Exception(
          'Access token was not returned by the server.',
        );
      }

      _accessToken = access;
      _refreshToken = refresh;

      await _saveToken(key: 'access_token', value: access);

      if (refresh != null && refresh.isNotEmpty) {
        await _saveToken(key: 'refresh_token', value: refresh);
      }

      _isAuthenticated = true;

      // Register FCM token for THIS user immediately after login.
      // Any previous user's token is overwritten on the backend
      // because the token is stored per-user via the authenticated endpoint.
      try {
        final notificationService = NotificationService(
          authProvider: this,
        );
        await notificationService.registerFcmToken();
      } catch (e) {
        debugPrint('FCM token registration failed after login: $e');
      }

      return true;
    } on PendingApprovalException {
      _isAuthenticated = false;
      rethrow; // Let LoginScreen catch it as typed exception
    } on RegistrationRejectedException {
      _isAuthenticated = false;
      rethrow;
    } catch (e) {
      _isAuthenticated = false;
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Call once after the app has initialised.
  /// Listens for Firebase token rotation and re-registers immediately.
  void listenForFcmTokenRefresh() {
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      if (!_isAuthenticated) return;
      debugPrint('FCM token refreshed — re-registering...');
      try {
        final notificationService = NotificationService(authProvider: this);
        await notificationService.registerFcmToken();
      } catch (e) {
        debugPrint('FCM refresh re-register failed: $e');
      }
    });
  }

  Future<bool> refreshAccessToken() async {
    final refresh = _refreshToken;

    if (refresh == null || refresh.isEmpty) {
      return false;
    }

    try {
      final result = await _authService.refreshAccessToken(
        refreshToken: refresh,
      );

      final newAccessToken =
      result['access']?.toString();

      if (newAccessToken == null ||
          newAccessToken.isEmpty) {
        return false;
      }

      _accessToken = newAccessToken;

      await _saveToken(
        key: 'access_token',
        value: newAccessToken,
      );

      _isAuthenticated = true;
      notifyListeners();

      debugPrint('Access token refreshed successfully.');

      return true;
    } catch (e) {
      debugPrint(
        'Access token refresh failed: $e',
      );

      await logout();

      return false;
    }
  }

  Future<void> loadStoredTokens() async {
    try {
      debugPrint('Checking for stored authentication tokens...');

      _accessToken = await _getToken('access_token');
      _refreshToken = await _getToken('refresh_token');

      if (_accessToken != null && _accessToken!.isNotEmpty) {
        _isAuthenticated = true;

        debugPrint('Stored access token found.');
      } else {
        _isAuthenticated = false;

        debugPrint('No stored access token found.');
      }
    } catch (e) {
      debugPrint(
        'Error loading stored tokens: $e',
      );

      _isAuthenticated = false;
    } finally {
      _isInitialized = true;

      notifyListeners();
    }
  }

  Future<void> logout() async {
    await _deleteToken('access_token');
    await _deleteToken('refresh_token');

    _accessToken = null;
    _refreshToken = null;

    _isAuthenticated = false;

    notifyListeners();
  }

}