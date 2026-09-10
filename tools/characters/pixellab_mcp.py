"""Call the configured official PixelLab MCP server; Python 3.11+.

Credentials remain in the local Codex configuration. An exclusive receipt
claim prevents duplicate creation at the same path, including concurrent calls.
Uncertain submissions stay blocked; status queries must use a separate receipt.
"""

import argparse
import hashlib
import json
import sys
import tomllib
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path


READ_TOOLS = {'get_balance', 'get_character', 'list_jobs', 'list_characters'}
CREATE_TOOLS = {'create_character', 'animate_character'}


def save_json(path, value, exclusive=False):
    path.parent.mkdir(parents=True, exist_ok=True)
    if exclusive:
        with path.open('x') as output:
            output.write(json.dumps(value, ensure_ascii=False, indent=2) + '\n')
        return
    temporary = path.with_suffix(path.suffix + '.tmp')
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')
    temporary.replace(path)


class PixelLabMCP:
    def __init__(self, config_path):
        server = tomllib.loads(config_path.read_text())['mcp_servers']['pixellab']
        self.url = server.get('url')
        if self.url != 'https://api.pixellab.ai/mcp' or not server.get('enabled', True):
            raise ValueError('Expected the enabled official PixelLab MCP server')
        self.headers = dict(server.get('http_headers', {}))
        self.headers.update({'Content-Type': 'application/json', 'Accept': 'application/json, text/event-stream'})
        self.next_id = 0
        result = self.rpc('initialize', {
            'protocolVersion': '2025-03-26', 'capabilities': {},
            'clientInfo': {'name': 'guiliu-character-pipeline', 'version': '0.1'},
        })
        self.headers['MCP-Protocol-Version'] = result['protocolVersion']
        self.rpc('notifications/initialized', {}, notification=True)
        self.tool_schemas = {tool['name']: tool for tool in self.rpc('tools/list', {})['tools']}

    def rpc(self, method, params, notification=False):
        payload = {'jsonrpc': '2.0', 'method': method, 'params': params}
        self.next_id += 1
        if not notification:
            payload['id'] = self.next_id
        request = urllib.request.Request(self.url, data=json.dumps(payload).encode(), headers=self.headers)
        with urllib.request.urlopen(request, timeout=45) as response:
            session = response.headers.get('Mcp-Session-Id')
            if session:
                self.headers['Mcp-Session-Id'] = session
            if notification:
                return None
            if 'text/event-stream' in response.headers.get('Content-Type', ''):
                data, message = [], None
                for raw_line in response:
                    line = raw_line.decode().rstrip('\r\n')
                    if line.startswith('data:'):
                        data.append(line[5:].lstrip())
                    elif not line and data:
                        candidate = json.loads('\n'.join(data))
                        data = []
                        if candidate.get('id') == payload['id']:
                            message = candidate
                            break
                if message is None:
                    raise RuntimeError('MCP stream ended without the requested response')
            else:
                message = json.load(response)
        if 'error' in message:
            raise RuntimeError('MCP RPC failed: ' + str(message['error'].get('code')))
        return message['result']

    def call(self, name, arguments):
        if name not in self.tool_schemas:
            raise ValueError('Requested tool is not advertised by this MCP server')
        schema = self.tool_schemas[name]['inputSchema']
        if set(arguments) - set(schema['properties']):
            raise ValueError('Arguments contain unsupported fields')
        if set(schema.get('required', [])) - set(arguments):
            raise ValueError('Arguments are missing required fields')
        return self.rpc('tools/call', {'name': name, 'arguments': arguments})


def execute(client, name, arguments, receipt_path):
    request = {'tool': name, 'arguments': arguments}
    fingerprint = hashlib.sha256(json.dumps(request, sort_keys=True).encode()).hexdigest()
    receipt = {**request, 'fingerprint': fingerprint, 'submitted_at': datetime.now(timezone.utc).isoformat(), 'status': 'submitting'}
    try:
        save_json(receipt_path, receipt, exclusive=True)
    except FileExistsError:
        try:
            existing = json.loads(receipt_path.read_text())
        except json.JSONDecodeError as exc:
            raise RuntimeError('Receipt is incomplete. Check the pending submission; do not repeat creation') from exc
        if name in CREATE_TOOLS:
            if existing.get('fingerprint') != fingerprint:
                raise ValueError('Receipt belongs to a different request; choose a new candidate revision')
            if existing.get('status') == 'returned':
                return existing['result']
            raise RuntimeError('Submission is unresolved. Check remote jobs; do not repeat creation')
        if existing.get('tool') in CREATE_TOOLS:
            raise ValueError('Status queries must not overwrite a creation receipt; choose a separate query receipt')
        save_json(receipt_path, receipt)
    try:
        result = client.call(name, arguments)
    except Exception:
        receipt['status'] = 'submission_unknown'
        save_json(receipt_path, receipt)
        raise
    receipt.update(status='returned', result=result)
    save_json(receipt_path, receipt)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('tool', choices=sorted(READ_TOOLS | CREATE_TOOLS))
    parser.add_argument('--arguments', type=Path)
    parser.add_argument('--receipt', type=Path, required=True)
    parser.add_argument('--config', type=Path, default=Path.home() / '.codex/config.toml')
    options = parser.parse_args()
    arguments = json.loads(options.arguments.read_text()) if options.arguments else {}
    result = execute(PixelLabMCP(options.config), options.tool, arguments, options.receipt)
    for item in result.get('content', []):
        if item.get('type') == 'text':
            print(item['text'])
    if result.get('isError'):
        return 1
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except urllib.error.HTTPError as exc:
        print('MCP HTTP error:', exc.code, file=sys.stderr)
        sys.exit(1)
    except Exception as exc:
        print(type(exc).__name__ + ': ' + str(exc), file=sys.stderr)
        sys.exit(1)
