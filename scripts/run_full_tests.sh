#!/usr/bin/env bash
# Runs the whole `flutter test` suite in resumable shards.
#
# A single full run takes ~40 minutes here and the sandbox kills long commands,
# so this walks the tree in batches and records each file it has finished in
# `.agent_logs/full_test_done.txt`. Re-running the script picks up where the
# last one stopped; delete that file to start over.
#
#   bash scripts/run_full_tests.sh          # resume
#   bash scripts/run_full_tests.sh --fresh  # start over
#
# Results land in `.agent_logs/full_test.log`; `grep '^FAIL'` lists the files
# that failed. A batch that fails is retried one file at a time so a single
# broken file cannot hide the rest of its batch. Files that fail stay out of
# the done list, so the next run retries exactly those.
set -u

cd "$(dirname "$0")/.." || exit 1
# shellcheck source=/dev/null
source scripts/env.sh

LOG=.agent_logs/full_test.log
DONE=.agent_logs/full_test_done.txt
BATCH=${BATCH:-25}

mkdir -p .agent_logs
[ "${1:-}" = "--fresh" ] && rm -f "$LOG" "$DONE"
touch "$LOG" "$DONE"
START=$(wc -l <"$LOG")

run_batch() {
  local -a batch=("$@")
  [ ${#batch[@]} -eq 0 ] && return
  echo "### batch: ${batch[0]} (+$(( ${#batch[@]} - 1 )))" >>"$LOG"
  if timeout 900 flutter test --no-pub "${batch[@]}" >>"$LOG" 2>&1; then
    printf '%s\n' "${batch[@]}" >>"$DONE"
    echo "### ok ${#batch[@]}" >>"$LOG"
    return
  fi
  echo "### batch failed, retrying one file at a time" >>"$LOG"
  local g
  for g in "${batch[@]}"; do
    if timeout 400 flutter test --no-pub "$g" >>"$LOG" 2>&1; then
      printf '%s\n' "$g" >>"$DONE"
    else
      echo "FAIL $g" >>"$LOG"
    fi
  done
}

batch=()
while IFS= read -r f; do
  grep -qxF "$f" "$DONE" && continue
  batch+=("$f")
  if [ ${#batch[@]} -ge "$BATCH" ]; then
    run_batch "${batch[@]}"
    batch=()
  fi
done < <(find test -name '*_test.dart' | sort)
run_batch "${batch[@]}"

echo "### driver finished" >>"$LOG"
echo "done: $(wc -l <"$DONE") files; this run:"
tail -n +$((START + 1)) "$LOG" | grep '^FAIL' || echo "  no failures"
