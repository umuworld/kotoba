"""Loopback-only protocol contract tests. Never uses a real provider or key."""
from http.server import BaseHTTPRequestHandler, HTTPServer
import json


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_GET(self):
        if self.path == '/health':
            self.respond(200, {'fixture': 'kotoba-protocol-v1'})
        else:
            self.respond(404, {})

    def respond(self, status, result):
        data = result if isinstance(result, bytes) else json.dumps(result).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_POST(self):
        try:
            self.handle_request()
        except (AssertionError, KeyError, ValueError) as error:
            print('Contract assertion failed:', type(error).__name__, flush=True)
            self.respond(400, {'error': 'fixture contract failed'})

    def handle_request(self):
        body = json.loads(self.rfile.read(int(self.headers.get('Content-Length', 0))))
        model = body['model']
        assert body['stream'] is False
        if self.path == '/v1/messages':
            assert self.headers.get('x-api-key') == 'fixture-token'
            assert self.headers.get('anthropic-version') == '2023-06-01'
            assert self.headers.get('Authorization') is None
            assert body['max_tokens'] == 8192
            assert all(m['role'] in ('user', 'assistant') for m in body['messages'])
            messages = ([{'role': 'system', 'content': body['system']}] if 'system' in body else []) + body['messages']
        else:
            assert self.headers.get('x-api-key') is None
            assert self.headers.get('anthropic-version') is None
            if model == 'test-local':
                assert self.headers.get('Authorization') is None
            else:
                assert self.headers.get('Authorization') == 'Bearer fixture-token'
            if self.path == '/v1/responses':
                assert body['store'] is False and body['max_output_tokens'] == 8192
                assert 'messages' not in body
                messages = body['input']
            else:
                assert self.path == '/v1/chat/completions'
                assert body['max_tokens'] == 8192
                messages = body['messages']
        if model in ('test-401', 'test-429'):
            return self.respond(int(model.split('-')[1]), {})
        if model == 'test-redirect':
            self.send_response(302)
            self.send_header('Location', 'http://127.0.0.1:18765/should-not-follow')
            self.end_headers()
            return
        if model == 'test-malformed':
            return self.respond(200, {'unexpected': True})
        if model == 'test-invalid-json':
            return self.respond(200, b'<html>invalid JSON</html>')
        if model in ('test-truncated', 'test-refused'):
            content = 'partial'
        elif messages[-1]['content'] == '请只回复 OK。':
            assert len(messages) == 1
            content = 'OK'
        elif '只输出 JSON' in messages[0]['content']:
            assert messages[0]['role'] == 'system'
            assert messages[-1]['content'] == '私の住所を知っていますか。'
            content = json.dumps({'translation': '你知道我的住址吗？', 'grammar': [], 'vocabulary': []}, ensure_ascii=False)
        else:
            assert '私の住所を知っていますか。' in messages[0]['content']
            assert [(m['role'], m['content']) for m in messages[1:]] == [('user', '第一问'), ('assistant', '第一答'), ('user', '解释一下')]
            content = '这是一条测试回答。'
        cut = model == 'test-truncated'
        refused = model == 'test-refused'
        # Split text blocks and include non-text output to catch fragile parsers.
        split = len(content) // 2
        if self.path == '/v1/responses':
            blocks = [{'type': 'output_text', 'text': part} for part in (content[:split], content[split:])]
            if refused:
                blocks = [{'type': 'refusal', 'refusal': 'declined'}]
            result = {'status': 'incomplete' if cut else 'completed', 'output': [{'type': 'reasoning', 'summary': []}, {'type': 'message', 'content': blocks}]}
        elif self.path == '/v1/messages':
            result = {'stop_reason': 'max_tokens' if cut else 'refusal' if refused else 'end_turn', 'content': [{'type': 'thinking', 'thinking': 'not an answer'}] + [{'type': 'text', 'text': part} for part in (content[:split], content[split:])]}
        else:
            result = {'choices': [{'finish_reason': 'length' if cut else 'content_filter' if refused else 'stop', 'message': {'role': 'assistant', 'content': content}}]}
        self.respond(200, result)


HTTPServer(('127.0.0.1', 18765), Handler).serve_forever()
