#!/usr/bin/env python3
"""Download the three assigned dashboards and bind their Prometheus datasource."""
import json
import re
from pathlib import Path
from urllib.request import urlopen

target = Path(__file__).resolve().parents[1] / 'grafana' / 'dashboards'
target.mkdir(parents=True, exist_ok=True)
# 11003 in the handout currently resolves to an unrelated Metasploit board.
# 19908 is the catalogue's cAdvisor Docker Insights template.
for dashboard_id in (1860, 19908, 9628):
    url = f'https://grafana.com/api/dashboards/{dashboard_id}/revisions/latest/download'
    with urlopen(url, timeout=60) as response:
        dashboard = json.load(response)
    # The catalogue's import wizard normally substitutes __inputs. File
    # provisioning must do that before writing JSON to disk.
    raw = json.dumps(dashboard)
    for item in dashboard.get('__inputs', []):
        if item.get('pluginId') == 'prometheus':
            raw = raw.replace('${' + item['name'] + '}', 'prometheus')
    raw = re.sub(r'\$\{DS_PROMETHEUS[^}]*\}', 'prometheus', raw)
    dashboard = json.loads(raw)
    dashboard.pop('__inputs', None)
    if dashboard_id == 9628:
        # The catalogue template assumes Kubernetes release/namespace labels.
        # This deployment uses Compose and a stable release label instead.
        variables = dashboard.get('templating', {}).get('list', [])
        dashboard['templating']['list'] = [v for v in variables if v['name'] != 'namespace']
        for variable in dashboard['templating']['list']:
            if variable['name'] == 'release':
                variable.update(query='label_values(pg_up, release)', regex='', current={})
    dashboard['id'] = None
    dashboard['uid'] = f'course-{dashboard_id}'
    (target / f'{dashboard_id}.json').write_text(
        json.dumps(dashboard, ensure_ascii=False, indent=2) + '\n')
    print(f'{dashboard_id}: {dashboard["title"]}, revision {dashboard.get("version")}')
