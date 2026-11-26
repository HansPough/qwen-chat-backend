-- Database schema for the CRUD server (server.js).
-- Fresh install:
--   createdb chat_app
--   psql -d chat_app -f schema.sql
--   psql -d chat_app -f api_keys.sql
--
-- This mirrors the columns, defaults and foreign keys the code actually uses.
-- Everything is IF NOT EXISTS so running it on a partly-built database is safe.

-- ---------------------------------------------------------------------------
-- users
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS users (
  id             SERIAL PRIMARY KEY,
  username       TEXT NOT NULL,
  email          TEXT NOT NULL,
  password_hash  TEXT NOT NULL,
  display_name   TEXT,
  created_at     TIMESTAMP DEFAULT NOW(),
  email_verified BOOLEAN NOT NULL DEFAULT FALSE,
  token_version  INTEGER NOT NULL DEFAULT 0
);

-- Logins look users up by lower(email), so the index has to be on lower(email):
-- a plain index on `email` would not be used and would not stop "A@x.com" and
-- "a@x.com" from becoming two accounts.
CREATE UNIQUE INDEX IF NOT EXISTS users_email_lower_idx ON users (lower(email));

-- ---------------------------------------------------------------------------
-- conversations
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS conversations (
  id         SERIAL PRIMARY KEY,
  user_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title      TEXT DEFAULT 'New chat',
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- The conversation list is "this user's chats, newest first".
CREATE INDEX IF NOT EXISTS conversations_user_idx ON conversations (user_id, updated_at DESC);

-- ---------------------------------------------------------------------------
-- messages
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS messages (
  id              SERIAL PRIMARY KEY,
  conversation_id INTEGER NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  role            TEXT NOT NULL,
  content         TEXT NOT NULL,
  created_at      TIMESTAMP DEFAULT NOW(),
  image           TEXT
);

-- History is read per conversation in id order. The ON DELETE CASCADE above is
-- what makes deleting a conversation remove its messages.
CREATE INDEX IF NOT EXISTS messages_conversation_idx ON messages (conversation_id, id);

-- ---------------------------------------------------------------------------
-- email_codes (one-time codes for verifying email / changing password / email)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS email_codes (
  id          SERIAL PRIMARY KEY,
  user_id     INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  email       TEXT NOT NULL,
  purpose     TEXT NOT NULL,
  code_hash   TEXT NOT NULL,
  expires_at  TIMESTAMPTZ NOT NULL,
  attempts    INTEGER NOT NULL DEFAULT 0,
  consumed_at TIMESTAMPTZ,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Codes are looked up by (user, purpose), newest first.
CREATE INDEX IF NOT EXISTS email_codes_lookup_idx ON email_codes (user_id, purpose, id DESC);
