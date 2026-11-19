#!/usr/bin/env bash
# Re-run a workflow run that failed only because GitHub never handed one of its jobs to a runner.
# Such a job is cancelled after 15 minutes in the queue with the annotation matched below.
# A run that failed for any other reason, or was cancelled by a newer push, is left alone.
#
#   RUN_ID=<run id> RUN_ATTEMPT=<attempt> .github/scripts/retry-dropped.sh
#
# DRY_RUN=1 prints the decision without re-running anything.
set -euo pipefail

repo="${GITHUB_REPOSITORY:?set GITHUB_REPOSITORY to owner/name}"
run="${RUN_ID:?set RUN_ID}"
attempt="${RUN_ATTEMPT:?set RUN_ATTEMPT}"
[[ "$run" =~ ^[0-9]+$ && "$attempt" =~ ^[0-9]+$ ]] || { echo "RUN_ID and RUN_ATTEMPT must be numbers" >&2; exit 2; }

marker="was not acquired by Runner"
dropped=""
jobs="$(gh api "repos/$repo/actions/runs/$run/attempts/$attempt/jobs" --paginate \
  --jq '.jobs[] | select(.conclusion == "cancelled" and (.runner_name // "") == "") | .id')"
for job in $jobs; do
  if gh api "repos/$repo/check-runs/$job/annotations" --jq '.[].message' | grep -q "$marker"; then
    dropped="$job"
    break
  fi
done

if [[ -z "$dropped" ]]; then
  echo "Run $run, attempt $attempt: no job was dropped by the runner queue. Nothing to retry."
  exit 0
fi
if [[ "${DRY_RUN:-}" == "1" ]]; then
  echo "Run $run, attempt $attempt: job $dropped was never given a runner. Would re-run the failed jobs."
  exit 0
fi
echo "Run $run, attempt $attempt: job $dropped was never given a runner. Re-running the failed jobs."
gh run rerun "$run" --repo "$repo" --failed
