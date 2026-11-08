#!/usr/bin/env python3
"""Read-only local provider bridge. Never creates model turns or conversations."""
import argparse
import datetime as dt
import json
import math
import os
from pathlib import Path
import selectors
import shutil
import subprocess
import tempfile
import time
import urllib.request
from urllib.parse import urlsplit


def percentage(value, scale=1):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError('Invalid quota percentage')
    result = value * scale
    if not math.isfinite(result) or not 0 <= result <= 100:
        raise ValueError('Invalid quota percentage')
    return round(100 - result, 2)


def codex_windows(result):
    buckets = result.get('rateLimitsByLimitId')
    if not isinstance(buckets, dict) or not buckets:
        buckets = {'codex': result.get('rateLimits', {})}
    windows = []
    for bucket_id, bucket in buckets.items():
        if not isinstance(bucket, dict):
            raise ValueError('Invalid quota bucket')
        for kind in ('primary', 'secondary'):
            item = bucket.get(kind)
            if not isinstance(item, dict) or item.get('usedPercent') is None:
                continue
            duration = item.get('windowDurationMins')
            label = f'{bucket.get("limitName") or bucket_id} — {kind}'
            if isinstance(duration, (int, float)) and not isinstance(duration, bool) and duration > 0:
                label += f' ({duration:g} min)'
            reset = item.get('resetsAt')
            if reset is not None:
                if isinstance(reset, bool) or not isinstance(reset, (int, float)):
                    raise ValueError('Invalid reset time')
                reset = dt.datetime.fromtimestamp(reset, dt.timezone.utc).isoformat()
            windows.append({'id': f'{bucket_id}:{kind}', 'label': label,
                            'remainingPercent': percentage(item['usedPercent']), 'resetsAt': reset})
    return windows


def kimi_windows(envelope):
    if envelope.get('code') != 0:
        raise ValueError('Kimi server rejected usage request')
    data = envelope.get('data', {})
    if data.get('kind') != 'ok':
        raise ValueError('Kimi account usage unavailable')
    usages = data.get('quota', {}).get('usages', {})
    if not isinstance(usages, dict):
        raise ValueError('Invalid Kimi quota')
    labels = {'limit5h': '5-hour allowance', 'limit7d': '7-day allowance',
              'monthTotal': 'Monthly total allowance', 'monthCode': 'Monthly code allowance'}
    windows = []
    for key, item in usages.items():
        if not isinstance(item, dict) or item.get('usedRatio') is None:
            continue
        reset = item.get('resetAt')
        if reset is not None:
            dt.datetime.fromisoformat(reset.replace('Z', '+00:00'))
        windows.append({'id': key, 'label': labels.get(key, key),
                        'remainingPercent': percentage(item['usedRatio'], 100), 'resetsAt': reset})
    return windows


def read_codex(executable):
    # One bounded process owns a private stdio transport; stderr is never exported.
    process = subprocess.Popen([executable, 'app-server', '--stdio'], stdin=subprocess.PIPE,
                               stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ)
    buffer = b''
    deadline = time.monotonic() + 15
    def send(message):
        process.stdin.write(json.dumps(message).encode() + b'\n')
        process.stdin.flush()
    def receive(request_id):
        nonlocal buffer
        while time.monotonic() < deadline:
            while b'\n' in buffer:
                line, buffer = buffer.split(b'\n', 1)
                message = json.loads(line)
                if message.get('id') == request_id:
                    if 'error' in message:
                        raise ValueError('Codex account read failed')
                    return message['result']
            events = selector.select(max(0, deadline-time.monotonic()))
            if not events:
                break
            chunk = os.read(process.stdout.fileno(), 65536)
            if not chunk:
                raise ValueError('Codex disconnected')
            buffer += chunk
            if len(buffer) > 1048576:
                raise ValueError('Codex response too large')
        raise TimeoutError('Codex usage request timed out')
    try:
        send({'id': 1, 'method': 'initialize', 'params': {'clientInfo': {
            'name': 'keepingyouawake_usage', 'version': '0.1.0'}}})
        receive(1)
        send({'method': 'initialized'})
        send({'id': 2, 'method': 'account/rateLimits/read'})
        return codex_windows(receive(2))
    finally:
        selector.close()
        process.terminate()
        try:
            process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
        process.stdin.close()
        process.stdout.close()


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise ValueError('Usage endpoint redirects are not allowed')


def read_kimi(base_url, token_path):
    url = urlsplit(base_url)
    if url.scheme != 'http' or url.hostname not in ('127.0.0.1', 'localhost', '::1') or url.username or url.password or url.query or url.fragment or url.path not in ('', '/'):
        raise ValueError('Kimi URL must be a plain loopback HTTP origin')
    token = Path(token_path).expanduser().read_text().strip()
    if not token or '\n' in token or '\r' in token:
        raise ValueError('Invalid local server token')
    request = urllib.request.Request(base_url.rstrip('/') + '/api/v1/oauth/usage',
                                     headers={'Authorization': 'Bearer ' + token})
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
    with opener.open(request, timeout=10) as response:
        raw = response.read(1048577)
        if len(raw) > 1048576:
            raise ValueError('Kimi response too large')
        return kimi_windows(json.loads(raw))


def read_managed_kimi():
    executable = shutil.which('kimi')
    if executable is None:
        executable = next((str(p) for p in [Path.home()/'.kimi-code/bin/kimi', Path('/opt/homebrew/bin/kimi'), Path('/usr/local/bin/kimi')] if p.is_file()), None)
    if executable is None:
        raise ValueError('Kimi CLI is not installed')
    base = 'http://127.0.0.1:58627'
    token = Path.home()/'.kimi-code/server.token'
    # Reuse a local CLI server when available; never shut down another client's server.
    try:
        return read_kimi(base, token)
    except (OSError, ValueError):
        pass
    # Start a private server on a dynamically allocated loopback port.
    import socket
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        port = sock.getsockname()[1]
    process = subprocess.Popen([executable, 'web', '--no-open', '--host', '127.0.0.1', '--port', str(port)],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        deadline = time.monotonic()+12
        while time.monotonic() < deadline:
            if process.poll() is not None:
                raise ValueError('Kimi server could not start')
            try:
                return read_kimi(f'http://127.0.0.1:{port}', token)
            except (OSError, ValueError):
                time.sleep(.25)
        raise TimeoutError('Kimi server startup timed out')
    finally:
        process.terminate()
        try:
            process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()


def snapshot(provider, reader):
    now = dt.datetime.now(dt.timezone.utc).isoformat()
    try:
        windows = reader()
        return {'provider': provider, 'fetchedAt': now,
                'state': 'fresh' if windows else 'unavailable', 'windows': windows}
    except Exception:
        # Raw provider errors can contain credentials or account details.
        return {'provider': provider, 'fetchedAt': now, 'state': 'unavailable',
                'message': 'Usage unavailable; check CLI login and bridge configuration.', 'windows': []}


def write_snapshot(folder, data):
    folder.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd, name = tempfile.mkstemp(prefix='.usage-', dir=folder)
    try:
        with os.fdopen(fd, 'w') as stream:
            json.dump(data, stream, allow_nan=False)
        os.replace(name, folder/'usage.json')
    finally:
        if os.path.exists(name):
            os.unlink(name)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, help='Dedicated snapshot directory selected in the app')
    parser.add_argument('--codex', default=shutil.which('codex'), help='Path to official Codex CLI')
    parser.add_argument('--kimi-url', help='Origin of an already-running local kimi web server')
    parser.add_argument('--kimi-token-file', type=Path, help='File containing that local server bearer token')
    parser.add_argument('--interval', type=int, default=0, help='Repeat every N seconds (minimum 60); default runs once')
    parser.add_argument('--stdout', action='store_true', help='Return one snapshot over private helper IPC')
    parser.add_argument('--no-codex', action='store_true')
    parser.add_argument('--auto-kimi', action='store_true')
    args = parser.parse_args()
    if not args.stdout and args.output is None:
        parser.error('--output or --stdout is required')
    if args.stdout and args.interval:
        parser.error('--stdout is a single request')
    if args.no_codex:
        args.codex = None
    elif args.codex is None:
        candidates = [Path.home()/'.local/bin/codex', Path('/opt/homebrew/bin/codex'), Path('/usr/local/bin/codex')]
        args.codex = next((str(p) for p in candidates if p.is_file()), None)

    if args.interval and args.interval < 60:
        parser.error('--interval must be at least 60')
    if bool(args.kimi_url) != bool(args.kimi_token_file):
        parser.error('--kimi-url and --kimi-token-file must be supplied together')
    while True:
        providers = []
        if args.codex:
            providers.append(snapshot('Codex', lambda: read_codex(args.codex)))
        else:
            providers.append({'provider': 'Codex', 'state': 'notConnected', 'windows': []})
        if args.auto_kimi:
            providers.append(snapshot('Kimi Code', read_managed_kimi))
        elif args.kimi_url:
            providers.append(snapshot('Kimi Code', lambda: read_kimi(args.kimi_url, args.kimi_token_file)))
        else:
            providers.append({'provider': 'Kimi Code', 'state': 'notConnected', 'windows': []})
        document = {'schemaVersion': 1, 'providers': providers}
        if args.stdout:
            print(json.dumps(document, allow_nan=False))
            return
        write_snapshot(args.output.expanduser(), document)
        print('Updated usage snapshot.', flush=True)
        if not args.interval:
            break
        time.sleep(args.interval)


if __name__ == '__main__':
    import signal
    def stop(signum, frame):
        raise SystemExit(0)
    signal.signal(signal.SIGTERM, stop)
    main()
