import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:community_issue_tracker/providers/auth_provider.dart';
import 'package:community_issue_tracker/screens/auth/login_screen.dart';
import 'package:community_issue_tracker/screens/auth/register_screen.dart';

void main() {
  testWidgets('LoginScreen Register tap test', (WidgetTester tester) async {
    final authProvider = AuthProvider();
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

    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);

    final registerButton = find.text("Don't have an account? Register");
    expect(registerButton, findsOneWidget);

    await tester.tap(registerButton);
    await tester.pumpAndSettle();

    expect(find.byType(RegisterScreen), findsOneWidget);
  });
}
