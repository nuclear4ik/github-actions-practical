#!/usr/bin/env python3
"""Idempotent configuration of hosted APT, signing and a deploy-only Nexus user."""
import base64
import importlib.util
import json
import os
import subprocess
import sys
import time
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen

spec = importlib.util.spec_from_file_location('labenv', Path(__file__).resolve().parents[1] / 'scripts/lab-env.py')
labenv = importlib.util.module_from_spec(spec)
spec.loader.exec_module(labenv)
root = labenv.load_env()
state = labenv.state_dir('nexus')
key_dir = labenv.state_dir('nexus-key')


def main():
    password_file = state / 'admin-password'
    if password_file.exists():
        admin = password_file.read_text().strip()
    else:
        admin = subprocess.check_output(['docker', 'exec', 'nexus', 'cat', '/nexus-data/admin.password'], text=True).strip()
        fd = os.open(password_file, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, 'w') as f:
            f.write(admin)
    auth = base64.b64encode(('admin:' + admin).encode()).decode()

    def api(method, path, data=None):
        body = None if data is None else json.dumps(data).encode()
        headers = {'Authorization': 'Basic ' + auth, 'Content-Type': 'application/json'}
        request = Request('http://127.0.0.1:8081/service/rest/v1' + path, data=body, headers=headers, method=method)
        with urlopen(request, timeout=30) as response:
            result = response.read()
            return json.loads(result) if result else None

    for _ in range(60):
        try:
            api('GET', '/status')
            break
        except Exception:
            time.sleep(3)
    else:
        raise SystemExit('Nexus did not become ready')
    if '--accept-eula' in sys.argv:
        eula = api('GET', '/system/eula')
        if not eula['accepted']:
            eula['accepted'] = True
            api('POST', '/system/eula', eula)
            print('Nexus CE EULA accepted with explicit user authorization')
    repositories = api('GET', '/repositories')
    if not any(r['name'] == 'syspulse' for r in repositories):
        api('POST', '/repositories/apt/hosted', {
            'name': 'syspulse', 'online': True,
            'storage': {'blobStoreName': 'default', 'strictContentTypeValidation': True, 'writePolicy': 'ALLOW'},
            'apt': {'distribution': 'stable'},
            'aptSigning': {'keypair': (key_dir / 'private.asc').read_text(), 'passphrase': ''},
        })
    role = 'syspulse-deployer'
    roles = api('GET', '/security/roles')
    if not any(r['id'] == role for r in roles):
        api('POST', '/security/roles', {
            'id': role, 'name': 'SysPulse APT deployer', 'description': 'Publish and read only the lab APT repository',
            'privileges': ['nx-component-upload'] + [f'nx-repository-view-apt-syspulse-{p}' for p in ('add', 'edit', 'read', 'browse')],
            'roles': [],
        })
    user = os.environ['NEXUS_USER']
    users = api('GET', '/security/users')
    if not any(u['userId'] == user for u in users):
        api('POST', '/security/users', {
            'userId': user, 'firstName': 'Ilya', 'lastName': 'Tolmachev', 'emailAddress': 'tir63@list.ru',
            'password': os.environ['NEXUS_PASSWORD'], 'status': 'active', 'roles': [role],
        })
    api('PUT', '/security/anonymous', {'enabled': True, 'userId': 'anonymous', 'realmName': 'NexusAuthorizingRealm'})
    print('Nexus hosted APT syspulse: ready; distribution: stable; writePolicy: ALLOW')
    print('Dedicated deployer configured; metadata signing enabled')


if __name__ == '__main__':
    main()
