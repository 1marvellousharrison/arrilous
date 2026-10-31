import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/state/business_repository.dart';
import '../../core/state/catalog_repository.dart';
import '../../core/state/customer_repository.dart';
import '../../core/state/dashboard_repository.dart';
import '../../core/state/logistics_repository.dart';
import '../../core/state/staff_repository.dart';
import '../../core/state/transaction_repository.dart';
import '../../core/state/wallet_repository.dart';
import '../../core/state/ai_repository.dart';
import '../../core/state/app_notifications_repository.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/common.dart';
import '../business/business_edit_gate.dart';
import '../business/business_setup_flow.dart';
import '../customers/customer_form_screen.dart';
import '../customers/customers_screen.dart';
import '../products/product_form_screen.dart';
import '../products/products_screen.dart';
import '../staff/staff_screen.dart';
import '../transactions/new_transaction_screen.dart';
import '../transactions/transaction_detail_screen.dart';
import '../transactions/transactions_screen.dart';
import '../logistics/business_logistics_screen.dart';
import '../logistics/delivery_requests_list_screen.dart';
import '../logistics/notifications_screen.dart';
import 'ai_chat_screen.dart';
import 'app_notifications_screen.dart';
import '../wallet/wallet_screen.dart';
import 'dashboard_screen.dart';

/// The authenticated shell for a business account.
///
/// Tabs are Home | Transactions | AI/Chats | Logistics | Profile. An owner
/// without a business is held at setup rather than shown an empty app: every
/// operational view needs a business behind it.
///
/// The same shell serves a staff member, restricted to their slice of it: they
/// see only their own sales, may annotate but never move a sale, get a
/// read-only catalog and add-only customers, and cannot reach the wallet,
/// business details or staff management.
class HomeShellScreen extends StatefulWidget {
  const HomeShellScreen({
    required this.user,
    required this.business,
    required this.catalog,
    required this.customers,
    required this.transactions,
    required this.dashboard,
    required this.logistics,
    required this.wallet,
    required this.staff,
    required this.ai,
    required this.appNotifications,
    required this.onOpenSettings,
    required this.onSignOut,
    super.key,
  });

  final AuthUser user;
  final BusinessRepository business;
  final CatalogRepository catalog;
  final CustomerRepository customers;
  final TransactionRepository transactions;
  final DashboardRepository dashboard;
  final LogisticsRepository logistics;
  final WalletRepository wallet;
  final StaffRepository staff;
  final AiRepository ai;
  final AppNotificationsRepository appNotifications;
  final VoidCallback onOpenSettings;
  final Future<void> Function() onSignOut;

  @override
  State<HomeShellScreen> createState() => _HomeShellScreenState();
}

class _HomeShellScreenState extends State<HomeShellScreen> {
  int _index = 0;

  bool get _isStaff => widget.user.role == 'staff';

  // Login or refresh is the only moment the incomplete-details prompt appears
  // on its own. Recording a sale asks again regardless of this flag, because
  // those details are exactly what the delivery partner needs on the job.
  bool _promptedForDetails = false;

  // Set the moment a sale is stopped for missing details, so the launch prompt
  // does not ask the same question a second time right after it.
  bool _salePrompted = false;

  @override
  void initState() {
    super.initState();
    widget.business.load().whenComplete(() {
      if (mounted) _maybePromptForDetails();
    });
  }

  /// Spec — a refresh or a sign-in surfaces the details the logistics side
  /// depends on (contact number, city, area, state) before the owner gets
  /// comfortable. Once per launch, and never for an owner who has them.
  Future<void> _maybePromptForDetails() async {
    if (_promptedForDetails) return;
    // Business contact and location are the owner's to fill in and only the
    // owner may edit them, so a staff member is never nudged towards a form the
    // server would refuse.
    if (_isStaff) return;
    final business = widget.business;
    if (!business.isReady || business.needsSetup || !business.needsLogisticsDetails) {
      return;
    }
    _promptedForDetails = true;
    // The refresh prompt waits a couple of seconds, so the owner lands on the
    // page before being asked; a sale, by contrast, is asked the instant it is
    // started — that question stands in front of the job.
    await Future<void>.delayed(const Duration(seconds: 2));
    if (!mounted || _salePrompted) return;
    if (business.needsSetup || !business.needsLogisticsDetails) return;
    final open = await _promptForDetails();
    if (open == true && mounted) await _openBusinessDetails();
  }

  Future<bool?> _promptForDetails() => showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Complete your business details'),
          content: const Text(
            'Your business contact and your location (city, area, state) are '
            'shown to the delivery partner and the rider on every transaction. '
            'Add them now so nobody has to guess how to reach your shop.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Later'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Open business details'),
            ),
          ],
        ),
      );

  /// The gate before any sale: an owner missing these details is sent to
  /// business details instead of the sale form, and the sale waits.
  Future<bool> _ensureDetailsBeforeSale() async {
    if (_isStaff) return true;
    if (!widget.business.needsLogisticsDetails) return true;
    _salePrompted = true;
    final open = await _promptForDetails();
    if (open == true && mounted) await _openBusinessDetails();
    return false;
  }

  /// Opens the business-details editor. Editing an existing profile is the
  /// shop's identity, so it goes through the owner-confirmation gate first; the
  /// very first setup (no profile yet) is not a change and opens directly.
  Future<void> _openBusinessDetails() async {
    String? editToken;
    if (widget.business.hasProfile) {
      editToken = await Navigator.of(context).push<String>(
        MaterialPageRoute<String>(
          builder: (_) => BusinessEditGate(business: widget.business),
        ),
      );
      if (!mounted || editToken == null) return;
    }
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => BusinessSetupFlow(
          business: widget.business,
          editToken: editToken,
          onComplete: widget.business.load,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.business,
      builder: (context, _) {
        final business = widget.business;

        // Checked before `needsSetup`, and independently of `isReady`: a load
        // that finished with a 403 still sets isReady, so gating the error on
        // `!isReady` would let a forbidden account fall through into setup and
        // be asked to create a business it is not allowed to own.
        if (business.error != null && !business.hasProfile) {
          return _SetupFailed(
            message: business.error!,
            onRetry: business.load,
            onSignOut: widget.onSignOut,
          );
        }

        if (!business.isReady) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (business.needsSetup) {
          return BusinessSetupFlow(
            business: business,
            onComplete: business.load,
          );
        }

        final ownerName = business.business?.displayName ?? '';

        return Scaffold(
          appBar: AppBar(
            // The Profile tab is the shop's own page: the bar leads with the
            // tab name where the business name sits elsewhere, and the business
            // (storefront) icon moves here — Settings is already a row in the
            // profile list, so its gear would be a duplicate. On the other tabs
            // the storefront's slot is taken by the wallet, so money is always
            // one tap away for the owner.
            title: _index == 4
                ? const Text('Profile')
                : Text(ownerName.isEmpty ? 'Biziness' : ownerName),
            actions: _index == 4
                ? [
                    if (_isStaff)
                      IconButton(
                        tooltip: 'Settings',
                        onPressed: widget.onOpenSettings,
                        icon: const Icon(Icons.settings_outlined),
                      )
                    else
                      IconButton(
                        tooltip: 'Business details',
                        onPressed: _openBusinessDetails,
                        icon: const Icon(Icons.storefront_outlined),
                      ),
                  ]
                : [
                    if (!_isStaff)
                      IconButton(
                        tooltip: 'Wallet',
                        onPressed: _openWallet,
                        icon: const Icon(Icons.account_balance_wallet_outlined),
                      ),
                    IconButton(
                      tooltip: 'Settings',
                      onPressed: widget.onOpenSettings,
                      icon: const Icon(Icons.settings_outlined),
                    ),
                  ],
          ),
          body: _tabs(),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: _onTab,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.receipt_long_outlined),
                selectedIcon: Icon(Icons.receipt_long),
                label: 'Sales',
              ),
              NavigationDestination(
                icon: Icon(Icons.auto_awesome_outlined),
                selectedIcon: Icon(Icons.auto_awesome),
                label: 'AI / Chats',
              ),
              NavigationDestination(
                icon: Icon(Icons.local_shipping_outlined),
                selectedIcon: Icon(Icons.local_shipping),
                label: 'Logistics',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: 'Profile',
              ),
            ],
          ),
        );
      },
    );
  }

  /// Each tab loads on entry so it always shows data matching the server rather
  /// than a snapshot taken at sign-in. The initial tab is loaded here too, since
  /// `onDestinationSelected` does not fire for the tab the shell opens on.
  void _onTab(int index) {
    setState(() => _index = index);
    switch (index) {
      case 0:
        widget.dashboard.load();
      case 1:
        widget.transactions.load();
      case 3:
        widget.logistics.load();
    }
  }

  Widget _tabs() {
    return switch (_index) {
      0 => DashboardScreen(
          dashboard: widget.dashboard,
          business: widget.business,
          transactions: widget.transactions,
          catalog: widget.catalog,
          customers: widget.customers,
          onOpenTransaction: _openTransaction,
          onManualEntry: _manualTransaction,
          onSeeAllTransactions: () => _onTab(1),
          onAddProduct: _addProduct,
          onAddCustomer: _addCustomer,
          canAddProduct: !_isStaff,
        ),
      1 => TransactionsScreen(
          transactions: widget.transactions,
          onOpen: _openTransaction,
          onCreate: _newTransaction,
        ),
      2 => AiChatScreen(ai: widget.ai, catalog: widget.catalog, customers: widget.customers),
      3 => BusinessLogisticsScreen(business: widget.business, transactions: widget.transactions, logistics: widget.logistics),
      _ => _ProfileScreen(
          onOpenSettings: widget.onOpenSettings,
          onProducts: _openProducts,
          onCustomers: _openCustomers,
          onStaff: _openStaff,
          business: widget.business,
          logistics: widget.logistics,
          isStaff: _isStaff,
        ),
    };
  }

  Future<void> _openWallet() => Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => WalletScreen(wallet: widget.wallet),
        ),
      );

  /// Spec 6 — `+ New Transaction` offers three entry methods over one engine.
  /// Only manual entry runs today; the other two are visible and inert.
  Future<void> _newTransaction() async {
    if (!await _ensureDetailsBeforeSale()) return;
    if (!mounted) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm),
              child: Text(
                'New transaction',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit_note),
              title: const Text('Manual Entry'),
              subtitle: const Text('Available'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pop(context, 'manual'),
            ),
            ListTile(
              leading: Icon(Icons.chat_bubble_outline, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4)),
              enabled: false,
              title: const Text('WhatsApp AI'),
              subtitle: const Text('Coming soon'),
              trailing: const Icon(Icons.lock_outline),
            ),
            ListTile(
              leading: Icon(Icons.photo_camera_outlined, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4)),
              enabled: false,
              title: const Text('Screenshot / Photo'),
              subtitle: const Text('Coming soon'),
              trailing: const Icon(Icons.lock_outline),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
    if (choice == 'manual') await _manualTransaction();
  }

  Future<void> _manualTransaction() async {
    if (!await _ensureDetailsBeforeSale()) return;
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => NewTransactionScreen(
          transactions: widget.transactions,
          catalog: widget.catalog,
          customers: widget.customers,
          onCreated: _openTransaction,
        ),
      ),
    );
    // The dashboard figures are aggregates over every sale, so they are stale
    // the moment one is recorded.
    if (mounted) widget.dashboard.load();
  }

  void _openTransaction(Transaction transaction) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => TransactionDetailScreen(
          transactions: widget.transactions,
          transactionId: transaction.id,
          canChangeStatus: !_isStaff,
        ),
      ),
    );
  }

  Future<void> _addCustomer() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => CustomerFormScreen(customers: widget.customers),
      ),
    );
  }

  Future<void> _addProduct() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ProductFormScreen(catalog: widget.catalog),
      ),
    );
  }

  Future<void> _openProducts() => Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => ProductsScreen(
        catalog: widget.catalog,
        businessName: widget.business.business?.displayName ?? '',
        readOnly: _isStaff,
      ),
    ),
  );

  Future<void> _openCustomers() => Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => CustomersScreen(
        customers: widget.customers,
        canEdit: !_isStaff,
      ),
    ),
  );

  Future<void> _openStaff() => Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => StaffScreen(staff: widget.staff),
    ),
  );
}

class _ComingSoonScreen extends StatelessWidget {
  const _ComingSoonScreen();

  @override
  Widget build(BuildContext context) => const Center(
    child: EmptyState(
      icon: Icons.auto_awesome_outlined,
      title: 'AI order creation is coming soon',
      message: 'WhatsApp and screenshot orders will become drafts for your review before they can be confirmed.',
    ),
  );
}

/// The Profile tab: the shop's own details first, then the two doorways into
/// the busiest lists — Notifications and Delivery requests — and Settings
/// last. Each doorway opens the whole list on its own page, so nothing is
/// sampled away, and the header keeps the coordinates off the page.
class _ProfileScreen extends StatefulWidget {
  const _ProfileScreen({
    required this.onOpenSettings,
    required this.onProducts,
    required this.onCustomers,
    required this.onStaff,
    required this.business,
    required this.logistics,
    required this.isStaff,
  });

  final VoidCallback onOpenSettings;
  final Future<void> Function() onProducts;
  final Future<void> Function() onCustomers;
  final Future<void> Function() onStaff;
  final BusinessRepository business;
  final LogisticsRepository logistics;
  final bool isStaff;

  @override
  State<_ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<_ProfileScreen> {
  @override
  void initState() {
    super.initState();
    widget.logistics.loadNotifications();
    widget.logistics.load();
  }

  Future<void> _openNotifications() => Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => NotificationsScreen(logistics: widget.logistics),
        ),
      );

  Future<void> _openAllRequests() => Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => DeliveryRequestsListScreen(
            title: 'Delivery requests',
            statuses: allDeliveryRequestStatuses,
            logistics: widget.logistics,
            role: 'business',
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final logistics = widget.logistics;
    return ListenableBuilder(
      listenable: Listenable.merge([logistics, widget.business]),
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          _businessHeader(widget.business.business),
          const SizedBox(height: AppSpacing.lg),
          ListTile(
            leading: const Icon(Icons.notifications_none),
            title: const Text('Notifications'),
            subtitle: Text(logistics.unreadCount > 0 ? '${logistics.unreadCount} unread' : 'Delivery request activity'),
            onTap: _openNotifications,
          ),
          ListTile(leading: const Icon(Icons.inventory_2_outlined), title: const Text('Products'), subtitle: const Text('Catalog, prices and stock'), onTap: widget.onProducts),
          ListTile(leading: const Icon(Icons.people_outline), title: const Text('Customers'), subtitle: const Text('Customer records and history'), onTap: widget.onCustomers),
          if (!widget.isStaff)
            ListTile(leading: const Icon(Icons.group_outlined), title: const Text('Staff'), subtitle: const Text('Add staff and hand out their codes'), onTap: widget.onStaff),
          ListTile(
            leading: const Icon(Icons.local_shipping_outlined),
            title: const Text('Delivery requests'),
            subtitle: Text(logistics.requests.isEmpty ? 'Track each delivery' : '${logistics.requests.length} total'),
            onTap: _openAllRequests,
          ),
          const SizedBox(height: AppSpacing.lg),
          ListTile(leading: const Icon(Icons.settings_outlined), title: const Text('Settings'), onTap: widget.onOpenSettings),
        ],
      ),
    );
  }

  /// The shop's own details as a soft identity card: a tinted monogram header
  /// over an icon-led list of contact facts. The coordinates the dashboard
  /// shows are deliberately left off — the owner reads the page, not a map.
  Widget _businessHeader(BusinessProfile? profile) {
    final theme = Theme.of(context);
    final displayName = profile?.displayName ?? '';
    final title = displayName.isEmpty ? 'Your business' : displayName;
    final category = profile?.businessCategory?.trim();
    final location = profile?.location;

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.lg),
            color: theme.colorScheme.primary.withValues(alpha: 0.10),
            child: Row(
              children: [
                BusinessLogoAvatar(
                  logoUrl: profile?.logoUrl,
                  name: title,
                  size: 54,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                      if (category != null && category.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          category,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _identityRow(Icons.call_outlined, 'Phone', profile?.phone, spaced: true),
                _identityRow(Icons.place_outlined, 'Location', location?.oneLine, spaced: true),
                _identityRow(Icons.mail_outline, 'Email', profile?.email, spaced: false),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// One labelled fact on the identity card. A missing value is simply left
  /// out, so the card never shows a label with nothing behind it.
  Widget _identityRow(IconData icon, String label, String? value, {required bool spaced}) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: spaced ? AppSpacing.md : 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
                const SizedBox(height: 1),
                Text(text, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SetupFailed extends StatelessWidget {
  const _SetupFailed({
    required this.message,
    required this.onRetry,
    required this.onSignOut,
  });

  final String message;
  final VoidCallback onRetry;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // `Try again` alone made this a dead end: the shell is the root route,
        // so there was no back arrow and no way to sign out of a business that
        // could not be reached.
        leading: BackButton(onPressed: onSignOut),
        title: const Text('Biziness'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            onPressed: onSignOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          const SizedBox(height: AppSpacing.xxl),
          EmptyState(
            icon: Icons.cloud_off_outlined,
            title: 'Cannot reach your business yet',
            message: message,
            action: FilledButton(onPressed: onRetry, child: const Text('Try again')),
          ),
        ],
      ),
    );
  }
}
