import json, os, tempfile
from http.server import BaseHTTPRequestHandler, HTTPServer
from faster_whisper import WhisperModel

LANGUAGE = "en"  # set to None to auto-detect
model = WhisperModel("small", device="cpu", compute_type="int8")


class Handler(BaseHTTPRequestHandler):
    def _send_json(self, code, payload):
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        # A missing or malformed Content-Length used to raise here, which closed the
        # connection without any response and made the backend report the Whisper
        # service as "not running".
        try:
            size = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            size = 0
        if size <= 0:
            self._send_json(400, {"error": "No audio in the request body"})
            return

        data = self.rfile.read(size)
        with tempfile.NamedTemporaryFile(delete=False, suffix=".m4a") as f:
            f.write(data)
            path = f.name
        try:
            segments, _ = model.transcribe(path, language=LANGUAGE, beam_size=1, vad_filter=True)
            self._send_json(200, {"text": " ".join(s.text.strip() for s in segments).strip()})
        except Exception as e:
            self._send_json(500, {"error": str(e)})
        finally:
            os.remove(path)

    def log_message(self, *args):
        pass


print("Whisper ready on http://127.0.0.1:8001")
HTTPServer(("127.0.0.1", 8001), Handler).serve_forever()
