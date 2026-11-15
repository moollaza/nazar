#!/usr/bin/env bash
# Build, launch, drive, and tear down an isolated copy of the Nazar Mac app.
# Usage: .claude/skills/verify/scripts/nazar-app.sh <command> [args]
#
#   build                 Debug build with bundle ID com.moollapps.StatusMonitor.verify, plus the ax driver
#   launch [--fresh] [-- app-args...]
#                         start the verify build; --fresh wipes its (and only its) saved state first
#   doctor                read-only health check; run it whenever anything looks off
#   ax <cmd> [args...]    run the ax driver against the running verify app (PID is filled in)
#   shot <name>           save screenshots + AX tree as evidence/<run>/<name>.*
#   log [pattern]         print this run's app log, optionally filtered
#   quit                  stop the app and log stream this run started
#   clean                 quit, then wipe the verify app's saved state; evidence is kept
#   evidence              print this run's evidence directory
set -euo pipefail

ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
SKILL="$ROOT/.claude/skills/verify"
STATE="$ROOT/.verify"
RUN="$STATE/run"
BID="com.moollapps.StatusMonitor.verify"
DERIVED="$STATE/DerivedData"
APP="$DERIVED/Build/Products/Debug/Nazar.app"
EXE="$APP/Contents/MacOS/Nazar"
AX="$STATE/bin/ax"
CONTAINER_PREFS="$HOME/Library/Containers/$BID/Data/Library/Preferences/$BID"

mkdir -p "$RUN"

# The app macOS asks permission for: the nearest .app above this shell. (Claude's
# desktop app disclaims its child, so there it is "Claude Code", not "Claude".)
responsible_app() {
  local p=$$ c
  while [[ "$p" -gt 1 ]]; do
    c=$(ps -o comm= -p "$p")
    if [[ "$c" == *.app/Contents/MacOS/* ]]; then
      /usr/libexec/PlistBuddy -c 'Print :CFBundleName' "${c%%/Contents/MacOS/*}/Contents/Info.plist" 2>/dev/null \
        || basename "${c%%.app/Contents/MacOS/*}"
      return
    fi
    p=$(ps -o ppid= -p "$p" | tr -d ' ')
  done
  echo "your terminal app"
}

responsible_exe() {
  local p=$$ c
  while [[ "$p" -gt 1 ]]; do
    c=$(ps -o comm= -p "$p")
    [[ "$c" == *.app/Contents/MacOS/* ]] && { basename "$c"; return; }
    p=$(ps -o ppid= -p "$p" | tr -d ' ')
  done
}

alive() { [[ -f "$RUN/$1.pid" ]] && kill -0 "$(cat "$RUN/$1.pid")" 2>/dev/null; }
app_pid() { alive app || { echo "verify app is not running; run: nazar-app.sh launch" >&2; exit 1; }; cat "$RUN/app.pid"; }
run_id() { cat "$RUN/run_id" 2>/dev/null || echo "no-run"; }
evidence_dir() { local d="$STATE/evidence/$(run_id)"; mkdir -p "$d"; echo "$d"; }

reset_state() {
  # Only the verify bundle ID. Never the user's com.moollapps.StatusMonitor domain.
  defaults delete "$CONTAINER_PREFS" >/dev/null 2>&1 || true
  defaults delete "$BID" >/dev/null 2>&1 || true
}

stop() {
  local name=$1
  if alive "$name"; then
    local pid; pid=$(cat "$RUN/$name.pid")
    kill "$pid" 2>/dev/null || true
    for _ in $(seq 1 20); do kill -0 "$pid" 2>/dev/null || break; sleep 0.25; done
    kill -9 "$pid" 2>/dev/null || true
    echo "stopped $name (pid $pid)"
  fi
  rm -f "$RUN/$name.pid"
}

cmd=${1:-}; shift || true
case "$cmd" in
build)
  cd "$ROOT"
  xcodebuild -project StatusMonitor.xcodeproj -scheme StatusMonitor -configuration Debug \
    -destination 'platform=macOS' -derivedDataPath "$DERIVED" \
    PRODUCT_BUNDLE_IDENTIFIER="$BID" \
    CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER= \
    ENABLE_HARDENED_RUNTIME=NO \
    build 2>&1 | tee "$RUN/build.log" | grep -E '^(\*\* BUILD|error:|.*: error:)' || true
  grep -q '\*\* BUILD SUCCEEDED \*\*' "$RUN/build.log" || { echo "build failed; see $RUN/build.log" >&2; exit 1; }
  mkdir -p "$STATE/bin"
  swiftc -O "$SKILL/scripts/ax.swift" -o "$AX"
  echo "built $APP"
  echo "built $AX"
  ;;

launch)
  [[ -x "$EXE" && -x "$AX" ]] || { echo "nothing built; run: nazar-app.sh build" >&2; exit 1; }
  if alive app; then echo "verify app already running (pid $(cat "$RUN/app.pid")); run quit first" >&2; exit 1; fi
  fresh=0; app_args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in --fresh) fresh=1 ;; --) shift; app_args=("$@"); break ;; *) echo "unknown arg $1" >&2; exit 1 ;; esac
    shift
  done
  [[ $fresh == 1 ]] && reset_state
  # --fresh starts a new evidence folder; a plain relaunch (persistence check) keeps the run.
  if [[ $fresh == 1 || ! -f "$RUN/run_id" ]]; then date +%Y%m%d-%H%M%S > "$RUN/run_id"; fi
  stop logstream
  : > "$RUN/app.log"
  log stream --style compact --level debug --predicate "subsystem == \"$BID\"" >> "$RUN/app.log" 2>&1 &
  echo $! > "$RUN/logstream.pid"
  sleep 1
  "$EXE" ${app_args[@]+"${app_args[@]}"} > "$RUN/stdout.log" 2>&1 &
  echo $! > "$RUN/app.pid"
  for _ in $(seq 1 60); do
    if grep -q 'App launch complete' "$RUN/app.log"; then
      echo "ready: pid $(cat "$RUN/app.pid"), run $(run_id), fresh=$fresh"
      exit 0
    fi
    alive app || { echo "app exited during launch; see $RUN/stdout.log" >&2; exit 1; }
    sleep 0.5
  done
  echo "app did not log 'App launch complete' within 30s; see $RUN/app.log" >&2; exit 1
  ;;

doctor)
  ok=1
  if alive app; then
    pid=$(cat "$RUN/app.pid"); cmdline=$(ps -p "$pid" -o command=)
    if [[ "$cmdline" == "$EXE"* ]]; then echo "ok   app pid $pid is the verify build"; else echo "FAIL pid $pid is not our build: $cmdline"; ok=0; fi
  else
    echo "FAIL verify app not running"; ok=0
  fi
  if alive logstream; then echo "ok   log stream running"; else echo "FAIL log stream not running (relaunch)"; ok=0; fi
  if [[ -x "$EXE" ]]; then
    bid=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")
    ver=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
    [[ "$bid" == "$BID" ]] && echo "ok   bundle id $bid, version $ver" || { echo "FAIL bundle id is $bid"; ok=0; }
    newer=$(cd "$ROOT" && find Models Views Services Resources StatusMonitorApp.swift Config -newer "$EXE" -type f | head -3)
    [[ -z "$newer" ]] && echo "ok   build is newer than every source file" || { echo "FAIL stale build, newer sources: $newer (run build)"; ok=0; }
  else
    echo "FAIL not built"; ok=0
  fi
  if [[ -x "$AX" ]]; then
    if ! "$AX" check --prompt | sed 's/^/     /'; then
      host=$(responsible_app)
      echo "FAIL a person must switch on \"$host\" in System Settings > Privacy & Security, under both"
      echo "     Accessibility (called \"Device Control and Data Access\" on newer macOS) and Screen & System Audio Recording."
      echo "     The list may show it as \"$(responsible_exe)\". Do not restart $host; rerun doctor after."
      ok=0
    fi
  fi
  real=$(pgrep -x Nazar | grep -v "^$(cat "$RUN/app.pid" 2>/dev/null || echo none)$" || true)
  [[ -n "$real" ]] && echo "note another Nazar is running (pid $real): it is the user's copy, do not touch it"
  echo "run $(run_id), evidence $(evidence_dir)"
  [[ $ok == 1 ]]
  ;;

ax)
  sub=${1:?usage: ax <cmd> [args]}; shift
  if [[ "$sub" == check ]]; then exec "$AX" check; fi
  exec "$AX" "$sub" "$(app_pid)" "$@"
  ;;

shot)
  name=${1:?usage: shot <name>}; pid=$(app_pid); dir=$(evidence_dir)
  # Without Screen Recording permission screencapture fails; keep the AX tree anyway.
  "$AX" dump "$pid" > "$dir/$name.ax.txt"
  if ! screencapture -x "$dir/$name.screen.png" 2>/dev/null; then
    echo "WARN no screenshot (Screen Recording not granted; run doctor); saved $dir/$name.ax.txt only" >&2
    exit 1
  fi
  i=0
  while IFS=$'\t' read -r wid layer _bounds _title; do
    [[ "$layer" == "layer=25" ]] && continue  # the menu bar icon itself
    screencapture -x -o -l "$wid" "$dir/$name.win$i.png" && i=$((i+1))
  done < <("$AX" windows "$pid")
  echo "saved $dir/$name.screen.png, $i window shot(s), $dir/$name.ax.txt"
  ;;

log)
  if [[ -n "${1:-}" ]]; then grep -i -- "$1" "$RUN/app.log" || true; else cat "$RUN/app.log"; fi
  ;;

quit)
  # Append: a relaunch in the same run must not overwrite the first launch's log.
  [[ -f "$RUN/app.log" && "$(run_id)" != no-run ]] && cat "$RUN/app.log" >> "$(evidence_dir)/app.log"
  : > "$RUN/app.log"
  stop app
  stop logstream
  ;;

clean)
  "$0" quit
  reset_state
  echo "cleaned verify state; evidence kept in $STATE/evidence"
  ;;

evidence)
  evidence_dir
  ;;

*)
  sed -n '2,17p' "$0"; exit 1
  ;;
esac
