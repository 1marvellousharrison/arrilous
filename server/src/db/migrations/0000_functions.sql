-- 0000_functions.sql
-- Provides an ISO UTC default timestamp that matches new Date().toISOString()
-- exactly, replacing the SQLite-specific strftime() used in earlier migrations.
CREATE OR REPLACE FUNCTION now_iso() RETURNS text
LANGUAGE sql STABLE AS $$
  SELECT to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"');
$$;