import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'core/api/api_client.dart';
import 'core/state/auth_repository.dart';
import 'core/state/business_repository.dart';
import 'core/state/catalog_repository.dart';
import 'core/state/customer_repository.dart';
import 'core/state/dashboard_repository.dart';
import 'core/state/logistics_repository.dart';
import 'core/state/theme_controller.dart';
import 'core/state/transaction_repository.dart';
import 'core/state/wallet_repository.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/reset_password_screen.dart';
import 'features/logistics/logistics_workspace_screen.dart';
import 'features/auth/signup_screen.dart';
import 'features/auth/verify_otp_screen.dart';
import 'features/home/home_shell_screen.dart';
import 'features/settings/settings_screen.dart';

const String _apiBaseUrlOverride = String.fromEnvironment('API_BASE_URL');

/// Backend base URL.
///
/// On the web the app talks to its own origin (`<origin>/api/v1`) and the host
/// proxies `/api` to the API, so one build works on any domain. Override for
/// devices, desktop or a local preview without editing code:
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.20:4000/api/v1
final String apiBaseUrl = _apiBaseUrlOverride.isNotEmpty
    ? _apiBaseUrlOverride
    : kIsWeb
        ? '${Uri.base.origin}/api/v1'
        : 'http://localhost:4000/api/v1';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BizinessApp());
}

class BizinessApp extends StatefulWidget {
  const BizinessApp({super.key, this.apiBaseUrlOverride});

  final String? apiBaseUrlOverride;

  @override
  State<BizinessApp> createState() => _BizinessAppState();
}

class _BizinessAppState extends State<BizinessApp> {
  late final ThemeController _theme = ThemeController();
  late final ApiClient _api = ApiClient(
    baseUrl: widget.apiBaseUrlOverride ?? apiBaseUrl,
  );
  late final AuthRepository _auth = AuthRepository(_api);

  // Business-scoped state. These all resolve their owner from the session on
  // every request, so signing out has to clear them rather than leave another
  // account's catalog in memory.
  late final BusinessRepository _business = BusinessRepository(_api, _auth);
  late final CatalogRepository _catalog = CatalogRepository(_api, _auth);
  late final CustomerRepository _customers = CustomerRepository(_api, _auth);
  late final TransactionRepository _transactions =
      TransactionRepository(_api, _auth);
  late final DashboardRepository _dashboard = DashboardRepository(_api, _auth);
  late final LogisticsRepository _logistics = LogisticsRepository(_api, _auth);
  late final WalletRepository _wallet = WalletRepository(_api, _auth);

  /// Repositories that cache data belonging to the signed-in owner.
  List<ChangeNotifier> get _scopedRepositories => [
        _business,
        _catalog,
        _customers,
        _transactions,
        _dashboard,
        _logistics,
        _wallet,
      ];

  bool _booting = true;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    for (final repository in _scopedRepositories) {
      repository.dispose();
    }
    _api.close();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    // Never strand the app on the splash: whatever happens while restoring the
    // cached theme and session, hand control to the root (sign-in) screen.
    try {
      await Future.wait([_theme.load(), _auth.restore()]);
    } finally {
      if (mounted) setState(() => _booting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _theme,
      builder: (context, _) {
        return MaterialApp(
          title: 'Biziness — Your Business, Simplified',
          debugShowCheckedModeBanner: false,
          themeMode: _theme.mode,
          theme: buildLightTheme(),
          darkTheme: buildDarkTheme(),
          home: _booting
              ? const _SplashScreen()
              : _Root(
                  auth: _auth,
                  theme: _theme,
                  business: _business,
                  catalog: _catalog,
                  customers: _customers,
                  transactions: _transactions,
                  dashboard: _dashboard,
                  logistics: _logistics,
                  wallet: _wallet,
                  onSignedOut: _clearScopedState,
                ),
        );
      },
    );
  }
  void _clearScopedState() {
    _business.reset();
    _catalog.reset();
    _customers.reset();
    _transactions.reset();
    _dashboard.reset();
    _logistics.requests = const [];
    _wallet.reset();
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Image.asset(
        'assets/images/logo.png',
        width: 76,
        height: 76,
        fit: BoxFit.cover,
      ),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root({
    required this.auth,
    required this.theme,
    required this.business,
    required this.catalog,
    required this.customers,
    required this.transactions,
    required this.dashboard,
    required this.logistics,
    required this.wallet,
    required this.onSignedOut,
  });

  final AuthRepository auth;
  final ThemeController theme;
  final BusinessRepository business;
  final CatalogRepository catalog;
  final CustomerRepository customers;
  final TransactionRepository transactions;
  final DashboardRepository dashboard;
  final LogisticsRepository logistics;
  final WalletRepository wallet;
  final VoidCallback onSignedOut;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: auth,
      builder: (context, _) {
        final user = auth.session?.user;
        if (user == null) {
          return LoginScreen(
            auth: auth,
            onSignedIn: (_) => onSignedOut(),
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

        // Logistics and rider workspaces are a later phase. Sending those roles
        // into the business shell asks `GET /business` a question the server
        // refuses for them, which used to strand the account on an error screen
        // with no way back. Give them a real screen with a way out instead.
        if (user.role != 'business') {
          return LogisticsWorkspaceScreen(
            user: user,
            logistics: logistics,
            wallet: wallet,
            onOpenSettings: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SettingsScreen(theme: theme, auth: auth, user: user),
                ),
              );
            },
          );
        }

        return HomeShellScreen(
          user: user,
          business: business,
          catalog: catalog,
          customers: customers,
          transactions: transactions,
          dashboard: dashboard,
          logistics: logistics,
          wallet: wallet,
          onSignOut: auth.signOut,
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
