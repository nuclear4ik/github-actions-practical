#!/usr/bin/env python3
"""Install checksum-pinned official GitHub CLI and runner for either Mac CPU."""
import hashlib
import json
import os
import platform
import subprocess
from pathlib import Path
from urllib.request import urlopen


def main():
    if platform.system() != 'Darwin':
        raise SystemExit('This installer targets macOS.')
    state = Path(os.environ.get('PRACTICE_HOME', str(Path.home() / 'Library/Application Support/DevOpsPractices')))
    metadata = json.loads(Path(__file__).with_name('tools.json').read_text())
    cpu = platform.machine()
    if cpu not in ('arm64', 'x86_64'):
        raise SystemExit(f'Unsupported Mac CPU: {cpu}')
    for directory in ('cache', 'tools', 'bin', 'runner'):
        (state / directory).mkdir(parents=True, exist_ok=True)
    for tool in ('gh', 'runner'):
        item = metadata[tool]['assets'][cpu]
        archive = state / 'cache' / item['url'].split('/')[-1]
        if not archive.exists():
            print(f'Downloading {tool} {metadata[tool]["version"]}', flush=True)
            partial = archive.with_suffix(archive.suffix + '.partial')
            with urlopen(item['url'], timeout=120) as response, partial.open('wb') as output:
                while True:
                    block = response.read(1024 * 1024)
                    if not block:
                        break
                    output.write(block)
            partial.replace(archive)
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        if digest != item['sha256']:
            raise SystemExit(f'Checksum mismatch: {archive}; remove it and retry.')
        if tool == 'gh':
            folder = state / 'tools' / archive.stem
            if not folder.exists():
                subprocess.run(['/usr/bin/unzip', '-q', str(archive), '-d', str(state / 'tools')], check=True)
            link = state / 'bin/gh'
            if link.is_symlink():
                link.unlink()
            elif link.exists():
                raise SystemExit(f'Refusing to overwrite existing non-symlink: {link}')
            link.symlink_to(folder / 'bin/gh')
        elif not (state / 'runner/config.sh').exists():
            subprocess.run(['/usr/bin/tar', '-xzf', str(archive), '-C', str(state / 'runner')], check=True)
            (state / 'runner/.distribution-version').write_text(metadata[tool]['version'] + '\n')
        print(f'{tool}: installed; SHA256 verified')
    subprocess.run([str(state / 'bin/gh'), '--version'], check=True)


if __name__ == '__main__':
    main()
