import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/state/wallet_repository.dart';
import '../../core/theme/app_theme.dart';
import '../../core/api/wallet_models.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({
    required this.wallet,
    super.key,
  });

  final WalletRepository wallet;

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  @override
  void initState() {
    super.initState();
    widget.wallet.load();
    widget.wallet.loadBanks();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Wallet')),
      body: AnimatedBuilder(
        animation: widget.wallet,
        builder: (context, _) {
          final wallet = widget.wallet.wallet;
          final txns = widget.wallet.transactions;
          if (widget.wallet.loading && wallet == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              _BalanceCard(wallet: wallet),
              const SizedBox(height: AppSpacing.lg),
              _VirtualAccountCard(wallet: wallet, repo: widget.wallet),
              const SizedBox(height: AppSpacing.lg),
              _AddMoneyCard(repo: widget.wallet),
              const SizedBox(height: AppSpacing.lg),
              _SendMoneyCard(repo: widget.wallet, banks: widget.wallet.banks),
              const SizedBox(height: AppSpacing.lg),
              Text('Recent transactions', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              if (txns.isEmpty)
                const Text('No transactions yet.')
              else
                ...txns.take(10).map((t) => _TxnTile(t)),
            ],
          );
        },
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({this.wallet});

  final Wallet? wallet;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.card),
        gradient: const LinearGradient(
          colors: [AppColors.orangeRed, AppColors.orangeRedDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Wallet balance', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white)),
          const SizedBox(height: AppSpacing.sm),
          Text(
            wallet != null ? wallet!.balanceNaira : '₦0.00',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _VirtualAccountCard extends StatefulWidget {
  const _VirtualAccountCard({this.wallet, required this.repo});

  final Wallet? wallet;
  final WalletRepository repo;

  @override
  State<_VirtualAccountCard> createState() => _VirtualAccountCardState();
}

class _VirtualAccountCardState extends State<_VirtualAccountCard> {
  bool _loading = false;

  Future<void> _generate() async {
    setState(() => _loading = true);
    try {
      await widget.repo.fundVirtualAccount();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Virtual account generated.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.wallet;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Dedicated virtual account', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            if (w?.virtualAccountNumber != null && w!.virtualAccountNumber!.isNotEmpty) ...[
              _Row('Bank', w.virtualAccountBank ?? ''),
              _Row('Account number', w.virtualAccountNumber!, onCopy: () => _copy(w.virtualAccountNumber!)),
              _Row('Account name', w.virtualAccountName ?? ''),
            ] else ...[
              const Text('No virtual account yet. Generate one to receive transfers.'),
              const SizedBox(height: AppSpacing.sm),
              FilledButton(onPressed: _loading ? null : _generate, child: Text(_loading ? 'Generating...' : 'Generate virtual account')),
            ],
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.onCopy});

  final String label;
  final String value;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text('$label: $value')),
          if (onCopy != null) TextButton(onPressed: onCopy, child: const Text('Copy')),
        ],
      ),
    );
  }
}

class _AddMoneyCard extends StatefulWidget {
  const _AddMoneyCard({required this.repo});

  final WalletRepository repo;

  @override
  State<_AddMoneyCard> createState() => _AddMoneyCardState();
}

class _AddMoneyCardState extends State<_AddMoneyCard> {
  final _amount = TextEditingController();
  final _card = TextEditingController();
  bool _loading = false;

  Future<void> _pay() async {
    final amt = parseKobo(_amount.text);
    if (amt <= 0) return;
    final card = _card.text.replaceAll(' ', '');
    if (card.length < 12) return;
    setState(() => _loading = true);
    try {
      await widget.repo.fundCard(amountKobo: amt, cardNumber: card);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Added successfully')));
        _amount.clear();
        _card.clear();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add money (card)', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(controller: _amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Amount (₦)')),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(controller: _card, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Card number')),
            const SizedBox(height: AppSpacing.sm),
            FilledButton(onPressed: _loading ? null : _pay, child: Text(_loading ? 'Processing...' : 'Pay')),
          ],
        ),
      ),
    );
  }
}

class _SendMoneyCard extends StatefulWidget {
  const _SendMoneyCard({required this.repo, required this.banks});

  final WalletRepository repo;
  final List<Bank> banks;

  @override
  State<_SendMoneyCard> createState() => _SendMoneyCardState();
}

class _SendMoneyCardState extends State<_SendMoneyCard> {
  final _amount = TextEditingController();
  final _acct = TextEditingController();
  final _name = TextEditingController();
  String? _bankCode;
  String? _otp;
  bool _loading = false;
  bool _pending = false;

  Future<void> _initiate() async {
    final amt = parseKobo(_amount.text);
    if (amt <= 0 || _bankCode == null) return;
    if (_acct.text.trim().length != 10) return;
    setState(() => _loading = true);
    try {
      final res = await widget.repo.initiatePayout(amountKobo: amt, bankCode: _bankCode!, accountNumber: _acct.text.trim(), accountName: _name.text.trim());
        setState(() {
          _pending = true;
          _otp = res['otp'] as String?;
        });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter the code to confirm')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirm() async {
    if (_otp == null || _otp!.isEmpty) return;
    setState(() => _loading = true);
    try {
      await widget.repo.confirmPayout(otp: _otp!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payout successful')));
        setState(() => _pending = false);
        _amount.clear(); _acct.clear(); _name.clear();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Send to bank', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<String>(
              initialValue: _bankCode,
              items: widget.banks.map((b) => DropdownMenuItem(value: b.code, child: Text(b.name))).toList(),
              onChanged: (v) => setState(() => _bankCode = v),
              decoration: const InputDecoration(labelText: 'Bank'),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(controller: _acct, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Account number')),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Account name')),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(controller: _amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Amount (₦)')),
            const SizedBox(height: AppSpacing.sm),
            if (!_pending) ...[
              FilledButton(onPressed: _loading ? null : _initiate, child: Text(_loading ? 'Sending...' : 'Send')),
            ] else ...[
              TextFormField(initialValue: _otp, onChanged: (v) => _otp = v, decoration: const InputDecoration(labelText: 'Enter 6-digit code')),
              const SizedBox(height: AppSpacing.sm),
              FilledButton(onPressed: _loading ? null : _confirm, child: Text(_loading ? 'Confirming...' : 'Confirm payout')),
            ],
          ],
        ),
      ),
    );
  }
}

class _TxnTile extends StatelessWidget {
  const _TxnTile(this.t);

  final WalletTransaction t;

  @override
  Widget build(BuildContext context) {
    final sign = t.direction == 'credit' ? '+' : '-';
    return ListTile(
      dense: true,
      title: Text('${t.kind} • ${t.status}'),
      subtitle: Text(t.narration ?? t.reference),
      trailing: Text('$sign${t.amountNaira}', style: TextStyle(color: t.direction == 'credit' ? Colors.green : Colors.red)),
    );
  }
}

int parseKobo(String s) {
  final cleaned = s.replaceAll(',', '').replaceAll('₦', '').trim();
  if (cleaned.isEmpty) return 0;
  return (double.tryParse(cleaned) ?? 0) * 100 ~/ 1;
}
