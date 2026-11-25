#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
# The package is amd64 even when the self-hosted runner is Apple Silicon.
VERSION=$(sed -n 's/^const Version = "\([0-9.]*\)"$/\1/p' main.go)
test -n "$VERSION"
test -s ../nexus/public.gpg
docker run --rm --platform linux/amd64 --network nexus_net \
  -e "EXPECTED_VERSION=$VERSION" \
  -v "$PWD/../nexus/public.gpg:/usr/share/keyrings/syspulse.gpg:ro" \
  ubuntu:22.04 bash -euc '
    export DEBIAN_FRONTEND=noninteractive
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/syspulse.gpg] http://nexus:8081/repository/syspulse/ stable main" > /etc/apt/sources.list.d/syspulse.list
    apt-get update
    apt-get install -y --no-install-recommends "syspulse=$EXPECTED_VERSION"
    dpkg -s syspulse | sed -n "/^Package:/p; /^Version:/p; /^Architecture:/p"
    test "$(syspulse --version)" = "syspulse $EXPECTED_VERSION"
    syspulse
  '
