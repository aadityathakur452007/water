#!/usr/bin/env bash
# Runs inside the GitHub Actions Android emulator step.
# Installs the built APK, launches the app, and executes OpenCode headlessly
# using verified free opencode/ models only.
set -uo pipefail

APP_NAME="${APP_NAME:?APP_NAME is required}"
APP_ID="${APP_ID:?APP_ID is required}"
APK_PATH="${APK_PATH:?APK_PATH is required}"
PRIMARY_MODEL="${PRIMARY_MODEL:?PRIMARY_MODEL is required}"
FALLBACK_MODEL="${FALLBACK_MODEL:-}"
BRIEF_PATH="${BRIEF_PATH:-tools/mobile-tester/BRIEF.md}"
OUT_DIR="results/$APP_NAME"

mkdir -p "$OUT_DIR"

adb wait-for-device
adb install -r -g "$APK_PATH" || adb install -r "$APK_PATH"
adb logcat -c
adb shell monkey -p "$APP_ID" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
sleep 5

export OPENCODE_CONFIG="$PWD/tools/mobile-tester/opencode.json"

CRED_HINT=""
if [ -n "${QA_PHONE:-}" ] && [ -n "${QA_PASSWORD:-}" ]; then
  CRED_HINT="QA login credentials are available: phone=$QA_PHONE password=$QA_PASSWORD."
elif [ -n "${QA_ACCESS_CODE:-}" ]; then
  CRED_HINT="QA access code is available: code=$QA_ACCESS_CODE."
else
  CRED_HINT="No QA login credentials were provided; test onboarding, validation, error states, and public screens."
fi

PROMPT="Read $BRIEF_PATH. You are testing APP_NAME=$APP_NAME (package=$APP_ID) on an Android emulator. Replace <APP_NAME> with $APP_NAME in all paths. $CRED_HINT Start by running python3 tools/mobile-tester/screen.py $OUT_DIR 01, explore the app, and finish by writing $OUT_DIR/report.md and $OUT_DIR/findings.json."

run_opencode() {
  local model="$1"
  local logfile="$2"
  echo "Running OpenCode agent with free model: $model"
  timeout 900 opencode run --format json --model "$model" "$PROMPT" > "$logfile" 2> "$OUT_DIR/opencode-stderr.log"
}

CODE=0
run_opencode "$PRIMARY_MODEL" "$OUT_DIR/opencode-output.jsonl" || CODE=$?

if { [ "$CODE" -ne 0 ] || [ ! -s "$OUT_DIR/report.md" ]; } && [ -n "$FALLBACK_MODEL" ]; then
  echo "Primary model ($PRIMARY_MODEL) exited with $CODE or produced no report. Retrying with fallback: $FALLBACK_MODEL"
  CODE=0
  run_opencode "$FALLBACK_MODEL" "$OUT_DIR/opencode-fallback-output.jsonl" || CODE=$?
fi

adb logcat -d > "$OUT_DIR/logcat.txt" 2>/dev/null || true

if [ ! -f "$OUT_DIR/report.md" ]; then
  cat > "$OUT_DIR/report.md" <<EOF
# AI Test Report ($APP_NAME)

- **Status:** Agent exited with code $CODE without writing report.md
- **Primary Model:** $PRIMARY_MODEL
- **Fallback Model:** ${FALLBACK_MODEL:-none}
- **Screenshots captured:** $(find "$OUT_DIR" -maxdepth 1 -name '*.png' | wc -l)
EOF
fi

if [ ! -f "$OUT_DIR/findings.json" ]; then
  echo "{\"app\": \"$APP_NAME\", \"status\": \"incomplete\", \"exit_code\": $CODE, \"issues\": []}" > "$OUT_DIR/findings.json"
fi

echo "Finished $APP_NAME (exit=$CODE), artifacts in $OUT_DIR:"
ls -la "$OUT_DIR"
exit "$CODE"
