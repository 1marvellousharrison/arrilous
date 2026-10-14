import 'package:dee_app/core/api/api_client.dart';
import 'package:dee_app/features/auth/role_unavailable_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression: a logistics or rider account used to be dropped into the
/// business shell, which asked `GET /business` a question the server refuses
/// for those roles. The resulting error screen was the root route with no back
/// arrow and no sign-out. This screen replaces it and always offers a way out.
void main() {
  AuthUser user(String role) => AuthUser(
        id: 'user-1',
        fullName: 'Rider One',
        email: 'rider@example.com',
        role: role,
      );

  testWidgets('a logistics account can sign out from the back arrow', (tester) async {
    var signedOut = false;

    await tester.pumpWidget(
      MaterialApp(
        home: RoleUnavailableScreen(
          user: user('logistics_partner'),
          onSignOut: () async => signedOut = true,
        ),
      ),
    );

    expect(find.text('The Logistics Partner workspace is coming'), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(signedOut, isTrue);
  });

  testWidgets('a rider can sign out from the primary action', (tester) async {
    var signedOut = false;

    await tester.pumpWidget(
      MaterialApp(
        home: RoleUnavailableScreen(
          user: user('rider'),
          onSignOut: () async => signedOut = true,
        ),
      ),
    );

    expect(find.text('The Rider workspace is coming'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
    await tester.pumpAndSettle();

    expect(signedOut, isTrue);
  });
}
