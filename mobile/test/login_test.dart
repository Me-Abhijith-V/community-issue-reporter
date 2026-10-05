import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:community_issue_tracker/providers/auth_provider.dart';
import 'package:community_issue_tracker/screens/auth/login_screen.dart';
import 'package:community_issue_tracker/screens/auth/register_screen.dart';
import 'package:community_issue_tracker/main.dart';

void main() {
  testWidgets('LoginScreen Register tap test', (WidgetTester tester) async {
    final authProvider = AuthProvider();
    // Use reflection or just test LoginScreen directly to avoid AuthGate's loading spinner
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: authProvider),
        ],
        child: const MaterialApp(
          home: LoginScreen(),
        ),
      ),
    );

    // Wait for the widgets to render
    await tester.pumpAndSettle();

    // Verify LoginScreen is displayed
    expect(find.byType(LoginScreen), findsOneWidget);

    // Find the text for Register
    final registerButton = find.text("Don't have an account? Register");
    expect(registerButton, findsOneWidget);

    // Tap the register button
    print('TAPPING BUTTON...');
    await tester.tap(registerButton);
    await tester.pumpAndSettle();

    // See if RegisterScreen is shown
    final registerScreen = find.byType(RegisterScreen);
    print('RegisterScreen found: \${registerScreen.evaluate().length}');
  });
}
