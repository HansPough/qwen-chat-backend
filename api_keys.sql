-- Migration for the API-key feature: run once on an existing database.
--   psql "host=... dbname=chat_app user=..." -f api_keys.sql
-- Safe to run again (every statement is IF NOT EXISTS).
--
-- API keys are shown to the user once and then stored only as a SHA-256 hash,
-- so the `key_hash` column is the lookup key and must be unique.

CREATE TABLE IF NOT EXISTS api_keys (
  id           SERIAL PRIMARY KEY,
  user_id      INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name         TEXT NOT NULL,
  key_hash     TEXT NOT NULL UNIQUE,
  prefix       TEXT NOT NULL,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_used_at TIMESTAMPTZ,
  revoked_at   TIMESTAMPTZ
);

-- The app lists and counts only a user's active keys.
CREATE INDEX IF NOT EXISTS api_keys_user_idx ON api_keys (user_id) WHERE revoked_at IS NULL;
