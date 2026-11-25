#!/usr/bin/env python3
"""Shared local helpers; dotenv values are read as data, never executed."""
import os
from pathlib import Path


def load_env():
    root = Path(__file__).resolve().parents[1]
    file = root / '.env'
    if file.exists():
        for line in file.read_text().splitlines():
            if '=' in line and not line.lstrip().startswith('#'):
                key, value = line.split('=', 1)
                os.environ.setdefault(key, value)
    return root


def state_dir(name):
    base = Path(os.environ.get('PRACTICE_HOME', str(Path.home() / 'Library/Application Support/DevOpsPractices')))
    directory = base / 'state' / name
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    return directory
