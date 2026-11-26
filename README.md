# Qwen2.5 Chat Backend

Three small services behind a React Native chat app:

| Program | Port | Job |
| --- | --- | --- |
| `server.js` | 3000 | Accounts, conversations, messages, photos (Express + PostgreSQL). Also proxies chat and voice. |
| `ai-service.js` | 3001 | The only program that talks to Ollama. OpenAI-style `/v1` API, protected by `AI_API_KEY`. |
| `whisper_server.py` | 8001 | Optional voice transcription with faster-whisper. |

`server.js` never runs the model itself: it calls the AI service over HTTP, so the
AI service can run on this PC or on another one.

## Requirements

- Node.js 18 or newer
- PostgreSQL (13 or newer) with the `chat_app` database
- [Ollama](https://ollama.com) with a vision model, so photos work:
  ```
  ollama pull qwen2.5vl:7b
  ```
- Python 3.10+ — only for voice messages

## Setup

1. **Create the database** (once):
   ```
   createdb chat_app
   psql -d chat_app -f schema.sql
   psql -d chat_app -f api_keys.sql
   ```
   `schema.sql` is for a new database; `api_keys.sql` is the migration for the API-key
   feature and is safe to run on an existing one. See
   [DATABASE EXPECTATIONS](server.js#L9-L24) in `server.js` for why the indexes matter.

2. **Install Node dependencies:**
   ```
   npm install
   ```

3. **Configure the environment:**
   ```
   copy .env.example .env      # macOS/Linux: cp .env.example .env
   ```
   Fill in `JWT_SECRET`, the `PG*` values and `AI_API_KEY`. The AI key is shared:
   `ai-service.js` only accepts requests that send it, and `server.js` sends it.
   It must be at least 24 characters.

4. **Start the services** (three terminals, in this order):
   ```
   node ai-service.js
   node server.js
   python whisper_server.py      # optional
   ```
   Or `npm start` for the backend and `npm run start:ai` for the AI service.

5. **Check it is alive:**
   ```
   curl http://localhost:3000/health
   curl http://localhost:3001/health
   ```
   The backend answers `{"status":"ok","db":"connected"}`.

## First requests

Sign up, verify, then chat. Without SMTP configured, the verification code is
printed in the `server.js` console (development only).

```bash
# 1. Sign up
curl -X POST http://localhost:3000/api/auth/signup \
  -H "Content-Type: application/json" \
  -d '{"username":"alice","email":"alice@example.com","password":"supersecret123"}'

# 2. Verify (code from the email or the server console)
curl -X POST http://localhost:3000/api/auth/verify-email \
  -H "Content-Type: application/json" \
  -d '{"email":"alice@example.com","code":"123456"}'
# -> { "token": "...", "user": { ... } }

# 3. Create a conversation
curl -X POST http://localhost:3000/api/conversations \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"title":"First chat"}'

# 4. Send a message (Server-Sent Events stream)
curl -N -X POST http://localhost:3000/api/chat \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"conversationId":1,"message":"hello"}'
```

Calling the AI service directly:

```bash
curl -X POST http://localhost:3001/v1/chat/completions \
  -H "Authorization: Bearer $AI_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"hello"}]}'
```

## API

All routes except `/health` and the auth routes need
`Authorization: Bearer <jwt>` — or `Bearer cb_...` for an API key created at
`POST /api/account/api-keys`. There is no `x-api-key` header any more.

| Method | Route | Purpose |
| --- | --- | --- |
| GET | `/health` | Database check |
| POST | `/api/auth/signup` | Create an account and send a code |
| POST | `/api/auth/verify-email` | Verify the code, returns a token |
| POST | `/api/auth/resend` | Send a new verification code |
| POST | `/api/auth/login` | Password login |
| GET | `/api/me` | Current user |
| POST | `/api/account/request-code` | Code for `change_password` / `change_email` |
| POST | `/api/account/change-password` | Set a new password (revokes API keys) |
| POST | `/api/account/change-email` | Confirm a new email address |
| PATCH | `/api/account/username` | Change the username |
| GET/POST | `/api/account/api-keys` | List / create API keys |
| DELETE | `/api/account/api-keys/:id` | Revoke an API key |
| GET/POST | `/api/conversations` | List / create conversations |
| PUT/DELETE | `/api/conversations/:id` | Rename / delete a conversation |
| GET | `/api/conversations/:id/messages` | Message history (no image data, just `has_image`) |
| GET | `/api/messages/:id/image` | Download a stored photo |
| POST | `/api/chat` | Save the message and stream the reply (SSE) |
| POST | `/api/transcribe` | Voice to text via `whisper_server.py` |

Chat streaming: each event is `data: {"content":"..."}`, ending with
`data: {"done":true}`. Errors arrive as `data: {"error":"..."}`.

## Connecting the React Native app

- Use `Authorization: Bearer <token>`; the old `x-api-key` header is gone.
- On a phone testing against a PC on the same WiFi, use the PC's LAN IP, not `localhost`.
- Photos must be JPEG data URLs, at most about 2 MB after base64 encoding.
- A 401 with `"Session expired. Sign in again."` means the password or email changed;
  sign in again to get a fresh token.

## Security notes

- `.env` and `login.json` were committed to this repository in early commits. Both
  contain real credentials. If the repository was ever pushed anywhere, treat those
  passwords, the JWT secret, the PostgreSQL password, the SMTP app password, the
  Serper key and the AI key as leaked: rotate them, then remove the files from
  history with `git filter-repo` (or BFG) before making the repository public.
- `JWT_SECRET` must be long and random; everyone with it can mint tokens.
- Put the backend behind HTTPS (Caddy/nginx) before pointing a real app at it.
- `SMTP_*` unset is fine locally (codes print to the console) but production needs it.
