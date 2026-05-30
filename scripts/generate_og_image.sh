#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OG_URL="${OG_URL:-http://127.0.0.1:4000/}"
OG_OUTPUT="${OG_OUTPUT:-$ROOT_DIR/priv/static/images/og/home.png}"
OG_WIDTH="${OG_WIDTH:-1200}"
OG_HEIGHT="${OG_HEIGHT:-630}"
OG_CROP_Y="${OG_CROP_Y:-237}"
OG_WAIT_MS="${OG_WAIT_MS:-3500}"
OG_CHROME_TIMEOUT_SEC="${OG_CHROME_TIMEOUT_SEC:-20}"
OG_ENV_FILE="${OG_ENV_FILE:-}"
SERVER_LOG="${SERVER_LOG:-$ROOT_DIR/tmp/og-image-server.log}"

server_pid=""
tmp_user_data=""
tmp_screenshot=""

cleanup() {
  if [ -n "$server_pid" ]; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi

  if [ -n "$tmp_user_data" ]; then
    rm -rf "$tmp_user_data"
  fi

  if [ -n "$tmp_screenshot" ]; then
    rm -f "$tmp_screenshot"
  fi
}

trap cleanup EXIT

find_chrome() {
  if [ -n "${CHROME_BIN:-}" ]; then
    if [ -x "$CHROME_BIN" ]; then
      printf '%s\n' "$CHROME_BIN"
      return 0
    fi

    printf 'CHROME_BIN is not executable: %s\n' "$CHROME_BIN" >&2
    return 1
  fi

  for name in chrome-headless-shell google-chrome google-chrome-stable chromium chromium-browser chrome; do
    if command -v "$name" >/dev/null 2>&1; then
      command -v "$name"
      return 0
    fi
  done

  for candidate in \
    "$HOME/Library/Caches/ms-playwright"/chromium_headless_shell-*/chrome-headless-shell-*/chrome-headless-shell \
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
    "$HOME/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
    "$HOME/Library/Caches/ms-playwright"/chromium-*/chrome-mac-*/Google\ Chrome\ for\ Testing.app/Contents/MacOS/Google\ Chrome\ for\ Testing; do
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  printf 'Could not find a Chrome or Chromium executable. Set CHROME_BIN=/path/to/chrome and retry.\n' >&2
  return 1
}

run_chrome() {
  local chrome="$1"
  local chrome_log="$2"
  shift 2

  "$chrome" "$@" >"$chrome_log" 2>&1 &
  local chrome_pid="$!"
  local elapsed=0
  local status=0

  while kill -0 "$chrome_pid" 2>/dev/null; do
    if [ "$elapsed" -ge "$OG_CHROME_TIMEOUT_SEC" ]; then
      kill "$chrome_pid" 2>/dev/null || true
      wait "$chrome_pid" 2>/dev/null || true
      printf 'Chrome did not finish within %s seconds.\n' "$OG_CHROME_TIMEOUT_SEC" >&2
      return 124
    fi

    sleep 1
    elapsed=$((elapsed + 1))
  done

  set +e
  wait "$chrome_pid"
  status="$?"
  set -e
  return "$status"
}

page_is_ready() {
  curl -fsS -o /dev/null "$OG_URL" >/dev/null 2>&1
}

start_server_if_needed() {
  if page_is_ready; then
    return 0
  fi

  mkdir -p "$(dirname "$SERVER_LOG")"

  (
    cd "$ROOT_DIR"

    if [ -n "$OG_ENV_FILE" ] && [ -f "$OG_ENV_FILE" ]; then
      set -a
      # shellcheck disable=SC1090
      . "$OG_ENV_FILE"
      set +a
    fi

    mix phx.server
  ) >"$SERVER_LOG" 2>&1 &

  server_pid="$!"

  for _attempt in $(seq 1 60); do
    if page_is_ready; then
      return 0
    fi

    if ! kill -0 "$server_pid" 2>/dev/null; then
      printf 'Phoenix server exited before %s became available.\n' "$OG_URL" >&2
      tail -40 "$SERVER_LOG" >&2 || true
      return 1
    fi

    sleep 0.5
  done

  printf 'Timed out waiting for %s.\n' "$OG_URL" >&2
  tail -40 "$SERVER_LOG" >&2 || true
  return 1
}

take_screenshot() {
  local chrome="$1"
  local chrome_log
  local capture_height
  local screenshot_path
  chrome_log="$(mktemp)"
  tmp_user_data="$(mktemp -d)"
  capture_height="$OG_HEIGHT"

  if [ "$OG_CROP_Y" -gt 0 ]; then
    capture_height=$((OG_HEIGHT + OG_CROP_Y - 1))
  fi

  mkdir -p "$(dirname "$OG_OUTPUT")"

  if [ "$OG_CROP_Y" -gt 0 ]; then
    tmp_screenshot="$(mktemp).png"
    screenshot_path="$tmp_screenshot"
  else
    screenshot_path="$OG_OUTPUT"
  fi

  if run_chrome "$chrome" "$chrome_log" \
    --headless=new \
    --no-first-run \
    --no-default-browser-check \
    --disable-background-networking \
    --disable-gpu \
    --disable-dev-shm-usage \
    --hide-scrollbars \
    --run-all-compositor-stages-before-draw \
    --user-data-dir="$tmp_user_data" \
    --window-size="${OG_WIDTH},${capture_height}" \
    --force-device-scale-factor=1 \
    --virtual-time-budget="$OG_WAIT_MS" \
    --screenshot="$screenshot_path" \
    "$OG_URL"; then
    crop_screenshot "$screenshot_path"
    rm -f "$chrome_log"
    return 0
  fi

  if run_chrome "$chrome" "$chrome_log" \
    --headless \
    --no-first-run \
    --no-default-browser-check \
    --disable-background-networking \
    --disable-gpu \
    --disable-dev-shm-usage \
    --hide-scrollbars \
    --run-all-compositor-stages-before-draw \
    --user-data-dir="$tmp_user_data" \
    --window-size="${OG_WIDTH},${capture_height}" \
    --force-device-scale-factor=1 \
    --timeout="$OG_WAIT_MS" \
    --screenshot="$screenshot_path" \
    "$OG_URL"; then
    crop_screenshot "$screenshot_path"
    rm -f "$chrome_log"
    return 0
  fi

  printf 'Chrome screenshot failed.\n' >&2
  cat "$chrome_log" >&2
  rm -f "$chrome_log"
  return 1
}

crop_screenshot() {
  local screenshot_path="$1"

  if [ "$OG_CROP_Y" -le 0 ]; then
    return 0
  fi

  cp "$screenshot_path" "$OG_OUTPUT"
  sips -c "$OG_HEIGHT" "$OG_WIDTH" --cropOffset "$OG_CROP_Y" 0 "$OG_OUTPUT" >/dev/null
}

chrome="$(find_chrome)"
start_server_if_needed
take_screenshot "$chrome"

printf 'Wrote %s from %s at %sx%s with y=%s crop.\n' "$OG_OUTPUT" "$OG_URL" "$OG_WIDTH" "$OG_HEIGHT" "$OG_CROP_Y"
