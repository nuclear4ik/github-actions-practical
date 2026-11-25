#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${NEXUS_HOST:?Set NEXUS_HOST without scheme or port}"
: "${NEXUS_USER:?Set NEXUS_USER}"
: "${NEXUS_PASSWORD:?Set NEXUS_PASSWORD}"
VERSION=$(sed -n 's/^const Version = "\([0-9.]*\)"$/\1/p' main.go)
DEB="dist/syspulse_${VERSION}_amd64.deb"
test -f "$DEB"
# Hosted APT accepts POST to the repository root and builds APT metadata.
# https://help.sonatype.com/en/apt-repositories.html
curl --fail --silent --show-error \
  --user "${NEXUS_USER}:${NEXUS_PASSWORD}" \
  -H 'Content-Type: multipart/form-data' \
  --data-binary "@$DEB" \
  "http://${NEXUS_HOST}:8081/repository/syspulse/"
echo "Published syspulse ${VERSION}"
