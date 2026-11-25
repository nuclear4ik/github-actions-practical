#!/usr/bin/env python3
"""Redact lab passwords and incoming-webhook tokens from diagnostic output."""
import os
import re
import sys

text = sys.stdin.read()
for key, value in os.environ.items():
    if value and ('PASSWORD' in key or 'WEBHOOK' in key or key in ('GH_TOKEN', 'GITHUB_TOKEN')):
        text = text.replace(value, '***')
text = re.sub(r'((?:postgres(?:ql)?|pgsql|mysql)://[^:@\s]+:)[^@\s]+@', r'\1***@', text)
text = re.sub(r'(https?://[^/\s]+/(?:api/v4/)?hooks/)[a-zA-Z0-9]+', r'\1***', text)
sys.stdout.write(text)
