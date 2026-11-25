#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
# dpkg-deb runs in Debian, so the same build works on a macOS runner.
docker run --rm -v "$PWD:/src" -w /src golang:1.22-bookworm bash -euc '
  gofmt -d main.go > /tmp/gofmt.diff
  test ! -s /tmp/gofmt.diff
  go vet ./...
  VERSION=$(sed -n "s/^const Version = \"\([0-9.]*\)\"$/\1/p" main.go)
  test -n "$VERSION"
  ROOT="build/syspulse_${VERSION}"
  rm -rf "$ROOT"
  mkdir -p "$ROOT/DEBIAN" "$ROOT/usr/bin" dist
  GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -trimpath -buildvcs=false -ldflags="-s -w -buildid=" -o "$ROOT/usr/bin/syspulse" .
  chmod 755 "$ROOT/usr/bin/syspulse"
  cat > "$ROOT/DEBIAN/control" <<EOF
Package: syspulse
Version: ${VERSION}
Section: utils
Priority: optional
Architecture: amd64
Maintainer: Ilya Tolmachev <tir63@list.ru>
Description: Lightweight CLI tool for a system health snapshot
 Reads /proc and reports uptime, load average and memory info.
EOF
  # CGO_ENABLED=0: no libc dependency is needed.
  export SOURCE_DATE_EPOCH=1704067200
  find "$ROOT" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +
  dpkg-deb --build --root-owner-group "$ROOT" "dist/syspulse_${VERSION}_amd64.deb"
  dpkg-deb --info "dist/syspulse_${VERSION}_amd64.deb"
  dpkg-deb --contents "dist/syspulse_${VERSION}_amd64.deb"
  sha256sum "dist/syspulse_${VERSION}_amd64.deb" > dist/SHA256SUMS
'
