"""Download a validated character ZIP from a get_character MCP receipt (Python 3.11+)."""

import argparse
import io
import json
import re
import sys
import tempfile
import tomllib
import urllib.error
import urllib.request
import zipfile
from pathlib import Path


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args):
        return None


def download(receipt_path, output_path, config_path):
    receipt = json.loads(receipt_path.read_text())
    result = receipt['result']
    if receipt.get('tool') != 'get_character' or receipt.get('status') != 'returned' or result.get('isError'):
        raise ValueError('Expected a returned get_character receipt without a tool error')
    text = '\n'.join(item['text'] for item in result['content'] if item.get('type') == 'text')
    urls = re.findall(r'^download: (https://api\.pixellab\.ai/mcp/characters/[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}/download)\s*$', text, re.M)
    if len(urls) != 1:
        raise ValueError('Receipt must contain exactly one official character download URL')
    opener = urllib.request.build_opener(NoRedirect())
    try:
        response = opener.open(urllib.request.Request(urls[0]), timeout=60)
    except urllib.error.HTTPError as error:
        if error.code not in (401, 403):
            raise
        error.close()
        server = tomllib.loads(config_path.read_text())['mcp_servers']['pixellab']
        if server.get('url') != 'https://api.pixellab.ai/mcp' or not server.get('enabled', True):
            raise ValueError('Expected the enabled official PixelLab MCP server')
        response = opener.open(urllib.request.Request(urls[0], headers=server.get('http_headers', {})), timeout=60)
    with response:
        data = response.read()
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        if archive.testzip() is not None:
            raise ValueError('ZIP checksum validation failed')
        json.loads(archive.read('metadata.json'))
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=output_path.parent, suffix='.tmp', delete=False) as output:
        temporary = Path(output.name)
        try:
            output.write(data)
            output.flush()
            temporary.replace(output_path)
        finally:
            temporary.unlink(missing_ok=True)
    return len(data)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--receipt', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--config', type=Path, default=Path.home() / '.codex/config.toml')
    options = parser.parse_args()
    try:
        print('Saved validated ZIP:', options.output, 'bytes:', download(options.receipt, options.output, options.config))
    except Exception as error:
        detail = str(error.code) if isinstance(error, urllib.error.HTTPError) else type(error).__name__
        print('Download failed:', detail, file=sys.stderr)
        sys.exit(1)
