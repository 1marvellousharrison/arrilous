-- 0020_order_imports.sql
-- AI/Chat order imports from screenshots/photos. The order may be created as
-- draft/incomplete; missing required details generate notifications in both
-- the general notifications stream and the AI/chat thread.

CREATE TABLE order_imports (
  id TEXT PRIMARY KEY,
  business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  source TEXT NOT NULL DEFAULT 'screenshot' CHECK (source IN ('whatsapp', 'screenshot', 'image')),
  image_url TEXT,
  status TEXT NOT NULL DEFAULT 'processing' CHECK (status IN ('processing', 'extracted', 'review', 'confirmed', 'completed', 'failed')),
  extracted_customer_name TEXT,
  extracted_customer_phone TEXT,
  extracted_customer_id TEXT REFERENCES customers(id) ON DELETE SET NULL,
  items_json TEXT,
  delivery_required INTEGER DEFAULT 0,
  delivery_address TEXT,
  delivery_fee_kobo INTEGER,
  discount_kobo INTEGER,
  notes TEXT,
  missing_fields_json TEXT,
  warnings_json TEXT,
  transaction_id TEXT REFERENCES transactions(id) ON DELETE SET NULL,
  created_at TEXT NOT NULL DEFAULT now_iso(),
  updated_at TEXT NOT NULL DEFAULT now_iso()
);

CREATE INDEX idx_order_imports_business ON order_imports(business_id, created_at DESC);
CREATE INDEX idx_order_imports_user ON order_imports(user_id, created_at DESC);

CREATE TABLE ai_chat_messages (
  id TEXT PRIMARY KEY,
  business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  order_import_id TEXT REFERENCES order_imports(id) ON DELETE CASCADE,
  role TEXT NOT NULL CHECK (role IN ('user', 'assistant', 'system')),
  message_type TEXT NOT NULL DEFAULT 'text' CHECK (message_type IN ('text', 'image', 'order_draft', 'notification', 'action')),
  content TEXT,
  metadata_json TEXT,
  read_by_owner INTEGER DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT now_iso()
);

CREATE INDEX idx_ai_chat_messages ON ai_chat_messages(business_id, created_at);

CREATE TABLE notifications (
  id TEXT PRIMARY KEY,
  business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  user_id TEXT REFERENCES users(id) ON DELETE CASCADE,
  order_import_id TEXT REFERENCES order_imports(id) ON DELETE CASCADE,
  transaction_id TEXT REFERENCES transactions(id) ON DELETE SET NULL,
  type TEXT NOT NULL,
  title TEXT NOT NULL,
  message TEXT NOT NULL,
  severity TEXT DEFAULT 'info' CHECK (severity IN ('info', 'warning', 'error', 'success')),
  read_at TEXT,
  created_at TEXT NOT NULL DEFAULT now_iso()
);

CREATE INDEX idx_notifications_user ON notifications(user_id, read_at, created_at DESC);
CREATE INDEX idx_notifications_business ON notifications(business_id, created_at DESC);
