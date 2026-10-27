"""One-time Spotify login: get a refresh token with read-only access to the
user's playlists, and append it to the keys file. Never prints secrets."""
import base64, http.server, json, secrets, sys, urllib.parse, urllib.request

KEYS = sys.argv[1]
REDIRECT = "http://127.0.0.1:8888/callback"
SCOPES = "playlist-read-private playlist-read-collaborative"

env = dict(l.strip().split("=", 1) for l in open(KEYS) if "=" in l)
cid, csec = env["CLIENT_ID"], env["CLIENT_SECRET"]
state = secrets.token_urlsafe(16)
url = "https://accounts.spotify.com/authorize?" + urllib.parse.urlencode(
    {"client_id": cid, "response_type": "code", "redirect_uri": REDIRECT,
     "scope": SCOPES, "state": state, "show_dialog": "true"})
print(url, flush=True)


class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        if q.get("state", [""])[0] != state or "code" not in q:
            self.send_response(400); self.end_headers()
            self.wfile.write("Ошибка: нет кода или неверный state".encode())
            print("ERROR:", q.get("error", ["no code"])[0], flush=True)
            return
        req = urllib.request.Request(
            "https://accounts.spotify.com/api/token",
            data=urllib.parse.urlencode({"grant_type": "authorization_code",
                                         "code": q["code"][0],
                                         "redirect_uri": REDIRECT}).encode(),
            headers={"Authorization": "Basic " + base64.b64encode(f"{cid}:{csec}".encode()).decode()})
        tok = json.load(urllib.request.urlopen(req))
        lines = [l for l in open(KEYS) if not l.startswith("REFRESH_TOKEN=")]
        lines.append("REFRESH_TOKEN=" + tok["refresh_token"] + "\n")
        open(KEYS, "w").writelines(lines)
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.end_headers()
        self.wfile.write("<h2>Готово, можно закрыть вкладку.</h2>".encode())
        print("OK: refresh token saved, scopes:", tok.get("scope"), flush=True)
        raise SystemExit


try:
    http.server.HTTPServer(("127.0.0.1", 8888), H).handle_request()
except SystemExit:
    pass
