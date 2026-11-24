#!/usr/bin/env python3
"""Local stand-in for the parts of the Notion API the task panel uses; synthetic data, no real accounts."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import argparse, copy, itertools, json, threading

TOKEN = 'fixture-token'
VERSION = '2026-03-11'
PAGE_SIZE = 2  # small on purpose, so the client has to follow next_cursor
lock = threading.Lock()
ids = itertools.count(100)

def rich(text):
    return [{'type': 'text', 'text': {'content': text}, 'plain_text': text}]

PEOPLE = {'u1': '佐藤', 'u2': '鈴木'}

STATUS = {'options': [{'id': 'o1', 'name': '未着手', 'color': 'default'}, {'id': 'o2', 'name': '進行中', 'color': 'blue'},
                      {'id': 'o3', 'name': '完了', 'color': 'green'}, {'id': 'o4', 'name': '中止', 'color': 'gray'}],
          'groups': [{'id': 'g1', 'name': 'To-do', 'option_ids': ['o1']}, {'id': 'g2', 'name': 'In progress', 'option_ids': ['o2']},
                     {'id': 'g3', 'name': 'Complete', 'option_ids': ['o3', 'o4']}]}

def initial_state():
    sources = {
        'ds-status': {'title': 'プロジェクト', 'properties': {
            '名前': {'id': 'title', 'type': 'title', 'title': {}},
            'ステータス': {'id': '%3AUPp', 'type': 'status', 'status': copy.deepcopy(STATUS)},
            '期限': {'id': 'd%2Fe', 'type': 'date', 'date': {}},
            'タグ': {'id': 'tg', 'type': 'multi_select', 'multi_select': {'options': [
                {'id': 't1', 'name': '営業', 'color': 'blue'}, {'id': 't2', 'name': '開発', 'color': 'green'}]}},
            '担当': {'id': 'pp', 'type': 'people', 'people': {}}}},
        'ds-checkbox': {'title': 'チーム タスク', 'properties': {
            'タスク': {'id': 'title', 'type': 'title', 'title': {}},
            '済み': {'id': 'chk', 'type': 'checkbox', 'checkbox': {}}}},
        'ds-hidden': None,  # exists but is not shared with the connection
    }
    pages = {}
    def add(source, title, **values):
        pid = f'page-{next(ids)}'
        pages[pid] = {'source': source, 'title': title, 'values': values, 'created': f'2026-11-{len(pages) + 1:02d}T00:00:00.000Z'}
    add('ds-status', '資料を共有', status='o1', due='2026-11-30', tags=['t1'], people=['u1'])
    add('ds-status', '見積もりを確認', status='o2', due='2026-11-25', tags=['t2'], people=['u2'])
    add('ds-status', '週次レポート', status='o1', tags=['t1', 't2'])
    add('ds-status', '終わった作業', status='o3')
    add('ds-status', '取りやめた作業', status='o4')
    for n in range(5):
        add('ds-checkbox', f'チェック {n + 1}', checked=False)
    add('ds-checkbox', '済んだチェック', checked=True)
    # Page content of the first task: a mix of editable, formatted, nested and read-only blocks.
    first = next(iter(pages))
    blocks, children = {}, {}
    def block(parent, bid, kind, content):
        blocks[bid] = {'id': bid, 'type': kind, 'content': content, 'parent': parent}
        children.setdefault(parent, []).append(bid)
    block(first, 'b-h', 'heading_2', {'rich_text': runs(('準備', {}))})
    block(first, 'b-p', 'paragraph', {'rich_text': runs(('資料をまとめる', {}))})
    block(first, 'b-bold', 'paragraph', {'rich_text': runs(('重要：', {'bold': True}), ('期限を守る', {}))})
    block(first, 'b-todo', 'to_do', {'rich_text': runs(('下書きを作る', {})), 'checked': False})
    block(first, 'b-list', 'bulleted_list_item', {'rich_text': runs(('確認先', {}))})
    block('b-list', 'b-nested', 'bulleted_list_item', {'rich_text': runs(('営業チーム', {}))})
    block(first, 'b-n1', 'numbered_list_item', {'rich_text': runs(('一つ目', {}))})
    block(first, 'b-n2', 'numbered_list_item', {'rich_text': runs(('二つ目', {}))})
    block(first, 'b-img', 'image', {'type': 'external', 'external': {'url': 'https://example.invalid/image.png'}})
    block(first, 'b-child', 'child_page', {'title': '議事録'})
    block(first, 'b-form', 'unsupported', {'block_type': 'form'})
    return {'sources': sources, 'pages': pages, 'search_pages': {'page-root': '作業メモ'}, 'requests': [],
            'blocks': blocks, 'children': children}

def runs(*parts):
    out = []
    for text, flags in parts:
        annotations = {'bold': False, 'italic': False, 'strikethrough': False, 'underline': False, 'code': False, 'color': 'default'}
        annotations.update(flags)
        out.append({'type': 'text', 'text': {'content': text, 'link': None}, 'annotations': annotations, 'plain_text': text, 'href': None})
    return out

def block_json(bid):
    b = state['blocks'][bid]
    return {'object': 'block', 'id': bid, 'type': b['type'], b['type']: copy.deepcopy(b['content']),
            'has_children': bool(state['children'].get(bid)), 'in_trash': False}

state = initial_state()

# Databases reached by a pasted link or ID; each lists its data sources.
DATABASES = {
    '1f2e3d4c5b6a79881f2e3d4c5b6a7988': ('プロジェクト', ['ds-status']),
    '2a2b2c2d2e2f30313233343536373839': ('まとめ', ['ds-status', 'ds-checkbox']),
}
# A data source pasted by its own ID ("Copy data source ID").
ALIASES = {'3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c': 'ds-checkbox'}

def resolve(sid):
    return ALIASES.get((sid or '').replace('-', ''), sid)

def prop_by_id(source, pid):
    for name, prop in state['sources'][source]['properties'].items():
        if prop['id'] == pid or name == pid:
            return name, prop
    return None, None

def page_json(pid):
    page = state['pages'][pid]
    source = state['sources'][page['source']]
    props = {}
    for name, prop in source['properties'].items():
        kind = prop['type']
        value = {'id': prop['id'], 'type': kind}
        if kind == 'title': value['title'] = rich(page['title'])
        elif kind == 'checkbox': value['checkbox'] = page['values'].get('checked', False)
        elif kind == 'status':
            option = next((o for o in prop['status']['options'] if o['id'] == page['values'].get('status')), None)
            value['status'] = option and {'id': option['id'], 'name': option['name']}
        elif kind == 'date':
            due = page['values'].get('due')
            value['date'] = due and {'start': due, 'end': None, 'time_zone': None}
        elif kind == 'multi_select':
            names = {o['id']: o['name'] for o in prop['multi_select']['options']}
            value['multi_select'] = [{'id': t, 'name': names[t]} for t in page['values'].get('tags', [])]
        elif kind == 'people':
            value['people'] = [{'object': 'user', 'id': u, 'name': PEOPLE[u]} for u in page['values'].get('people', [])]
        props[name] = value
    return {'object': 'page', 'id': pid, 'created_time': page['created'], 'in_trash': False,
            'url': f'https://app.notion.com/p/{pid}', 'parent': {'type': 'data_source_id', 'data_source_id': page['source']},
            'properties': props}

def apply_properties(source, page, properties):
    for key, value in properties.items():
        name, prop = prop_by_id(source, key)
        if prop is None:
            return False
        kind = prop['type']
        if kind == 'title': page['title'] = ''.join(part['text']['content'] for part in value['title'])
        elif kind == 'checkbox': page['values']['checked'] = bool(value['checkbox'])
        elif kind == 'status':
            option = value['status']
            if option is None: page['values']['status'] = None
            elif not any(o['id'] == option.get('id') for o in prop['status']['options']): return False
            else: page['values']['status'] = option['id']
        elif kind == 'date':
            page['values']['due'] = value['date'] and value['date']['start']
        else:
            return False
    return True

def matches(source, page, condition):
    if 'and' in condition: return all(matches(source, page, c) for c in condition['and'])
    name, prop = prop_by_id(source, condition['property'])
    if prop is None: raise KeyError(condition['property'])
    if 'checkbox' in condition: return page['values'].get('checked', False) == condition['checkbox']['equals']
    if 'status' in condition:
        option = next((o for o in prop['status']['options'] if o['id'] == page['values'].get('status')), None)
        return (option or {}).get('name') != condition['status']['does_not_equal']
    raise KeyError('unsupported filter')

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args): pass

    def reply(self, status, body):
        data = json.dumps(body, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def error(self, status, code):
        self.reply(status, {'object': 'error', 'status': status, 'code': code, 'message': code})

    def body(self):
        length = int(self.headers.get('Content-Length') or 0)
        return json.loads(self.rfile.read(length) or b'{}')

    def handle_api(self, method):
        path = self.path.split('?')[0]
        if path == '/__state':
            blocks = {bid: {'type': b['type'], 'parent': b['parent'], 'checked': b['content'].get('checked'),
                            'text': ''.join(r['plain_text'] for r in b['content'].get('rich_text', []))} for bid, b in state['blocks'].items()}
            return self.reply(200, {'pages': {pid: {'title': p['title'], **p['values'], 'source': p['source']} for pid, p in state['pages'].items()},
                                    'sources': list(state['sources']), 'blocks': blocks, 'children': state['children'],
                                    'requests': state['requests'][-50:]})
        if path == '/__reset':
            state.clear(); state.update(initial_state()); return self.reply(200, {})
        if self.headers.get('Authorization') != f'Bearer {TOKEN}':
            return self.error(401, 'unauthorized')
        if self.headers.get('Notion-Version') != VERSION:
            return self.error(400, 'missing_version')
        body = self.body() if method in ('POST', 'PATCH') else {}
        state['requests'].append({'method': method, 'path': path, 'body': body})
        parts = path.strip('/').split('/')
        if len(parts) == 4 and parts[:2] == ['v1', 'blocks'] and parts[3] == 'children':
            parent = parts[2]
            if parent not in state['pages'] and parent not in state['blocks']: return self.error(404, 'object_not_found')
            if method == 'GET':
                from urllib.parse import urlparse, parse_qs
                query = parse_qs(urlparse(self.path).query)
                size = min(int(query.get('page_size', ['100'])[0]), 3)  # small pages exercise start_cursor
                start = int(query.get('start_cursor', ['0'])[0])
                child_ids = state['children'].get(parent, [])
                chunk = child_ids[start:start + size]; more = start + size < len(child_ids)
                return self.reply(200, {'object': 'list', 'type': 'block', 'block': {}, 'results': [block_json(b) for b in chunk],
                                        'has_more': more, 'next_cursor': str(start + size) if more else None})
            if method == 'PATCH':
                if body.get('position') != {'type': 'end'} or 'after' in body: return self.error(400, 'validation_error')
                added = []
                for child in body.get('children', []):
                    kind = child['type']; bid = f'b-new-{next(ids)}'
                    state['blocks'][bid] = {'id': bid, 'type': kind, 'content': {'rich_text': runs(*[(r['text']['content'], {}) for r in child[kind]['rich_text']]),
                                                                              **({'checked': child[kind].get('checked', False)} if kind == 'to_do' else {})}, 'parent': parent}
                    state['children'].setdefault(parent, []).append(bid); added.append(block_json(bid))
                return self.reply(200, {'object': 'list', 'results': added, 'has_more': False, 'next_cursor': None})
        if len(parts) == 3 and parts[:2] == ['v1', 'blocks']:
            b = state['blocks'].get(parts[2])
            if b is None: return self.error(404, 'object_not_found')
            if method == 'DELETE':
                state['children'][b['parent']].remove(parts[2]); reply = block_json(parts[2]); del state['blocks'][parts[2]]
                reply['in_trash'] = True
                return self.reply(200, reply)
            if method == 'PATCH':
                update = body.get(b['type'])
                if update is None or set(body) - {b['type'], 'type'}: return self.error(400, 'validation_error')
                if 'rich_text' in update:
                    b['content']['rich_text'] = runs(*[(r['text']['content'], {}) for r in update['rich_text']])
                if 'checked' in update: b['content']['checked'] = bool(update['checked'])
                return self.reply(200, block_json(parts[2]))
        if parts == ['v1', 'users', 'me'] and method == 'GET':
            return self.reply(200, {'object': 'user', 'id': 'bot-1', 'type': 'bot'})
        if parts == ['v1', 'search'] and method == 'POST':
            kind, query = body.get('filter', {}).get('value'), body.get('query', '')
            if kind == 'data_source':
                results = [{'object': 'data_source', 'id': sid, 'title': rich(s['title'])}
                           for sid, s in state['sources'].items() if s and query in s['title']]
            else:
                results = [{'object': 'page', 'id': pid, 'properties': {'title': {'id': 'title', 'type': 'title', 'title': rich(title)}}}
                           for pid, title in state['search_pages'].items() if query in title]
            return self.reply(200, {'object': 'list', 'results': results, 'has_more': False, 'next_cursor': None})
        if len(parts) == 3 and parts[:2] == ['v1', 'databases'] and method == 'GET':
            database = DATABASES.get(parts[2].replace('-', ''))
            if database is None: return self.error(404, 'object_not_found')
            title, sources = database
            return self.reply(200, {'object': 'database', 'id': parts[2], 'title': rich(title),
                                    'data_sources': [{'id': sid, 'name': state['sources'][sid]['title']} for sid in sources]})
        if len(parts) == 3 and parts[:2] == ['v1', 'data_sources'] and method == 'GET':
            source = state['sources'].get(resolve(parts[2]))
            if source is None: return self.error(404, 'object_not_found')
            props = {name: {'name': name, **copy.deepcopy(p)} for name, p in source['properties'].items()}
            return self.reply(200, {'object': 'data_source', 'id': parts[2], 'title': rich(source['title']), 'properties': props})
        if len(parts) == 4 and parts[:2] == ['v1', 'data_sources'] and parts[3] == 'query' and method == 'POST':
            sid = resolve(parts[2])
            if state['sources'].get(sid) is None: return self.error(404, 'object_not_found')
            try:
                found = [pid for pid, p in state['pages'].items() if p['source'] == sid and matches(sid, p, body.get('filter', {'and': []}))]
            except KeyError:
                return self.error(400, 'validation_error')
            found.sort(key=lambda pid: state['pages'][pid]['created'])
            start = int(body.get('start_cursor') or 0)
            chunk = found[start:start + PAGE_SIZE]
            more = start + PAGE_SIZE < len(found)
            return self.reply(200, {'object': 'list', 'results': [page_json(pid) for pid in chunk], 'has_more': more,
                                    'next_cursor': str(start + PAGE_SIZE) if more else None})
        if parts == ['v1', 'pages'] and method == 'POST':
            sid = resolve(body.get('parent', {}).get('data_source_id'))
            if state['sources'].get(sid) is None: return self.error(404, 'object_not_found')
            pid = f'page-{next(ids)}'
            page = {'source': sid, 'title': '', 'values': {}, 'created': f'2026-12-{len(state["pages"]) % 28 + 1:02d}T00:00:00.000Z'}
            if not apply_properties(sid, page, body.get('properties', {})): return self.error(400, 'validation_error')
            state['pages'][pid] = page
            return self.reply(200, page_json(pid))
        if len(parts) == 3 and parts[:2] == ['v1', 'pages'] and method == 'PATCH':
            page = state['pages'].get(parts[2])
            if page is None: return self.error(404, 'object_not_found')
            updated = copy.deepcopy(page)
            if not apply_properties(page['source'], updated, body.get('properties', {})): return self.error(400, 'validation_error')
            state['pages'][parts[2]] = updated
            return self.reply(200, page_json(parts[2]))
        if parts == ['v1', 'databases'] and method == 'POST':
            parent = body.get('parent', {}).get('page_id')
            if parent not in state['search_pages']: return self.error(404, 'object_not_found')
            sid = f'ds-new-{next(ids)}'
            props = {}
            for name, definition in body['initial_data_source']['properties'].items():
                kind = next(iter(definition))
                props[name] = {'id': 'title' if kind == 'title' else f'p{next(ids)}', 'type': kind, kind: {}}
            state['sources'][sid] = {'title': ''.join(t['text']['content'] for t in body.get('title', [])), 'properties': props}
            return self.reply(200, {'object': 'database', 'id': f'db-{sid}', 'data_sources': [{'id': sid, 'name': state['sources'][sid]['title']}]})
        return self.error(400, 'invalid_request_url')

    def do_GET(self):
        with lock: self.handle_api('GET')
    def do_POST(self):
        with lock: self.handle_api('POST')
    def do_PATCH(self):
        with lock: self.handle_api('PATCH')
    def do_DELETE(self):
        with lock: self.handle_api('DELETE')

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', type=int, default=18765)
    args = parser.parse_args()
    server = ThreadingHTTPServer(('127.0.0.1', args.port), Handler)
    print(f'http://127.0.0.1:{server.server_port}/', flush=True)
    server.serve_forever()
