#!/usr/bin/env python3
"""Seed real test data, verify it after migration, and create the alert webhook."""
import hashlib
import importlib.util
import json
import os
import struct
import sys
import uuid
import zlib
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen

spec = importlib.util.spec_from_file_location('labenv', Path(__file__).resolve().parents[1] / 'scripts/lab-env.py')
labenv = importlib.util.module_from_spec(spec)
spec.loader.exec_module(labenv)
root = labenv.load_env()
state = labenv.state_dir('mattermost')
BASE = os.environ.get('MM_URL', 'http://127.0.0.1:8065')
token = None


def api(method, path, data=None, multipart=None, raw=False):
    headers = {}
    if token:
        headers['Authorization'] = 'Bearer ' + token
    body = None
    if multipart:
        field, filename, content_type, value = multipart
        boundary = uuid.uuid4().hex
        headers['Content-Type'] = 'multipart/form-data; boundary=' + boundary
        body = (f'--{boundary}\r\nContent-Disposition: form-data; name="{field}"; filename="{filename}"\r\nContent-Type: {content_type}\r\n\r\n'.encode() + value + f'\r\n--{boundary}--\r\n'.encode())
    elif data is not None:
        headers['Content-Type'] = 'application/json'
        body = json.dumps(data, ensure_ascii=False).encode()
    with urlopen(Request(BASE + '/api/v4' + path, data=body, headers=headers, method=method), timeout=30) as response:
        content = response.read()
        if raw:
            return content
        return (json.loads(content) if content else None), response.headers


def login():
    global token
    user, headers = api('POST', '/users/login', {'login_id': os.environ['MM_ADMIN_USER'], 'password': os.environ['MM_ADMIN_PASSWORD']})
    token = headers['Token']
    return user


def avatar():
    def chunk(kind, data):
        return struct.pack('!I', len(data)) + kind + data + struct.pack('!I', zlib.crc32(kind + data))
    rows = bytearray()
    for y in range(64):
        rows.append(0)
        for x in range(64):
            white = (12 <= x < 18 and 12 <= y < 52) or (30 <= x < 52 and 12 <= y < 18) or (38 <= x < 44 and 12 <= y < 52)
            rows.extend((255, 255, 255) if white else (35, 84, 145))
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('!IIBBBBB', 64, 64, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(rows)) + chunk(b'IEND', b'')


def seed():
    baseline_file = state / 'baseline.json'
    if baseline_file.exists():
        verify()
        return
    try:
        user = login()
    except HTTPError as error:
        if error.code not in (400, 401, 404):
            raise
        api('POST', '/users', {
            'email': os.environ['MM_ADMIN_EMAIL'], 'username': os.environ['MM_ADMIN_USER'],
            'password': os.environ['MM_ADMIN_PASSWORD'], 'first_name': 'Илья', 'last_name': 'Толмачев',
        })
        user = login()
    api('POST', f'/users/{user["id"]}/image', multipart=('image', 'avatar.png', 'image/png', avatar()))
    team, _ = api('POST', '/teams', {'name': 'devops-lab', 'display_name': 'Практики DevOps', 'type': 'I'})
    channel, _ = api('POST', '/channels', {'team_id': team['id'], 'name': 'migration-proof', 'display_name': 'Проверка миграции', 'type': 'P'})
    ops, _ = api('POST', '/channels', {'team_id': team['id'], 'name': 'ops-alerts', 'display_name': 'Оповещения мониторинга', 'type': 'O'})
    attachment = 'Практика 4. Контрольное вложение Толмачева Ильи. Данные должны сохраниться.\n'.encode()
    files, _ = api('POST', '/files?channel_id=' + channel['id'], multipart=('files', 'migration-proof.txt', 'text/plain', attachment))
    file_id = files['file_infos'][0]['id']
    messages = [
        'Сообщение 1. Mattermost 9.5 работает с MySQL 8.0.',
        'Сообщение 2. Приватный канал создан до миграции.',
        'Сообщение 3. Проверка кириллицы: данные Толмачева Ильи.',
        'Сообщение 4. После переноса должны сохраниться пользователи и сообщения.',
        'Сообщение 5. Контрольное вложение перед обновлением до 12.0.1.',
    ]
    posts = []
    for i, message in enumerate(messages):
        data = {'channel_id': channel['id'], 'message': message}
        if i == 4:
            data['file_ids'] = [file_id]
        post, _ = api('POST', '/posts', data)
        posts.append({'id': post['id'], 'message': message})
    baseline = {
        'user_id': user['id'], 'team_id': team['id'], 'channel_id': channel['id'], 'ops_channel_id': ops['id'],
        'posts': posts, 'file_id': file_id, 'attachment_sha256': hashlib.sha256(attachment).hexdigest(),
        'avatar_sha256': hashlib.sha256(api('GET', f'/users/{user["id"]}/image', raw=True)).hexdigest(),
    }
    baseline_file.write_text(json.dumps(baseline, ensure_ascii=False, indent=2) + '\n')
    print('Created administrator, team, private channel, 5 messages, attachment and avatar')
    verify()


def verify():
    baseline = json.loads((state / 'baseline.json').read_text())
    user = login()
    assert user['id'] == baseline['user_id'], 'User ID changed'
    channel, _ = api('GET', '/channels/' + baseline['channel_id'])
    assert channel['type'] == 'P', 'Private channel type changed'
    posts, _ = api('GET', '/channels/' + baseline['channel_id'] + '/posts?per_page=100')
    for expected in baseline['posts']:
        assert posts['posts'][expected['id']]['message'] == expected['message'], 'Message changed'
    for path, key in [('/files/' + baseline['file_id'], 'attachment_sha256'), ('/users/' + user['id'] + '/image', 'avatar_sha256')]:
        assert hashlib.sha256(api('GET', path, raw=True)).hexdigest() == baseline[key], key + ' differs'
    evidence = root / 'evidence/practice4'
    evidence.mkdir(parents=True, exist_ok=True)
    (evidence / 'baseline.json').write_text(json.dumps(baseline, ensure_ascii=False, indent=2) + '\n')
    print('PASS: user ID, private channel, 5 original post IDs/texts, attachment SHA256 and avatar SHA256 preserved')


def webhook():
    login()
    baseline = json.loads((state / 'baseline.json').read_text())
    hooks, _ = api('GET', '/hooks/incoming?per_page=200')
    hook = next((h for h in hooks if h['channel_id'] == baseline['ops_channel_id']), None)
    if hook is None:
        hook, _ = api('POST', '/hooks/incoming', {'channel_id': baseline['ops_channel_id'], 'display_name': 'Grafana', 'description': 'Practice 6 monitoring alerts'})
    url = 'http://mattermost:8065/hooks/' + hook['id']
    # Store privately. The webhook token permits posting and must not be logged.
    file = state / 'webhook-url'
    fd = os.open(file, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, 'w') as stream:
        stream.write(url)
    print('Mattermost ops-alerts incoming webhook created; URL stored privately')


if __name__ == '__main__':
    action = sys.argv[1] if len(sys.argv) > 1 else 'verify'
    {'seed': seed, 'verify': verify, 'webhook': webhook}[action]()
