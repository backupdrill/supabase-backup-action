# Supabase Backup with BackupDrill

A GitHub Action that backs up a Supabase project's Postgres database, and its Storage files if you want them, into an S3, Cloudflare R2 or Backblaze B2 bucket that you own. It runs the open-source [backupdrill CLI](https://backupdrill.com/docs/cli) (MIT). Turn on `drill` and it also restores the new snapshot into a throwaway Postgres and checks that it comes back.

The data goes from Supabase through the GitHub runner straight into your bucket. Nothing is sent to BackupDrill.

The full walkthrough, including where to find each secret and how to restore, is here: [Automatic Supabase backups with GitHub Actions](https://backupdrill.com/guides/supabase-backup-github-actions).

## Usage

Add the secrets below to your repository (Settings → Secrets and variables → Actions), then save this as `.github/workflows/supabase-backup.yml`:

```yaml
name: supabase-backup

on:
  schedule:
    - cron: "0 3 * * 0" # Sundays at 03:00 UTC
  workflow_dispatch: {} # run it by hand from the Actions tab

permissions:
  contents: read

# Never let two backups run at once. A slow run overlapping the next one
# would pull the database out of Supabase twice.
concurrency:
  group: supabase-backup
  cancel-in-progress: false

jobs:
  backup:
    runs-on: ubuntu-latest
    steps:
      - uses: backupdrill/supabase-backup-action@v1
        with:
          database-url: ${{ secrets.BACKUPDRILL_DATABASE_URL }}
          s3-bucket: ${{ secrets.BACKUPDRILL_S3_BUCKET }}
          s3-access-key-id: ${{ secrets.BACKUPDRILL_S3_ACCESS_KEY_ID }}
          s3-secret-access-key: ${{ secrets.BACKUPDRILL_S3_SECRET_ACCESS_KEY }}
          s3-endpoint: ${{ secrets.BACKUPDRILL_S3_ENDPOINT }} # leave the secret unset for AWS S3
          s3-region: ${{ secrets.BACKUPDRILL_S3_REGION }} # auto for R2, the bucket's region for AWS S3
          project-name: my-app
          drill: "true"
```

Use a private repository for this workflow. Each run's log lists the project name, snapshot times and table counts, and on a public repository anyone can read the logs.

The secret names match the ones in the CLI's own example workflow, so if you already use that, you can switch without renaming anything.

## Secrets

| Secret | Required | What it is |
|---|---|---|
| `BACKUPDRILL_DATABASE_URL` | yes | The Session pooler connection string, password included. In the Supabase dashboard, click **Connect** at the top of the project page and pick **Session pooler**. The default `postgres` user works as is. |
| `BACKUPDRILL_S3_BUCKET` | yes | The bucket the backups go to. |
| `BACKUPDRILL_S3_ACCESS_KEY_ID`, `BACKUPDRILL_S3_SECRET_ACCESS_KEY` | yes | Keys that can write to that bucket. Keys limited to this one bucket are the safer choice. |
| `BACKUPDRILL_S3_ENDPOINT` | for R2, B2 and other S3-compatible stores | The S3 endpoint of your provider. Leave it out for AWS S3. |
| `BACKUPDRILL_S3_REGION` | for AWS S3 | The bucket's region, such as `us-east-1`. R2 takes `auto`, which is also what the CLI uses when this is empty. |
| `BACKUPDRILL_SUPABASE_STORAGE_ENDPOINT`, `_REGION`, `_ACCESS_KEY_ID`, `_SECRET_ACCESS_KEY` | no | To back up Storage files as well. Generate the keys under **Storage → Settings → S3 Access Keys** and copy the endpoint and region from the same page. These keys bypass row-level security, so keep them in secrets. |
| `BACKUPDRILL_PING_URL` | no | A Healthchecks.io ping URL, so you hear about failed runs and runs that never started. |

Pass the optional ones through the matching inputs, for example `supabase-storage-endpoint: ${{ secrets.BACKUPDRILL_SUPABASE_STORAGE_ENDPOINT }}`. A secret that isn't set comes through as an empty string, and the CLI treats empty as not set.

## Inputs

| Input | Default | Description |
|---|---|---|
| `database-url` | | Session pooler connection string. Required. |
| `s3-bucket` | | Destination bucket. Required. |
| `s3-access-key-id` | | Access key ID for the bucket. Required. |
| `s3-secret-access-key` | | Secret access key for the bucket. Required. |
| `s3-endpoint` | empty | S3-compatible endpoint for R2, B2 or a self-hosted store. Empty means AWS S3. |
| `s3-region` | empty | Bucket region. Empty means `auto`, which works for R2. AWS S3 needs the bucket's real region. |
| `project-name` | empty | Name used in the bucket path and the manifest. Empty means `supabase`. |
| `supabase-storage-endpoint` | empty | Storage S3 endpoint. Set it with the key ID and secret to back up Storage files, or leave all three empty for the database only. |
| `supabase-storage-region` | empty | Storage S3 region. |
| `supabase-storage-access-key-id` | empty | Storage S3 access key ID. |
| `supabase-storage-secret-access-key` | empty | Storage S3 secret access key. |
| `ping-url` | empty | Healthchecks.io ping URL. The backup and the drill each report start, success and failure to it. |
| `drill` | `"false"` | `"true"` restores the new snapshot into a throwaway Postgres and checks it. |
| `postgres-version` | `"17"` | Major version of `pg_dump` and `pg_restore` to install. It has to be at least your Supabase Postgres version. |
| `backupdrill-version` | `"2"` | backupdrill CLI version from npm. `"2"` takes the newest 2.x release on every run. |

Settings that have no input, such as `BACKUPDRILL_SCHEMAS` (which schemas to dump, `public` by default), `BACKUPDRILL_S3_PREFIX` or `BACKUPDRILL_SUPABASE_STORAGE_BUCKETS`, can be set as environment variables on the job. The CLI documentation lists all of them.

## Outputs

| Output | Description |
|---|---|
| `snapshot` | Name of the snapshot folder the backup wrote, a UTC timestamp such as `2026-10-28T16-32-21-387Z`. |
| `dump-key` | Object key of the database dump, `<prefix>/<project>/<snapshot>/dump.pgcustom`. |

## What a run does

1. Installs `postgresql-client-17` (or the version you set) from the PostgreSQL apt repository, unless it is already there. The client that comes with the runner image can be older than your database, and `pg_dump` won't dump a newer server.
2. Sets up Node.js 24 with `actions/setup-node`. Later steps in the same job see Node 24 too.
3. Runs `backupdrill backup`. The snapshot lands in `<prefix>/<project>/<timestamp>/` with `dump.pgcustom` (a plain `pg_dump` custom-format file that stock `pg_restore` can read), `manifest.json` with the tables, estimated row counts and sha256 checksums, `RECOVERY.md`, and a `storage/` folder when Storage is configured.
4. With `drill: "true"`, runs `backupdrill drill` on that snapshot.

The CLI prints its result as JSON that includes every table name and every Storage file path. The action keeps that JSON out of the log, reads the outputs from it, and deletes it when the step ends.

## The restore drill

A backup you have never restored is a guess. The drill downloads the dump the run just wrote, checks its sha256, restores it into a Postgres container on the runner and compares what came back with the manifest: whether `pg_restore` finished, whether every table is there, and whether tables that had rows still have rows. If Storage files were backed up, it checksums a sample of them. A failed check fails the job.

The drill step only gets the bucket settings. It never connects to your Supabase project, so it adds no Supabase egress, only a download from your bucket.

It needs Docker, which GitHub-hosted Ubuntu runners have. On a self-hosted runner, Docker has to be installed and usable by the runner user.

## Egress and cost

Every backup pulls your data out of Supabase, and that counts as egress on your Supabase bill. These figures come from Supabase's egress and cost control documentation, checked on 2026-10-29:

- Backup traffic is uncached egress. Each plan includes some every month: Free 5 GB, Pro 250 GB, Team 250 GB. Above that, Pro and Team pay $0.09 per GB.
- Pro has a Spend Cap, and it is on by default. With it on, Supabase doesn't bill the overage. Its docs say usage past the allowance is then disallowed until the next billing cycle, and that Fair Use restrictions apply if you keep going over. Either way your backups can start failing. Turn the Spend Cap off if you'd rather pay for the extra egress.
- Team has no Spend Cap and is billed for the overage.
- Free never bills overage. If you keep going over 5 GB, Supabase notifies you and then restricts the project under its Fair Use Policy, so large backups on Free aren't viable.

Rough monthly cost on Pro with the Spend Cap off, if backups are your only egress:

| Database + Storage | Weekly | Daily |
|---|---|---|
| 10 GB | $0 | about $4.50 |
| 50 GB | about $0 | about $112 |

Cost grows with size times frequency. The weekly schedule in the example is a sensible start. To see what your own project would cost, run `npx backupdrill estimate --plan pro` once on your machine with `BACKUPDRILL_DATABASE_URL` set, plus the `BACKUPDRILL_SUPABASE_STORAGE_*` variables if you back up Storage files. It measures the database and Storage and prints a monthly projection.

## Versions

- `@v1` is this action's own version. Within v1 the inputs and outputs above stay compatible.
- By default, v1 takes the newest backupdrill CLI 2.x release from npm on each run, so CLI fixes reach you without editing your workflow. To use the same CLI on every run, pin a 2.x release, for example `backupdrill-version: "2.7.1"`.
- The CLI follows semantic versioning. Moving the default to CLI 3.x would come with a new major version of this action.

## Requirements

- A Linux runner. The action installs packages with `apt-get` and uses `sudo` when it isn't running as root. It has been tested on Ubuntu 24.04.
- `pg_dump` at least as new as the Supabase database. The default, 17, covers projects on Postgres 15 and 17.

## Hosted option

If you'd rather not keep a workflow running, [BackupDrill](https://backupdrill.com) runs the same engine as a hosted service, with scheduled backups, automatic restore drills, alerts and emailed reports.

## License

MIT
