import '../utils/money.dart';

class Wallet {
  const Wallet({
    required this.id,
    required this.ownerType,
    required this.ownerId,
    required this.balanceKobo,
    this.virtualAccountBank,
    this.virtualAccountNumber,
    this.virtualAccountName,
    this.virtualAccountReference,
    this.updatedAt,
  });

  factory Wallet.fromJson(Map<String, dynamic> json) => Wallet(
        id: json['id'] as String,
        ownerType: json['ownerType'] as String? ?? json['owner_type'] as String? ?? '',
        ownerId: json['ownerId'] as String? ?? json['owner_id'] as String? ?? '',
        balanceKobo: (json['balanceKobo'] as num?)?.toInt() ?? (json['balance_kobo'] as num?)?.toInt() ?? 0,
        virtualAccountBank: json['virtualAccountBank'] as String? ?? json['virtual_account_bank'] as String?,
        virtualAccountNumber: json['virtualAccountNumber'] as String? ?? json['virtual_account_number'] as String?,
        virtualAccountName: json['virtualAccountName'] as String? ?? json['virtual_account_name'] as String?,
        virtualAccountReference: json['virtualAccountReference'] as String? ?? json['virtual_account_reference'] as String?,
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? json['updated_at'] as String? ?? ''),
      );

  final String id;
  final String ownerType;
  final String ownerId;
  final int balanceKobo;
  final String? virtualAccountBank;
  final String? virtualAccountNumber;
  final String? virtualAccountName;
  final String? virtualAccountReference;
  final DateTime? updatedAt;

  String get balanceNaira => formatKobo(balanceKobo);
}

class WalletTransaction {
  const WalletTransaction({
    required this.id,
    required this.direction,
    required this.kind,
    required this.channel,
    required this.status,
    required this.amountKobo,
    this.balanceAfterKobo,
    required this.reference,
    this.providerReference,
    this.counterpartyBank,
    this.counterpartyBankCode,
    this.counterpartyAccount,
    this.counterpartyName,
    this.narration,
    this.createdAt,
  });

  factory WalletTransaction.fromJson(Map<String, dynamic> json) => WalletTransaction(
        id: json['id'] as String,
        direction: json['direction'] as String,
        kind: json['kind'] as String,
        channel: json['channel'] as String,
        status: json['status'] as String,
        amountKobo: (json['amountKobo'] as num?)?.toInt() ?? (json['amount_kobo'] as num?)?.toInt() ?? 0,
        balanceAfterKobo: (json['balanceAfterKobo'] as num?)?.toInt() ?? (json['balance_after_kobo'] as num?)?.toInt(),
        reference: json['reference'] as String,
        providerReference: json['providerReference'] as String? ?? json['provider_reference'] as String?,
        counterpartyBank: json['counterpartyBank'] as String? ?? json['counterparty_bank'] as String?,
        counterpartyBankCode: json['counterpartyBankCode'] as String? ?? json['counterparty_bank_code'] as String?,
        counterpartyAccount: json['counterpartyAccount'] as String? ?? json['counterparty_account'] as String?,
        counterpartyName: json['counterpartyName'] as String? ?? json['counterparty_name'] as String?,
        narration: json['narration'] as String?,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? json['created_at'] as String? ?? ''),
      );

  final String id;
  final String direction;
  final String kind;
  final String channel;
  final String status;
  final int amountKobo;
  final int? balanceAfterKobo;
  final String reference;
  final String? providerReference;
  final String? counterpartyBank;
  final String? counterpartyBankCode;
  final String? counterpartyAccount;
  final String? counterpartyName;
  final String? narration;
  final DateTime? createdAt;

  String get amountNaira => formatKobo(amountKobo);
}

class Bank {
  const Bank({required this.code, required this.name});

  factory Bank.fromJson(Map<String, dynamic> json) => Bank(
        code: json['code'] as String,
        name: json['name'] as String,
      );

  final String code;
  final String name;
}
