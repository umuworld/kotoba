#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_BIN="$PROJECT_DIR/dist/Kotoba.app/Contents/MacOS/Kotoba"
[[ -x "$APP_BIN" ]] || bash "$PROJECT_DIR/build.sh"
"$APP_BIN" --core-test

FIXTURE_PID=""
cleanup() {
  if [[ -n "$FIXTURE_PID" ]]; then
    kill "$FIXTURE_PID" 2>/dev/null || true
    wait "$FIXTURE_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT
python3 "$PROJECT_DIR/Tests/api_fixture.py" &
FIXTURE_PID=$!
READY=0
for attempt in {1..30}; do
  kill -0 "$FIXTURE_PID" 2>/dev/null || { echo "Fixture failed to start; check port 18765." >&2; exit 1; }
  if curl --fail --silent http://127.0.0.1:18765/health | grep -q 'kotoba-protocol-v1'; then
    READY=1
    break
  fi
  sleep 0.1
done
[[ "$READY" == 1 ]] || { echo "Fixture readiness timed out." >&2; exit 1; }
"$APP_BIN" --network-test
