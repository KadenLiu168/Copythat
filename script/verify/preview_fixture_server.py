#!/usr/bin/env python3
"""preview_fixture_server.py - sample-page server for preview live verification.

Routes are payload-safe sample pages only: og-image, title-only, slow-body
(navigation deliberately delayed) and hang (body never completes). Paths carry
case ids only; the server never logs and never sees clipboard content.

Usage: preview_fixture_server.py [port]
"""
import http.server
import socketserver
import struct
import sys
import time
import zlib

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8765


def png_bytes(rgb):
    width = height = 8
    row = b"\x00" + bytes(rgb) * width
    raw = row * height

    def chunk(tag, data):
        piece = struct.pack(">I", len(data)) + tag + data
        return piece + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    return b"".join([
        b"\x89PNG\r\n\x1a\n",
        chunk(b"IHDR", header),
        chunk(b"IDAT", zlib.compress(raw)),
        chunk(b"IEND", b""),
    ])


def html(title, extra_head, body):
    return (
        "<!doctype html><html><head><meta charset='utf-8'>"
        f"<title>{title}</title><link rel='icon' href='data:,'>"
        f"{body}</head><body><p>fixture {title}</p></body></html>"
    )


def og_page(base, n):
    return (
        "<!doctype html><html><head><meta charset='utf-8'>"
        f"<meta property='og:title' content='OG {n}'>"
        f"<meta property='og:image' content='http://127.0.0.1:{base}/png/{n}'>"
        "<link rel='icon' href='data:,'></head><body><p>og fixture</p></body></html>"
    )


def title_page(n):
    return (
        "<!doctype html><html><head><meta charset='utf-8'>"
        f"<title>Title only {n}</title>"
        "<link rel='icon' href='data:,'></head><body><p>no image</p></body></html>"
    )


def slow_body_page():
    return (
        "<!doctype html><html><head><meta charset='utf-8'>"
        "<title>Slow body</title><link rel='icon' href='data:,'></head>"
        "<body><div style='background:#ff8800;color:#fff;font-size:40px;padding:40px'>"
        "FALLBACK SNAPSHOT - orange means the browser fallback ran</div></body></html>"
    )


class FixtureHandler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "CopythatPreviewFixture/1.0"

    def send_body(self, body, content_type="text/html; charset=utf-8"):
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = self.path.split("?")[0].strip("/")
        parts = [piece for piece in path.split("/") if piece]
        kind = parts[0] if parts else ""
        n = parts[1] if len(parts) > 1 else "1"
        if kind == "png":
            self.send_body(png_bytes((200, 60, 60)), "image/png")
        elif kind == "og":
            self.send_body(og_page(PORT, n).encode())
        elif kind == "title":
            self.send_body(title_page(n).encode())
        elif kind == "slowbody":
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Connection", "close")
            self.end_headers()
            self.wfile.write(b"<!doctype html><html><head>")
            self.wfile.write(b"<title>Slow body</title></head><body>")
            self.wfile.flush()
            time.sleep(4.0)
            self.wfile.write(slow_body_page().encode().split(b"<body>", 1)[1])
            self.wfile.write(b"</body></html>")
            self.wfile.flush()
            self.close_connection = True
        elif kind == "hang":
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Connection", "close")
            self.end_headers()
            self.wfile.write(b"<!doctype html><html><head><title>Hang</title></head><body>")
            self.wfile.flush()
            time.sleep(30)
            self.close_connection = True
        else:
            self.send_response(404)
            self.send_header("Content-Length", "0")
            self.end_headers()

    def log_message(self, format, *args):  # noqa: A002 - silence stdlib logging
        pass


class ThreadingServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def handle_error(self, request, client_address):
        error = sys.exc_info()[1]
        if isinstance(error, (BrokenPipeError, ConnectionResetError)):
            return
        super().handle_error(request, client_address)


if __name__ == "__main__":
    ThreadingServer(("127.0.0.1", PORT), FixtureHandler).serve_forever()
