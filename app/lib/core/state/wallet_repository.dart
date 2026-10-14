import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../api/wallet_models.dart';
import 'auth_repository.dart';

class WalletRepository extends ChangeNotifier {
  WalletRepository(this._api, this._auth);

  final ApiClient _api;
  final AuthRepository _auth;

  Wallet? _wallet;
  List<WalletTransaction> _transactions = const [];
  List<Bank> _banks = const [];
  bool _loading = false;
  bool _loaded = false;
  String? _error;

  Wallet? get wallet => _wallet;
  List<WalletTransaction> get transactions => _transactions;
  List<Bank> get banks => _banks;
  bool get loading => _loading;
  bool get loaded => _loaded;
  String? get error => _error;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final data = await _api.get('/wallet', token: _token);
      _wallet = Wallet.fromJson(data['wallet'] as Map<String, dynamic>);
      await loadTransactions();
    } on ApiException catch (e) {
      _error = e.message;
    } on NetworkException catch (e) {
      _error = e.message;
    } finally {
      _loading = false;
      _loaded = true;
      notifyListeners();
    }
  }

  Future<void> loadTransactions() async {
    try {
      final data = await _api.get('/wallet/transactions', token: _token);
      final list = (data['transactions'] as List?) ?? const [];
      _transactions = list.whereType<Map<String, dynamic>>().map(WalletTransaction.fromJson).toList();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> loadBanks() async {
    try {
      final data = await _api.get('/wallet/banks', token: _token);
      final list = (data['banks'] as List?) ?? const [];
      _banks = list.whereType<Map<String, dynamic>>().map(Bank.fromJson).toList();
      notifyListeners();
    } catch (_) {}
  }

  Future<Map<String, dynamic>> fundVirtualAccount() async {
    final data = await _api.post('/wallet/fund', body: {'amount_kobo': 0, 'channel': 'virtual_account'}, token: _token);
    _wallet = Wallet.fromJson(data['wallet'] as Map<String, dynamic>);
    notifyListeners();
    return data as Map<String, dynamic>;
  }

  Future<Wallet> fundCard({required int amountKobo, required String cardNumber}) async {
    final data = await _api.post('/wallet/fund', body: {'amount_kobo': amountKobo, 'channel': 'card', 'card_number': cardNumber}, token: _token);
    _wallet = Wallet.fromJson(data['wallet'] as Map<String, dynamic>);
    await loadTransactions();
    notifyListeners();
    return _wallet!;
  }

  Future<Map<String, dynamic>> resolveAccount({required String bankCode, required String accountNumber}) async {
    return await _api.post('/wallet/resolve-account', body: {'bank_code': bankCode, 'account_number': accountNumber}, token: _token) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> initiatePayout({
    required int amountKobo,
    required String bankCode,
    required String accountNumber,
    required String accountName,
  }) async {
    return await _api.post('/wallet/payout', body: {
      'amount_kobo': amountKobo,
      'bank_code': bankCode,
      'account_number': accountNumber,
      'account_name': accountName,
    }, token: _token) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> confirmPayout({required String otp}) async {
    final data = await _api.post('/wallet/payout/confirm', body: {'otp': otp}, token: _token) as Map<String, dynamic>;
    if (data['wallet'] != null) _wallet = Wallet.fromJson(data['wallet'] as Map<String, dynamic>);
    await loadTransactions();
    notifyListeners();
    return data;
  }

  String get _token {
    final session = _auth.session;
    if (session == null) {
      throw ApiException(401, 'unauthorized', 'You need to sign in to continue.');
    }
    return session.accessToken;
  }

  void reset() {
    _wallet = null;
    _transactions = const [];
    _banks = const [];
    _loading = false;
    _loaded = false;
    _error = null;
    notifyListeners();
  }
}
