#!/usr/bin/env python3
"""Deliver a Grafana test, stop the lab DB, and verify Firing plus Resolved."""
import base64
import importlib.util
import json
import os
import subprocess
import time
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('mattermost', ROOT / 'migration/mattermost-data.py')
mm = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mm)


def posts():
    baseline = json.loads((mm.state / 'baseline.json').read_text())
    data, _ = mm.api('GET', '/channels/' + baseline['ops_channel_id'] + '/posts?per_page=100')
    return list(data['posts'].values())


def wait_message(after_ms, predicate, limit):
    deadline = time.monotonic() + limit
    while time.monotonic() < deadline:
        found = [p for p in posts() if p['create_at'] >= after_ms and predicate(json.dumps(p, ensure_ascii=False))]
        if found:
            return min(found, key=lambda p: p['create_at'])
        time.sleep(2)
    raise TimeoutError('Mattermost did not receive the expected Grafana notification in time')


def main():
    mm.login()
    webhook = (mm.state / 'webhook-url').read_text().strip()
    auth = base64.b64encode(('admin:' + os.environ['GRAFANA_PASSWORD']).encode()).decode()
    receiver = {'uid': 'mattermost', 'name': 'Mattermost', 'type': 'slack', 'settings': {'url': webhook}}
    body = {'receivers': [{'name': 'Mattermost', 'grafana_managed_receiver_configs': [receiver]}]}
    test_at = int(time.time() * 1000)
    request = Request('http://127.0.0.1:3000/api/alertmanager/grafana/config/api/v1/receivers/test',
                      data=json.dumps(body).encode(), method='POST',
                      headers={'Authorization': 'Basic ' + auth, 'Content-Type': 'application/json'})
    try:
        with urlopen(request, timeout=30) as response:
            result = json.load(response)
    except HTTPError as error:
        message = error.read().decode().replace(webhook, '***').replace(webhook.rsplit('/', 1)[-1], '***')
        raise RuntimeError(f'Grafana contact point test failed: HTTP {error.code}: {message}') from None
    test = wait_message(test_at, lambda text: 'TestAlert' in text, 30)
    print('PASS: Grafana native contact point test delivered to Mattermost', flush=True)
    stopped_at = int(time.time() * 1000)
    try:
        subprocess.run(['docker', 'stop', '--time', '30', 'app-db'], check=True, stdout=subprocess.DEVNULL)
        firing = wait_message(stopped_at, lambda text: 'Application PostgreSQL down' in text and 'FIRING' in text.upper(), 120)
        print(f'PASS: Firing received in {(firing["create_at"] - stopped_at) / 1000:.1f} seconds', flush=True)
    finally:
        restored_at = int(time.time() * 1000)
        subprocess.run(['docker', 'start', 'app-db'], check=True, stdout=subprocess.DEVNULL)
    resolved = wait_message(restored_at, lambda text: 'Application PostgreSQL down' in text and 'RESOLVED' in text.upper(), 120)
    print(f'PASS: Resolved received in {(resolved["create_at"] - restored_at) / 1000:.1f} seconds', flush=True)
    evidence = {
        'test_at': test_at, 'stopped_at': stopped_at, 'restored_at': restored_at,
        'firing_delay_seconds': (firing['create_at'] - stopped_at) / 1000,
        'resolved_delay_seconds': (resolved['create_at'] - restored_at) / 1000,
        'test_post': test, 'firing_post': firing, 'resolved_post': resolved,
    }
    directory = ROOT / 'evidence/practice6'
    directory.mkdir(parents=True, exist_ok=True)
    text = json.dumps(evidence, ensure_ascii=False, indent=2).replace(webhook, '***').replace(webhook.rsplit('/', 1)[-1], '***')
    (directory / 'alerts.json').write_text(text + '\n')
    assert evidence['firing_delay_seconds'] <= 120
    assert evidence['resolved_delay_seconds'] <= 120


if __name__ == '__main__':
    main()
