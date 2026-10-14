-- Wallet extension. A wallet belongs to exactly one owner: a business, a
-- logistics organization, or an individual rider. Money is stored as an integer
-- count of kobo, never a REAL in naira, so a balance can never drift.
--
-- A customer transfer lands as a `funding` credit (through the provider's
-- virtual account or a card charge); money leaving for another bank is a
-- `payout` debit that only settles after a confirmed one-time code.
CREATE TABLE wallets (
  id TEXT PRIMARY KEY,
  owner_type TEXT NOT NULL CHECK (owner_type IN ('business', 'organization', 'rider')),
  owner_id TEXT NOT NULL,
  owner_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  balance_kobo INTEGER NOT NULL DEFAULT 0 CHECK (balance_kobo >= 0),
  virtual_account_bank TEXT,
  virtual_account_number TEXT,
  virtual_account_name TEXT,
  virtual_account_reference TEXT,
  virtual_account_bank_code TEXT,
  created_at TEXT NOT NULL DEFAULT now_iso(),
  updated_at TEXT NOT NULL DEFAULT now_iso(),
  UNIQUE (owner_type, owner_id)
);

CREATE TABLE wallet_transactions (
  id TEXT PRIMARY KEY,
  wallet_id TEXT NOT NULL REFERENCES wallets(id) ON DELETE CASCADE,
  direction TEXT NOT NULL CHECK (direction IN ('credit', 'debit')),
  kind TEXT NOT NULL CHECK (kind IN ('funding', 'payout')),
  channel TEXT NOT NULL CHECK (channel IN ('virtual_account', 'card', 'payout')),
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'successful', 'failed')),
  amount_kobo INTEGER NOT NULL CHECK (amount_kobo > 0),
  balance_after_kobo INTEGER,
  reference TEXT NOT NULL UNIQUE,
  provider_reference TEXT,
  counterparty_bank TEXT,
  counterparty_bank_code TEXT,
  counterparty_account TEXT,
  counterparty_name TEXT,
  narration TEXT,
  created_at TEXT NOT NULL DEFAULT now_iso(),
  updated_at TEXT NOT NULL DEFAULT now_iso()
);
CREATE INDEX idx_wallet_transactions_wallet ON wallet_transactions(wallet_id, created_at);

-- A payout waits for a one-time code. The code is only ever stored hashed; the
-- payout itself is the pending debit row above, so a confirmed code is what
-- turns that row from `pending` into `successful`.
CREATE TABLE wallet_payout_otps (
  id TEXT PRIMARY KEY,
  wallet_transaction_id TEXT NOT NULL REFERENCES wallet_transactions(id) ON DELETE CASCADE,
  otp_hash TEXT NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0,
  expires_at TEXT NOT NULL,
  consumed_at TEXT,
  created_at TEXT NOT NULL DEFAULT now_iso()
);
CREATE INDEX idx_wallet_payout_otps_txn ON wallet_payout_otps(wallet_transaction_id);
