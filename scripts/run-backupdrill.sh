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

# Required inputs are checked here because GitHub doesn't enforce `required` for
# composite actions. An empty database URL is the dangerous one: the CLI would fall
# back to DATABASE_URL, which in many jobs points at some other database.
require_input() {  # $1 = environment variable, $2 = input name
  if [[ -z "${!1:-}" ]]; then
    echo "::error::$2 is empty. Check that the secret it comes from is set."
    exit 1
  fi
}
require_input BACKUPDRILL_S3_BUCKET s3-bucket
require_input BACKUPDRILL_S3_ACCESS_KEY_ID s3-access-key-id
require_input BACKUPDRILL_S3_SECRET_ACCESS_KEY s3-secret-access-key
if [[ "$command" == "backup" ]]; then
  require_input BACKUPDRILL_DATABASE_URL database-url
fi

# npm's "new version available" notice is noise in a backup log.
export npm_config_update_notifier=false
export BACKUPDRILL_PG_DUMP="/usr/lib/postgresql/${POSTGRES_VERSION}/bin/pg_dump"
export BACKUPDRILL_PG_RESTORE="/usr/lib/postgresql/${POSTGRES_VERSION}/bin/pg_restore"

# The CLI prints its result as one JSON line on stdout: for a backup that is the whole
# manifest, with every table name and Storage file path. It stays out of the job log,
# which anyone can read on a public repository, and is deleted when the step ends.
result="$(mktemp "${RUNNER_TEMP:-/tmp}/backupdrill-result.XXXXXX")"
trap 'rm -f "$result"' EXIT

cli=(npx --yes "backupdrill@${BACKUPDRILL_VERSION_SPEC}")

case "$command" in
  backup)
    if [[ "${DRILL_INPUT:-false}" != "true" && "${DRILL_INPUT:-false}" != "false" ]]; then
      echo "::error::drill must be \"true\" or \"false\"."
      exit 1
    fi
    "${cli[@]}" backup >"$result"
    node "$GITHUB_ACTION_PATH/scripts/write-outputs.mjs" "$result"
    ;;
  drill)
    if [[ -z "${SNAPSHOT:-}" ]]; then
      echo "::error::The backup step did not report a snapshot to drill."
      exit 1
    fi
    "${cli[@]}" drill --snapshot "$SNAPSHOT" >"$result"
    ;;
  *)
    echo "::error::Unknown command: use backup or drill."
    exit 1
    ;;
esac
