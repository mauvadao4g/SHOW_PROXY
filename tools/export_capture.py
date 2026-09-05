#!/usr/bin/env python3
"""
Le um arquivo de captura .jsonl gerado pelo capture_plugin.py e exporta pra:
  - texto legivel (--txt)
  - .har (--har)
ou apenas imprime formatado no stdout (sem flag, usado por -r no proxy_view.sh).

Uso:
  export_capture.py CAPTURE.jsonl --txt OUT.txt
  export_capture.py CAPTURE.jsonl --har OUT.har
  export_capture.py CAPTURE.jsonl            # imprime no stdout
"""
import base64
import json
import sys
import time


def load_records(path):
    records = []
    with open(path, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                records.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    return records


def format_txt(records):
    out = []
    for r in records:
        ts = time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(r.get('ts', 0)))
        status = '-'
        resp = r.get('response') or {}
        if 'status' in resp:
            status = resp.get('status')
        out.append('=' * 70)
        out.append('%s  %s %s -> %s' % (ts, r.get('method'), r.get('url'), status))
        out.append('-- request headers --')
        for k, v in (r.get('request', {}).get('headers') or {}).items():
            out.append('%s: %s' % (k, v))
        rbody = r.get('request', {}).get('body') or {}
        if rbody.get('data'):
            out.append('-- request body (%s%s) --' % (
                rbody.get('encoding'), ', truncado' if rbody.get('truncated') else '',
            ))
            out.append(rbody['data'])
        if resp:
            out.append('-- response headers --')
            for k, v in (resp.get('headers') or {}).items():
                out.append('%s: %s' % (k, v))
            sbody = resp.get('body') or {}
            if sbody.get('data'):
                out.append('-- response body (%s%s) --' % (
                    sbody.get('encoding'), ', truncado' if sbody.get('truncated') else '',
                ))
                out.append(sbody['data'])
        out.append('')
    return '\n'.join(out)


def _har_headers(headers):
    return [{'name': k, 'value': v} for k, v in (headers or {}).items()]


def _har_body(body):
    if not body or not body.get('data'):
        return {'size': 0, 'mimeType': ''}
    if body.get('encoding') == 'base64':
        text = body['data']
        encoding = 'base64'
        size = len(base64.b64decode(text))
    else:
        text = body['data']
        encoding = None
        size = len(text.encode('utf-8'))
    entry = {'size': size, 'mimeType': 'application/octet-stream', 'text': text}
    if encoding:
        entry['encoding'] = encoding
    return entry


def format_har(records):
    entries = []
    for r in records:
        resp = r.get('response') or {}
        started = time.strftime(
            '%Y-%m-%dT%H:%M:%S.000Z', time.gmtime(r.get('ts', 0)),
        )
        entries.append({
            'startedDateTime': started,
            'time': 0,
            'request': {
                'method': r.get('method'),
                'url': r.get('url'),
                'httpVersion': 'HTTP/1.1',
                'headers': _har_headers(r.get('request', {}).get('headers')),
                'queryString': [],
                'cookies': [],
                'headersSize': -1,
                'bodySize': -1,
                'postData': (
                    {
                        'mimeType': 'application/octet-stream',
                        'text': (r.get('request', {}).get('body') or {}).get('data') or '',
                    }
                    if (r.get('request', {}).get('body') or {}).get('data') else None
                ),
            },
            'response': {
                'status': resp.get('status') or 0,
                'statusText': '',
                'httpVersion': 'HTTP/1.1',
                'headers': _har_headers(resp.get('headers')),
                'cookies': [],
                'content': _har_body(resp.get('body')),
                'redirectURL': '',
                'headersSize': -1,
                'bodySize': -1,
            },
            'cache': {},
            'timings': {'send': 0, 'wait': 0, 'receive': 0},
        })
    return {
        'log': {
            'version': '1.2',
            'creator': {'name': 'SHOW_PROXY', 'version': '1'},
            'entries': entries,
        },
    }


def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        sys.exit(1)
    capture_path = args[0]
    records = load_records(capture_path)

    if '--txt' in args:
        out_path = args[args.index('--txt') + 1]
        with open(out_path, 'w', encoding='utf-8') as f:
            f.write(format_txt(records))
        print('Exportado: %s (%d requests)' % (out_path, len(records)))
    elif '--har' in args:
        out_path = args[args.index('--har') + 1]
        with open(out_path, 'w', encoding='utf-8') as f:
            json.dump(format_har(records), f, ensure_ascii=False, indent=2)
        print('Exportado: %s (%d requests)' % (out_path, len(records)))
    else:
        print(format_txt(records))


if __name__ == '__main__':
    main()
