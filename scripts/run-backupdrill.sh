#!/usr/bin/env bash
# Runs `backupdrill backup` or `backupdrill drill` and turns the CLI's JSON result into
# step outputs. Every setting comes in through environment variables set by action.yml.
set -euo pipefail

command="${1:?usage: run-backupdrill.sh backup|drill}"

# The version goes straight into an npm package spec, so only plain versions and
# ranges like "2" or "2.7.1" are accepted, never a path, URL or tag of another package.
if ! [[ "${BACKUPDRILL_VERSION_SPEC:-}" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
  echo "::error::backupdrill-version must look like 2, 2.7 or 2.7.1."
  exit 1
fi

# A secret that isn't set reaches the step as an empty string. The CLI ignores most
# empty settings but keeps an empty project name, which would write the snapshot under
# "<prefix>//<timestamp>/", so every empty BACKUPDRILL_* variable is removed first.
while IFS= read -r name; do
  if [[ -z "${!name}" ]]; then unset "$name"; fi
done < <(compgen -e | grep '^BACKUPDRILL_' || true)

# With BACKUPDRILL_DATABASE_URL empty, the CLI falls back to DATABASE_URL, which in many
# jobs points at the app's own database. Removing it means an empty database-url stops
# at the CLI's own config check, which names what is missing and sends the /fail ping.
# GitHub doesn't enforce `required` on composite action inputs, so that check is the guard.
unset DATABASE_URL

# npm's "new version available" notice is noise in a backup log.
export npm_config_update_notifier=false
export BACKUPDRILL_PG_DUMP="/usr/lib/postgresql/${POSTGRES_VERSION}/bin/pg_dump"
export BACKUPDRILL_PG_RESTORE="/usr/lib/postgresql/${POSTGRES_VERSION}/bin/pg_restore"

# The CLI prints its result as one JSON line on stdout: for a backup that is the whole
# manifest, with every table name and Storage file path. It stays out of the job log,
# which anyone can read on a public repository, and is deleted when the step ends.
result="$(mktemp "${RUNNER_TEMP:-/tmp}/backupdrill-result.XXXXXX")"
trap 'rm -f "$result"' EXIT

# The action takes its settings from its inputs and BACKUPDRILL_* variables only. A
# backupdrill.config.json in the workspace, say from a checked-out repository, could
# otherwise fill in a database or bucket the workflow never named. --config pointing at
# a file that doesn't exist makes the CLI skip the file.
no_config="${result}.none.json"
cli=(npx --yes "backupdrill@${BACKUPDRILL_VERSION_SPEC}")

case "$command" in
  backup)
    if [[ "${DRILL_INPUT:-false}" != "true" && "${DRILL_INPUT:-false}" != "false" ]]; then
      echo "::error::drill must be \"true\" or \"false\"."
      exit 1
    fi
    "${cli[@]}" backup --config "$no_config" >"$result"
    node "$GITHUB_ACTION_PATH/scripts/write-outputs.mjs" "$result"
    ;;
  drill)
    if [[ -z "${SNAPSHOT:-}" ]]; then
      echo "::error::The backup step did not report a snapshot to drill."
      exit 1
    fi
    "${cli[@]}" drill --config "$no_config" --snapshot "$SNAPSHOT" >"$result"
    ;;
  *)
    echo "::error::Unknown command: use backup or drill."
    exit 1
    ;;
esac
