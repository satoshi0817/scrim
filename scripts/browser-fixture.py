#!/usr/bin/env python3
"""Local WebKit regression fixture; no real accounts or credentials."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import argparse

class Handler(BaseHTTPRequestHandler):
    def html(self, content):
        data = ('<!doctype html><meta charset="utf-8"><style>body{font:20px system-ui;padding:32px;background:#f5f5f3;color:#202322}button,a{font:inherit;padding:12px}</style>' + content).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path == '/login':
            self.html('''<title>Scrim ブラウザ確認</title><h1>Scrim</h1><p>タイトルバーなしのパネルです。</p>
<p>通常時はページを操作でき、編集時はパネルを移動できます。</p>
<button id="login" onclick="window.open('/popup','scrim-login')">別窓でログイン（テスト）</button>
<p><a id="blank" href="/popup" target="_blank">新しいウィンドウ（テスト）</a></p>
<p><input placeholder="通常時の入力を確認"></p>
<script>document.cookie='opener=present; SameSite=Lax; path=/';
addEventListener('storage',e=>{if(e.key==='oAuthQuery' && e.newValue)localStorage.setItem('storageCallback','received')});
addEventListener('message',e=>{if(e.origin===location.origin && e.data==='complete')location.href='/signed-in'});</script>''')
        elif self.path == '/popup':
            if 'opener=present' not in self.headers.get('Cookie', ''):
                self.html('<h1>cookie-sharing-failed</h1>')
            else:
                self.html('''<title>ログイン確認</title><h1>テスト用ログイン</h1>
<form action="/post" method="post"><input type="hidden" name="token" value="synthetic-only">
<button id="continue">ログインを完了（テスト）</button></form>''')
        elif self.path == '/complete':
            self.html('''<title>完了</title><script>localStorage.setItem('oAuthQuery','synthetic');window.opener.postMessage('complete',location.origin);setTimeout(()=>window.close(),500)</script>''')
        elif self.path == '/signed-in':
            authenticated = 'session=fixture' in self.headers.get('Cookie', '')
            self.html('<title>ログイン済み</title><h1>' + ('signed-in' if authenticated else 'session-missing') + '</h1>')
        else:
            self.send_error(404)

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get('Content-Length', '0')))
        if self.path != '/post' or body != b'token=synthetic-only':
            self.send_error(400)
            return
        self.send_response(302)
        self.send_header('Location', '/complete')
        self.send_header('Set-Cookie', 'session=fixture; HttpOnly; SameSite=Lax; path=/')
        self.send_header('Content-Length', '0')
        self.end_headers()

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', type=int, default=18764)
    args = parser.parse_args()
    server = ThreadingHTTPServer(('127.0.0.1', args.port), Handler)
    print(f'http://127.0.0.1:{server.server_port}/login', flush=True)
    server.serve_forever()
