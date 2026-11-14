#!/usr/bin/env bash
# Serve the static website exactly as Cloudflare Pages does (no build step).
# Usage: .claude/skills/verify/scripts/web.sh <up|doctor|down> [port]
set -euo pipefail
ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
RUN="$ROOT/.verify/run"; mkdir -p "$RUN"
PORT=${2:-4174}   # 4173 belongs to `npm run test:visual`; keep them apart
URL="http://127.0.0.1:$PORT"
alive() { [[ -f "$RUN/web.pid" ]] && kill -0 "$(cat "$RUN/web.pid")" 2>/dev/null; }

case "${1:-}" in
up)
  if alive; then echo "already serving $(cat "$RUN/web.url") (pid $(cat "$RUN/web.pid"))"; exit 0; fi
  if curl -fs -o /dev/null "$URL/"; then echo "port $PORT is taken by something we did not start; pass another port" >&2; exit 1; fi
  python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$ROOT/website" > "$RUN/web.log" 2>&1 &
  echo $! > "$RUN/web.pid"; echo "$URL" > "$RUN/web.url"
  for _ in $(seq 1 40); do
    if curl -fs "$URL/catalog.json" | python3 -c 'import json,sys; assert len(json.load(sys.stdin))>0' 2>/dev/null; then
      echo "ready: $URL (pid $(cat "$RUN/web.pid"))"; exit 0
    fi
    sleep 0.25
  done
  echo "server did not serve catalog.json; see $RUN/web.log" >&2; exit 1
  ;;
doctor)
  alive || { echo "FAIL not running; run: web.sh up"; exit 1; }
  url=$(cat "$RUN/web.url")
  code=$(curl -s -o /dev/null -w '%{http_code}' "$url/")
  n=$(curl -fs "$url/catalog.json" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')
  [[ "$code" == 200 ]] && echo "ok   $url/ -> 200, catalog.json has $n entries, pid $(cat "$RUN/web.pid")" || { echo "FAIL $url/ -> $code"; exit 1; }
  ;;
down)
  if alive; then kill "$(cat "$RUN/web.pid")"; echo "stopped web server"; fi
  rm -f "$RUN/web.pid" "$RUN/web.url"
  ;;
*) sed -n '2,3p' "$0"; exit 1 ;;
esac
