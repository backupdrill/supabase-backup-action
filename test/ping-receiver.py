# Stands in for Healthchecks.io in the test workflow: answers every ping with 200 and
# prints the path it was sent to, one per line, so the test can check which pings arrived.
import http.server


class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length") or 0))
        print(self.path.split("?")[0], flush=True)
        self.send_response(200)
        self.end_headers()

    def log_message(self, *args):
        pass


http.server.HTTPServer(("127.0.0.1", 8099), Handler).serve_forever()
