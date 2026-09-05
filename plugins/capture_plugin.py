# -*- coding: utf-8 -*-
"""
Plugin de captura para o proxy.py (usado pelo SHOW_PROXY no Termux).

Grava cada requisição/resposta como uma linha JSON (.jsonl) no arquivo apontado
por CAPTURE_FILE. Corpos comprimidos (Content-Encoding: gzip/deflate/br) sao
descomprimidos automaticamente antes de salvar, pra ficarem legiveis. Suporta
filtro simples por dominio (CAPTURE_FILTER_DOMAIN, substring) e por metodo HTTP
(CAPTURE_FILTER_METHOD). O nivel de detalhe impresso ao vivo no stdout e'
controlado por CAPTURE_DETAIL:
  0 = so uma linha de acesso por requisicao (default)
  1 = + headers
  2 = + body (truncado)

Variaveis de ambiente usadas:
  CAPTURE_FILE            caminho do .jsonl de saida (obrigatorio p/ gravar)
  CAPTURE_FILTER_DOMAIN   substring: so grava/mostra requests p/ hosts que contenham isso
  CAPTURE_FILTER_METHOD   metodo HTTP exato (GET, POST, ...)
  CAPTURE_DETAIL          0|1|2 (default 0)
  CAPTURE_BODY_MAXLEN     tamanho maximo de body armazenado por request/response (default 65536)
"""
import gzip
import json
import os
import ssl
import time
import zlib
from typing import Optional

from proxy.http.proxy import HttpProxyBasePlugin
from proxy.http.parser import HttpParser
from proxy.common.utils import text_

MAX_BODY_LEN = int(os.environ.get('CAPTURE_BODY_MAXLEN', '65536'))
DETAIL = int(os.environ.get('CAPTURE_DETAIL', '0'))
FILTER_DOMAIN = os.environ.get('CAPTURE_FILTER_DOMAIN', '').strip()
FILTER_METHOD = os.environ.get('CAPTURE_FILTER_METHOD', '').strip().upper()
CAPTURE_FILE = os.environ.get('CAPTURE_FILE', '').strip()


def _headers_dict(parser: HttpParser) -> dict:
    if not parser.headers:
        return {}
    out = {}
    for k in parser.headers:
        name, value = parser.headers[k]
        out[text_(name)] = text_(value)
    return out


def _decompress(body: bytes, encoding: str) -> bytes:
    """Descomprime o body de acordo com o Content-Encoding, se possivel.
    Em qualquer erro (encoding desconhecido, dados parciais, etc.) devolve o
    body original - a captura nunca deve quebrar por causa disso."""
    encoding = (encoding or '').lower()
    try:
        if encoding == 'gzip':
            return gzip.decompress(body)
        if encoding == 'deflate':
            try:
                return zlib.decompress(body)
            except zlib.error:
                return zlib.decompress(body, -zlib.MAX_WBITS)
        if encoding == 'br':
            import brotli
            return brotli.decompress(body)
    except Exception:
        pass
    return body


def _header_ci(headers: dict, name: str) -> str:
    name = name.lower()
    for k, v in headers.items():
        if k.lower() == name:
            return v
    return ''


def _dechunk(raw: bytes) -> bytes:
    """Remonta um body chunked na mao. Usado como fallback quando o parser do
    proxy.py nao consegue (ex: servidor fecha a conexao logo apos o ultimo
    chunk, sem seguir o Transfer-Encoding a risca)."""
    out = bytearray()
    i, n = 0, len(raw)
    while i < n:
        j = raw.find(b'\r\n', i)
        if j == -1:
            break
        size_line = raw[i:j].split(b';', 1)[0].strip()
        try:
            size = int(size_line, 16)
        except ValueError:
            break
        if size == 0:
            break
        start = j + 2
        out += raw[start:start + size]
        i = start + size + 2
    return bytes(out)


def _dechunk_from_raw_response(raw: bytes) -> bytes:
    sep = raw.find(b'\r\n\r\n')
    if sep == -1:
        return b''
    return _dechunk(raw[sep + 4:])


def _decode_body(body: Optional[bytes]) -> dict:
    if not body:
        return {'encoding': None, 'data': None, 'truncated': False}
    truncated = len(body) > MAX_BODY_LEN
    chunk = body[:MAX_BODY_LEN]
    try:
        return {
            'encoding': 'text',
            'data': chunk.decode('utf-8'),
            'truncated': truncated,
        }
    except UnicodeDecodeError:
        import base64
        return {
            'encoding': 'base64',
            'data': base64.b64encode(chunk).decode('ascii'),
            'truncated': truncated,
        }


class CapturePlugin(HttpProxyBasePlugin):
    """Grava request/response completos em um arquivo .jsonl."""

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self._req: Optional[HttpParser] = None
        self._req_ts: float = 0.0
        self._is_https: bool = False
        self._resp_buf = bytearray()

    def handle_client_request(self, request: HttpParser) -> Optional[HttpParser]:
        if request.method == b'CONNECT':
            return request
        self._req = request
        self._req_ts = time.time()
        try:
            self._is_https = isinstance(self.client.connection, ssl.SSLSocket)
        except Exception:
            self._is_https = False
        return request

    def handle_upstream_chunk(self, chunk: memoryview):
        if self._req is not None:
            self._resp_buf += chunk.tobytes()
        return chunk

    def _passes_filter(self, host: str, method: str) -> bool:
        if FILTER_DOMAIN and FILTER_DOMAIN not in host:
            return False
        if FILTER_METHOD and FILTER_METHOD != method:
            return False
        return True

    def on_upstream_connection_close(self) -> None:
        if self._req is None:
            return
        req = self._req
        headers = _headers_dict(req)
        host = text_(req.host) if req.host else headers.get('Host', headers.get('host', ''))
        if ':' in host:
            host = host.split(':', 1)[0]
        method = text_(req.method) if req.method else ''
        path = text_(req.path) if req.path else '/'

        if not self._passes_filter(host, method):
            self._req = None
            self._resp_buf = bytearray()
            return

        req_body = req.body
        if req_body:
            req_body = _decompress(req_body, headers.get('Content-Encoding', ''))

        record = {
            'ts': self._req_ts,
            'method': method,
            'host': host,
            'port': 443 if self._is_https else (req.port or 80),
            'path': path,
            'url': 'http%s://%s%s' % (
                's' if self._is_https else '', host, path,
            ),
            'request': {
                'headers': headers,
                'body': _decode_body(req_body),
            },
            'response': None,
        }

        if self._resp_buf:
            try:
                raw_resp = bytes(self._resp_buf)
                resp = HttpParser.response(raw_resp)
                resp_headers = _headers_dict(resp)
                resp_body = resp.body
                if not resp_body and _header_ci(resp_headers, 'Transfer-Encoding').lower() == 'chunked':
                    resp_body = _dechunk_from_raw_response(raw_resp)
                if resp_body:
                    resp_body = _decompress(resp_body, resp_headers.get('Content-Encoding', ''))
                record['response'] = {
                    'status': int(resp.code) if resp.code else None,
                    'headers': resp_headers,
                    'body': _decode_body(resp_body),
                }
            except Exception as e:  # parser e' best-effort; nunca derruba a captura
                record['response'] = {'parse_error': str(e)}

        line = json.dumps(record, ensure_ascii=False)
        if CAPTURE_FILE:
            with open(CAPTURE_FILE, 'a', encoding='utf-8') as f:
                f.write(line + '\n')

        status = record['response']['status'] if record['response'] and 'status' in record['response'] else '-'
        print('%s %s -> %s' % (method, record['url'], status))
        if DETAIL >= 1:
            print('  req headers:', record['request']['headers'])
            if record['response']:
                print('  resp headers:', record['response'].get('headers'))
        if DETAIL >= 2:
            if record['request']['body']['data']:
                print('  req body:', record['request']['body']['data'][:2000])
            if record['response'] and record['response'].get('body', {}).get('data'):
                print('  resp body:', record['response']['body']['data'][:2000])

        self._req = None
        self._resp_buf = bytearray()
