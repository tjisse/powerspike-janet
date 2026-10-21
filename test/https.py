"""Exercise the production HTTPS client with a local TLS provider fixture."""
import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import os
from pathlib import Path
import ssl
import subprocess
import tempfile
import threading
import time


class Provider(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        idle = self.path in ('/idle', '/cdn/16.19.1/data/en_US/champion.json')
        status = 503 if self.path == '/unavailable' or '/16.18.1/' in self.path else 302 if self.path == '/redirect' else 200
        self.send_response(status)
        if status == 302:
            self.send_header('Location', '/ok')
        body = b'x'*64 if self.path == '/too-large' else b'fixture'
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.flush()
        if idle:
            time.sleep(6)
        try:
            self.wfile.write(body)
        except (OSError, ssl.SSLError):
            pass


def verify(janet):
    with tempfile.TemporaryDirectory(prefix='powerspike-tls-') as temp:
        root = Path(temp)
        cert, key = root/'cert.pem', root/'key.pem'
        subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1',
                        '-subj', '/CN=ddragon.leagueoflegends.com', '-addext',
                        'subjectAltName=DNS:ddragon.leagueoflegends.com', '-keyout', str(key), '-out', str(cert)],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        server = ThreadingHTTPServer(('127.0.0.1', 0), Provider)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(cert, key)
        server.socket = context.wrap_socket(server.socket, server_side=True)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            subprocess.run([janet, 'test/https.janet'], check=True, timeout=20, env={**os.environ,
                           'JANET_PATH':'build/web-modules', 'PS_TEST_TLS_PORT':str(server.server_port),
                           'PS_TEST_TLS_CERT':str(cert), 'PS_TEST_TLS_DATA':str(root/'data')})
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--janet', default='build/janet')
    verify(parser.parse_args().janet)
