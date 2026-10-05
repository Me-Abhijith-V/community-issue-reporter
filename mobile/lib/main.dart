import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/auth_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/issue/issue_detail_screen.dart';
import 'screens/main_shell.dart';
import 'services/issue_service.dart';
import 'services/notification_service.dart';

final GlobalKey<NavigatorState> navigatorKey =
GlobalKey<NavigatorState>();

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(
    RemoteMessage message,
    ) async {
  await Firebase.initializeApp();

  debugPrint(
    'Background FCM message received: ${message.messageId}',
  );
}

String? _pendingNotificationIssueId;

Future<void> openIssueFromNotification(
    String issueIdString,
    ) async {
  final issueId = int.tryParse(issueIdString);

  if (issueId == null) {
    debugPrint(
      'Invalid issue ID from notification: $issueIdString',
    );
    return;
  }

  final context = navigatorKey.currentContext;

  if (context == null) {
    debugPrint(
      'Navigation context is not available. '
          'Saving pending issue ID: $issueId',
    );

    _pendingNotificationIssueId = issueIdString;
    return;
  }

  final authProvider = context.read<AuthProvider>();

  if (!authProvider.isInitialized ||
      !authProvider.isAuthenticated) {
    debugPrint(
      'Authentication is not ready. '
          'Saving pending issue ID: $issueId',
    );

    _pendingNotificationIssueId = issueIdString;
    return;
  }

  await _openIssueDetails(issueId);
}

Future<void> _openIssueDetails(int issueId) async {
  final context = navigatorKey.currentContext;

  if (context == null) {
    debugPrint(
      'Navigation context is not available.',
    );

    _pendingNotificationIssueId = issueId.toString();
    return;
  }

  final authProvider = context.read<AuthProvider>();

  if (!authProvider.isAuthenticated) {
    debugPrint(
      'User is not authenticated. '
          'Saving pending issue ID: $issueId',
    );

    _pendingNotificationIssueId = issueId.toString();
    return;
  }

  try {
    debugPrint(
      'Opening issue details for issue ID: $issueId',
    );

    final issueService = IssueService(
      authProvider: authProvider,
    );

    final issue = await issueService.getIssueById(
      issueId: issueId,
    );

    final navigator = navigatorKey.currentState;

    if (navigator == null) {
      debugPrint(
        'Navigator is not available.',
      );

      _pendingNotificationIssueId = issueId.toString();
      return;
    }

    _pendingNotificationIssueId = null;

    navigator.push(
      MaterialPageRoute(
        builder: (_) => IssueDetailScreen(
          issue: issue,
        ),
      ),
    );

    debugPrint(
      'Issue details opened successfully.',
    );
  } catch (e) {
    debugPrint(
      'Failed to open issue from notification: $e',
    );
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();

  // Connect local notification taps to issue navigation.
  NotificationService.setNotificationTapHandler(
    openIssueFromNotification,
  );

  // Create the Android notification channel.
  await NotificationService.createNotificationChannel();

  // Register background FCM handler.
  FirebaseMessaging.onBackgroundMessage(
    _firebaseMessagingBackgroundHandler,
  );

  // Request notification permission.
  await FirebaseMessaging.instance.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );

  runApp(
    ChangeNotifierProvider(
      create: (_) => AuthProvider()..loadStoredTokens(),
      child: const CommunityIssueTrackerApp(),
    ),
  );
}

class CommunityIssueTrackerApp extends StatefulWidget {
  const CommunityIssueTrackerApp({super.key});

  @override
  State<CommunityIssueTrackerApp> createState() =>
      _CommunityIssueTrackerAppState();
}

class _CommunityIssueTrackerAppState
    extends State<CommunityIssueTrackerApp> {
  late final NotificationService _notificationService;

  @override
  void initState() {
    super.initState();

    final authProvider = context.read<AuthProvider>();

    authProvider.addListener(
      _checkPendingNotification,
    );

    _notificationService = NotificationService(
      authProvider: authProvider,
    );

    // Listen for FCM token rotation and re-register it for the current user.
    authProvider.listenForFcmTokenRefresh();

    // Foreground FCM notification.
    FirebaseMessaging.onMessage.listen(
          (RemoteMessage message) async {
        debugPrint(
          'Foreground FCM message received: ${message.messageId}',
        );

        debugPrint(
          'Notification title: ${message.notification?.title}',
        );

        debugPrint(
          'Notification body: ${message.notification?.body}',
        );

        await _notificationService
            .showForegroundNotification(
          message,
        );

        debugPrint(
          'showForegroundNotification() returned',
        );
      },
    );

    // Notification tapped while app is in background.
    FirebaseMessaging.onMessageOpenedApp.listen(
          (RemoteMessage message) async {
        await _handleNotificationMessage(
          message,
        );
      },
    );

    // Notification tapped while app was completely terminated.
    FirebaseMessaging.instance
        .getInitialMessage()
        .then(
          (RemoteMessage? message) async {
        if (message == null) {
          return;
        }

        debugPrint(
          'App opened from terminated notification.',
        );

        await _handleNotificationMessage(
          message,
        );
      },
    );
  }

  void _checkPendingNotification() {
    final issueIdString =
        _pendingNotificationIssueId;

    if (issueIdString == null) {
      return;
    }

    final issueId =
    int.tryParse(issueIdString);

    if (issueId == null) {
      _pendingNotificationIssueId = null;
      return;
    }

    final authProvider =
    context.read<AuthProvider>();

    if (!authProvider.isInitialized ||
        !authProvider.isAuthenticated) {
      return;
    }

    debugPrint(
      'Authentication ready. '
          'Opening pending notification issue: $issueId',
    );

    _pendingNotificationIssueId = null;

    Future.microtask(() {
      _openIssueDetails(issueId);
    });
  }

  Future<void> _handleNotificationMessage(
      RemoteMessage message,
      ) async {
    debugPrint(
      'Notification opened: ${message.messageId}',
    );

    final issueId =
    message.data['issue_id'];

    if (issueId == null) {
      debugPrint(
        'Notification does not contain issue_id.',
      );
      return;
    }

    await openIssueFromNotification(
      issueId.toString(),
    );
  }

  @override
  void dispose() {
    context
        .read<AuthProvider>()
        .removeListener(
      _checkPendingNotification,
    );

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Community Issue Tracker',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
        ),
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    if (!auth.isInitialized) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (auth.isAuthenticated) {
      return const MainShell();
    }

    return const LoginScreen();
  }
}