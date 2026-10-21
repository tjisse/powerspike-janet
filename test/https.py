"""Exercise the production HTTPS client with a local TLS provider fixture."""
import argparse
from collections import Counter
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import ssl
import subprocess
import tempfile
import threading
import time


class Provider(BaseHTTPRequestHandler):
    requests = Counter()
    recovered = False
    patch_recovered = False
    lock = threading.Lock()
    def log_message(self, *args):
        pass

    def do_GET(self):
        with Provider.lock:
            Provider.requests[self.path] += 1
        if self.path == '/recover':
            Provider.recovered = True
        if self.path == '/recover-patch':
            Provider.patch_recovered = True
        idle = self.path in ('/idle', '/cdn/16.19.1/data/en_US/champion.json')
        partial = self.path.startswith('/cdn/16.17.1/data/en_US/')
        partial_catalog = partial and self.path.endswith(('champion.json', 'item.json'))
        partial_outage = partial and not partial_catalog and not Provider.patch_recovered
        status = 503 if self.path == '/unavailable' or '/16.18.1/' in self.path or partial_outage or (self.path == '/outage.png' and not Provider.recovered) else 302 if self.path == '/redirect' else 200
        self.send_response(status)
        if status == 302:
            self.send_header('Location', '/ok')
        body = b'x'*64 if self.path == '/too-large' else b'fixture'
        # Required catalogs succeed, then optional sources stall in succession.
        # Neither response alone reaches the existing 45-second request limit.
        if partial_catalog or (partial and Provider.patch_recovered and self.path.endswith('summoner.json')):
            body = json.dumps({'version':'16.17.1', 'data':{}}).encode()
        elif partial and Provider.patch_recovered:
            body = b'[]'
        elif self.path.startswith('/16.17/') and Provider.patch_recovered:
            body = b'{}'
        if self.path == '/counts':
            body = json.dumps(Provider.requests).encode()
        elif self.path == '/outage.png' and Provider.recovered:
            body = b'\x89PNG\r\n\x1a\n'+b'fixture'
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.flush()
        if idle:
            time.sleep(6)
        elif partial_outage and self.path.endswith('runesReforged.json'):
            time.sleep(.75)
        elif partial_outage and self.path.endswith('summoner.json'):
            time.sleep(6)
        elif self.path == '/outage.png':
            time.sleep(.1)
        try:
            self.wfile.write(body)
        except (OSError, ssl.SSLError):
            pass


def verify(janet):
    Provider.requests.clear()
    Provider.recovered = False
    Provider.patch_recovered = False
    with tempfile.TemporaryDirectory(prefix='powerspike-tls-') as temp:
        root = Path(temp)
        cert, key = root/'cert.pem', root/'key.pem'
        subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1',
                        '-subj', '/CN=ddragon.leagueoflegends.com', '-addext',
                        'subjectAltName=DNS:ddragon.leagueoflegends.com,DNS:raw.communitydragon.org', '-keyout', str(key), '-out', str(cert)],
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
