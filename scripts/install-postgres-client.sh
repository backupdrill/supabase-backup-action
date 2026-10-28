#!/usr/bin/env bash
# Installs pg_dump and pg_restore of the requested major version from the PostgreSQL
# apt repository (PGDG). pg_dump refuses to dump a server newer than itself, and the
# client that ships with the runner image can be older than the Supabase database.
set -euo pipefail

if [[ "${RUNNER_OS:-Linux}" != "Linux" ]]; then
  echo "::error::This action needs a Linux runner, such as ubuntu-latest."
  exit 1
fi
if ! [[ "${POSTGRES_VERSION:-}" =~ ^[0-9]+$ ]]; then
  echo "::error::postgres-version must be a major version number, such as 17."
  exit 1
fi

bin_dir="/usr/lib/postgresql/${POSTGRES_VERSION}/bin"
if [[ -x "$bin_dir/pg_dump" && -x "$bin_dir/pg_restore" ]]; then
  echo "PostgreSQL ${POSTGRES_VERSION} client tools are already installed."
  exit 0
fi

# sudo only when needed: GitHub-hosted runners have it, a root container may not.
as_root() { if [[ "$(id -u)" -eq 0 ]]; then "$@"; else sudo "$@"; fi; }

# shellcheck source=/dev/null
. /etc/os-release
keyring=/usr/share/postgresql-common/pgdg/apt.postgresql.org.gpg
as_root install -d "$(dirname "$keyring")"
curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc |
  as_root gpg --batch --yes --dearmor -o "$keyring"
echo "deb [signed-by=$keyring] https://apt.postgresql.org/pub/repos/apt ${VERSION_CODENAME}-pgdg main" |
  as_root tee /etc/apt/sources.list.d/pgdg.list >/dev/null
as_root apt-get update -qq
as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "postgresql-client-${POSTGRES_VERSION}" >/dev/null
"$bin_dir/pg_dump" --version
