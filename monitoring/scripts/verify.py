#!/usr/bin/env python3
"""Fail unless all four targets, database metrics and three dashboards are live."""
import base64
import json
import os
import time
from urllib.parse import urlencode
from urllib.request import Request, urlopen


def get(url, authenticated=False):
    headers = {}
    if authenticated:
        password = os.environ['GRAFANA_PASSWORD']
        headers['Authorization'] = 'Basic ' + base64.b64encode(
            f'admin:{password}'.encode()).decode()
    with urlopen(Request(url, headers=headers), timeout=10) as response:
        return json.load(response)


def verify():
    targets = get('http://127.0.0.1:9090/api/v1/targets')['data']['activeTargets']
    expected = {'prometheus', 'node', 'cadvisor', 'postgres'}
    assert len(targets) == 4, f'Expected 4 targets; got {len(targets)}'
    assert {t['labels']['job'] for t in targets} == expected, 'Unexpected scrape jobs'
    assert all(t['health'] == 'up' for t in targets), 'Not all targets are UP'
    # A running exporter can still report database failure (pg_up == 0).
    query = urlencode({'query': 'pg_up{job="postgres"}'})
    result = get('http://127.0.0.1:9090/api/v1/query?' + query)['data']['result']
    assert result and all(float(r['value'][1]) == 1 for r in result), 'Database is unavailable'
    assert get('http://127.0.0.1:3000/api/health')['database'] == 'ok'
    dashboards = get('http://127.0.0.1:3000/api/search?type=dash-db', True)
    assert {f'course-{i}' for i in (1860, 19908, 9628)} <= {d['uid'] for d in dashboards}, 'Missing assigned dashboards'
    for t in targets:
        print(f'{t["labels"]["job"]}: {t["health"]}')
    print('pg_up: 1; Grafana database: ok; dashboards: 1860, 19908, 9628')


if __name__ == '__main__':
    last = None
    for attempt in range(30):
        try:
            verify()
            break
        except Exception as error:
            last = error
            time.sleep(5)
    else:
        raise SystemExit(f'Monitoring verification failed: {last}')
