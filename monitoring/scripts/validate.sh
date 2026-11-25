#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
docker compose -f docker-compose.monitoring.yml config -q
# The Prometheus image normally starts prometheus, not promtool.
docker run --rm --entrypoint /bin/promtool \
  -v "$PWD/prometheus:/etc/prometheus:ro" \
  prom/prometheus:v2.53.0 check config /etc/prometheus/prometheus.yml
for rule in prometheus/alerts/*.yml; do
  docker run --rm --entrypoint /bin/promtool \
    -v "$PWD/prometheus/alerts:/rules:ro" \
    prom/prometheus:v2.53.0 check rules "/rules/$(basename "$rule")"
done
