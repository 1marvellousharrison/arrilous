import 'package:flutter/material.dart';

import 'core/api/api_client.dart';
import 'core/state/auth_repository.dart';
import 'core/state/theme_controller.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/reset_password_screen.dart';
import 'features/auth/signup_screen.dart';
import 'features/auth/verify_otp_screen.dart';
import 'features/home/home_shell_screen.dart';
import 'features/settings/settings_screen.dart';

/// Backend base URL.
///
/// Override per environment without editing code:
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.20:4000/api/v1
const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:4000/api/v1',
);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BusinessHubApp());
}

class BusinessHubApp extends StatefulWidget {
  const BusinessHubApp({super.key, this.apiBaseUrlOverride});

  final String? apiBaseUrlOverride;

  @override
  State<BusinessHubApp> createState() => _BusinessHubAppState();
}

class _BusinessHubAppState extends State<BusinessHubApp> {
  late final ThemeController _theme = ThemeController();
  late final ApiClient _api = ApiClient(
    baseUrl: widget.apiBaseUrlOverride ?? apiBaseUrl,
  );
  late final AuthRepository _auth = AuthRepository(_api);

  bool _booting = true;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await Future.wait([_theme.load(), _auth.restore()]);
    if (mounted) setState(() => _booting = false);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _theme,
      builder: (context, _) {
        return MaterialApp(
          title: 'Business Hub',
          debugShowCheckedModeBanner: false,
          themeMode: _theme.mode,
          theme: buildLightTheme(),
          darkTheme: buildDarkTheme(),
          home: _booting ? const _SplashScreen() : _Root(auth: _auth, theme: _theme),
        );
      },
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Logo(),
            SizedBox(height: AppSpacing.xl),
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.orangeRed, AppColors.orangeRedDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: const Icon(Icons.storefront, color: Colors.white, size: 38),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root({required this.auth, required this.theme});

  final AuthRepository auth;
  final ThemeController theme;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: auth,
      builder: (context, _) {
        final user = auth.session?.user;
        if (user == null) {
          return LoginScreen(
            auth: auth,
            onSignedIn: (_) {},
            onCreateAccount: () => _openSignUp(context),
            onForgotPassword: (identifier) => _startPasswordReset(
              context,
              identifier: identifier,
            ),
            onUseCode: (identifier) => _startOtp(
              context,
              identifier: identifier,
              purpose: 'login_verification',
            ),
          );
        }

        return HomeShellScreen(
          user: user,
          onOpenSettings: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    SettingsScreen(theme: theme, auth: auth, user: user),
              ),
            );
          },
        );
      },
    );
  }

  void _openSignUp(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SignUpFlow(
          auth: auth,
          onBack: () => Navigator.of(context).pop(),
          onSignedIn: (_) {},
        ),
      ),
    );
  }

  Future<void> _startPasswordReset(
    BuildContext context, {
    required String identifier,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final changed = await navigator.push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ResetPasswordScreen(
          auth: auth,
          initialIdentifier: identifier,
        ),
      ),
    );

    if (changed == true) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Password updated. Sign in with your new password.'),
        ),
      );
    }
  }

  Future<void> _startOtp(
    BuildContext context, {
    required String identifier,
    required String purpose,
  }) async {
    final trimmed = identifier.trim();
    if (trimmed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your email or phone number first.')),
      );
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      final challenge = await auth.requestOtp(
        identifier: trimmed,
        purpose: purpose,
      );
      if (challenge == null) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'If an account exists for $trimmed, we sent a 6-digit code.',
            ),
          ),
        );
        return;
      }
      await navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => VerifyOtpScreen(
            auth: auth,
            challenge: challenge,
            onBack: () => navigator.pop(),
            // The root already rebuilds through AuthRepository's ChangeNotifier.
            onSignedIn: (_) => navigator.popUntil((route) => route.isFirst),
          ),
        ),
      );
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } on NetworkException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}
