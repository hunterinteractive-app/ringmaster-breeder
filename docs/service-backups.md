# Breeder service backups and account recovery

## What is implemented

`.github/workflows/nightly-service-backup.yml` runs nightly at 06:47 UTC
(02:47 Eastern daylight time / 01:47 Eastern standard time) and can be started
manually. GitHub schedules can be delayed. A successful nightly schedule targets
at most about 24 hours of lost **synced** data. It is not continuous replication
or a promise of a 24-hour recovery point when jobs fail. Recovery time depends
on database/file size and must be measured in a real replacement-project drill.

The destination is the existing Backblaze B2 backup bucket used by Show. Nightly
copies use `ringmaster-breeder/service/`; first-of-month copies use
`ringmaster-breeder/monthly/YYYY-MM/`. The workflow does not delete B2 objects.
The bucket applies separate expiration rules to each prefix, preserving Show's
existing retention.

Each archive contains:

- A consistent PostgreSQL custom-format dump of `public`, `breeder_private`,
  `auth`, `storage`, `supabase_migrations`, and `extensions`, explicitly including
  the `pgcrypto` extension required by registration referral codes.
- Cluster role definitions without role passwords.
- Original bytes for every object listed in Storage at the database snapshot,
  across all buckets, plus bucket configuration and object metadata.
- A recovery package for every Breeder owner. All packages and the database dump
  share one exported PostgreSQL snapshot, including writes happening during backup.
- The tracked source at the workflow's Git commit, its commit ID, timestamp,
  database version, file counts, and SHA-256 checksums for every payload file.

The archive is encrypted using GnuPG AES-256. The job decrypts its output and
checks every payload before upload, then downloads the B2 encrypted object and
checks it again. Only then does it publish the adjacent `.complete.json` marker.
An archive without that marker is not a completed backup. Failed jobs do not
delete earlier recovery points. Storage mutations/deletions during copying fail
the run instead of silently publishing a mismatched snapshot; retry the workflow.

**Activated:** the first production backup completed on October 19, 2026,
at 05:57 UTC (01:57 Eastern daylight time). Its encrypted B2 upload passed
read-back verification and its completion marker was published.
See the [successful production run](https://github.com/hunterinteractive-app/ringmaster-breeder/actions/runs/39207136709).
The nightly schedule is enabled on `main`. A managed replacement-project restore
drill is still required to qualify end-to-end disaster recovery.

GitHub does not return stored secret values. Reuse requires authorized re-entry
or re-encryption for the destination repository. Breeder uses its own encryption
passphrase and a B2 key with read/write access restricted to its prefix.

## One-time setup

Use the same **private bucket and B2 endpoint** as Show. Prefer a separate B2 key
restricted to this bucket and the `ringmaster-breeder/` filename prefix, with
read/list/write capabilities and no delete capability. Keep its recovery copy in
the password manager, outside GitHub and Supabase. Do not make the bucket public.

Configure these repository Actions secrets in `hunterinteractive-app/ringmaster-breeder`:

| Secret | Value |
| --- | --- |
| `SUPABASE_DB_URL` | Breeder's direct connection URI or **session** pooler URI on port 5432, with URL-encoded database password; require TLS with `?sslmode=require` |
| `SUPABASE_SERVICE_ROLE_KEY` | Breeder's server-side service-role/secret API key, for original Storage bytes |
| `BACKUP_PASSPHRASE` | A unique random single-line passphrase of at least 32 characters, saved separately in the password manager |
| `B2_KEY_ID` | Restricted B2 application key ID |
| `B2_APPLICATION_KEY` | Restricted B2 application key secret |
| `B2_REGION` | Existing bucket's region |
| `B2_BUCKET` | Existing private backup bucket name |
| `B2_ENDPOINT` | Its HTTPS S3 endpoint, such as `https://s3.us-west-004.backblazeb2.com` |

The source project URL/reference is fixed to Breeder (`aqfsrolvaewcpkdkttiz`). Do
not use Show's database URI or service key. Transaction pooling (port 6543) cannot
hold the exported snapshot session and is rejected. CI requires PostgreSQL 17
clients and GnuPG; the hosted Ubuntu runner provides AWS CLI v2. No backup keys
belong in Flutter, source control, review attachments, or unencrypted artifacts.

The following custom B2 lifecycle rules were saved and read back on October 19,
2026. Keep the prefixes separate; a broader overlapping rule could shorten
monthly retention.

| Prefix | Days after upload until hidden | Days hidden until deleted |
| --- | ---: | ---: |
| `ringmaster-breeder/service/` | 90 | 1 |
| `ringmaster-breeder/monthly/` | 365 | 1 |
| `ringmaster-show/database/` (unchanged) | 399 | 1 |

Nightly backups remain visible for 90 days and monthly copies for 365 days
(approximately 12 months). B2 permanently deletes the hidden copy one day later;
lifecycle processing is asynchronous. These bucket rules apply to archives and
their completion markers. Do not replace the custom rules with a bucket-wide rule.

On the first day of each month in `America/Indiana/Indianapolis`, the backup job
retains the first successfully verified nightly archive as that month's copy.
It copies the exact encrypted bytes, verifies B2 read-back, and publishes a
separate completion marker. A repeated first-day run verifies the existing monthly
archive and preserves it instead of overwriting it. An access error or corrupt
monthly copy fails the job and is not treated as a missing backup. The workflow's
concurrency group serializes writers. If all first-day runs fail or the schedule
is missed, the job does not label a later snapshot as the first; alert/retry on the
first day or manually retain a verified first-day archive from the daily history.
The first scheduled monthly copy after activation is November 1, 2026.

Full file copies are stored nightly, so budget for approximately 90 daily copies
plus 12 monthly copies of the database and stored files, with a short hidden-file
deletion grace period.
Use B2 Object Lock if stronger protection from administrator deletion is needed;
retention/immutability are bucket settings, not something the writer enforces.

Run **Back up Breeder service to Backblaze B2** manually. Check that the archive
and completion marker appear in the Breeder prefix. Download and decrypt that
first real archive and perform the replacement-project drill below. Enable
GitHub Actions failure notifications for the responsible administrator; verify
that the latest completed B2 snapshot is less than 36 hours old daily. GitHub
can disable schedules on inactive repositories, so a successful past run is not
proof the schedule is still active. No independent freshness alert is installed.

Keep Supabase's own backups/PITR enabled as an additional recovery option where
available. These B2 copies remain useful during a Supabase outage or account loss.

## Download and inspect a recovery point

Use a trusted administrator machine with PostgreSQL 17+ clients, Python 3.12+,
GnuPG, AWS CLI v2, and enough private disk space for the encrypted copy, plaintext
archive, extracted files, and database. Use a private directory outside the repo
or the ignored `.backups/` directory. Set secrets through a password manager or
protected environment, not command arguments or shell history. B2 tools use
`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, and `AWS_DEFAULT_REGION`.

1. List `ringmaster-breeder/service/` in B2 and select a completed snapshot before
   the incident. Inspect the marker's `snapshot_at`, not the download time.
2. Download its `.tar.gz.gpg` and `.complete.json` files. Compare the encrypted
   SHA-256 against the marker (for example, `shasum -a 256 ARCHIVE`).
3. Set `BACKUP_PASSPHRASE` securely, then run:

   ```sh
   python3 tool/backups/service.py extract /private/recovery/ARCHIVE.tar.gz.gpg \
     --output /private/recovery/verified
   ```

Extraction verifies the encryption integrity, rejects unsafe archive paths and
links, and verifies every checksum. Output directories must not already exist.
The output contains every customer's private data: restrict access and securely
remove the plaintext after the incident. The source tar is tracked source only;
it deliberately does not contain provider credentials or ignored local files.

## Restore one owner's records

This is administrator-assisted **snapshot record recovery**, not automatic
per-user restore and not an exact account rollback. It inserts missing backup
records and replaces matching records with the selected point's values. Records
created after the point stay in place. That means newer sale payments/history
also remain: reconcile financial totals and animal sale status before reopening
the account. For an exact rollback or recovery of a subset of records, review a
custom plan in a scratch database instead of deleting an owner's current data.

The recovery unit is the **herd owner/family**, not one invited member's login.
Recovering shared herd data is visible to everyone who currently has access to it.
Authentication identities, active licenses, legal acceptances, invitations and
revocations, admin privileges, calendar tokens, cross-app connection settings,
background jobs, sent-email records, and sync receipts are preserved as they are
now. Personal contact/profile details also remain current. Recovery never resends
an email or requeues old jobs. The selected records include herds, contacts,
animals, management details, pedigree links and drafts, body/feed/litter weights,
wool records/settings, health history, breeding (including imported litters with
an unknown sire), sales, and imports with original Rabbit Register file bytes.
Generated file fingerprints are recomputed by PostgreSQL during recovery.
Billing price campaigns/notices and registration/referral state remain current
during owner recovery; the whole-service dump includes all of these tables.

1. Identify the owner by `public.users.id`, not email alone or a family member's
   Auth UUID. Owner package filenames are SHA-256 hashes of that exact ID. Read
   the package's `owner.id` and `owner.auth_user_id` and verify the identity.
2. Save a fresh whole-service backup before restoring. Arrange maintenance for
   this owner and all family devices. Sync or export unsent work and stop
   background jobs/writers; the tool requires this operational step. It does not
   install an account maintenance gate. Database locks serialize the actual
   transaction, but do not stop writers that return afterward. These table locks
   briefly block writes across all households, so schedule a quiet maintenance window.
3. Start with a scratch clone of the current database. Set `RESTORE_DB_URL` to
   its direct/session URI and run the rollback-only review:

   ```sh
   python3 tool/backups/owner.py /private/recovery/verified/owners/OWNER_HASH.json \
     --output /private/recovery/review
   ```

   Read `review.json` and `restore.sql`. Dry run executes the real constraints and
   rolls everything back, including trigger/version changes. Inactive/deleted
   accounts, changed Auth links, mismatched table/column types, IDs now owned by
   another family, and incomplete/cross-family relationships require manual review.
   For schema drift, migrate a scratch restoration to the current schema and
   generate a new owner package with the reviewed `export_owner` utility.
4. Restore this owner's referenced photos/health attachments. Set
   `RESTORE_DB_URL`, `RESTORE_SUPABASE_URL`, and `RESTORE_SERVICE_ROLE_KEY` to the
   intended target. This writes **new immutable paths**, preserving current
   Storage bytes, and verifies each uploaded object's bytes:

   ```sh
   python3 tool/backups/files.py /private/recovery/verified \
     --owner /private/recovery/verified/owners/OWNER_HASH.json \
     --confirm-project aqfsrolvaewcpkdkttiz \
     --output /private/recovery/prepared
   ```

   The target URL must match the confirmed project. Run the files step even if
   the account has no attachments. It produces a rewritten `prepared/owner.json`
   plus an `uploads.json` journal. Missing source files fail recovery. A failed
   file/database step can leave new, unreferenced files; the journal identifies
   them for reviewed cleanup. Existing objects are never overwritten/deleted.
5. Dry-run the prepared package again, review it, then commit with the exact
   owner ID and maintenance acknowledgment:

   ```sh
   python3 tool/backups/owner.py /private/recovery/prepared/owner.json \
     --output /private/recovery/final-review
   python3 tool/backups/owner.py /private/recovery/prepared/owner.json \
     --output /private/recovery/applied \
     --apply --confirm-owner OWNER_ID --maintenance-confirmed
   ```

   Set `RESTORE_DB_URL` to the intended production target only for that final
   operation. The restore is one transaction with ownership checks after locking;
   SQL constraints stay enabled. User workflow triggers are suppressed only
   inside that transaction to avoid regenerating sales/audit activity. Original
   normal trigger state is required and restored. Animal revisions, sale versions,
   and breeding revisions advance; offline table versions increment to invalidate old data.
6. Check animals, parents, history, payments, and file access with the owner;
   compare another household before/after. All affected devices must reconnect
   and complete a fresh download before editing again. Do not replay unsent
   pre-restore work blindly: it can reintroduce the data being recovered from.

There is no customer-facing restore button and no new public database endpoint.
An individual account that was intentionally deleted is not revived by this tool.

## Whole-service disaster recovery

First restore to a **replacement** project, never overwrite the only live copy.
Keep the original service isolated until the replacement is validated. Pause
outbound email, external jobs, Show connections, and automated deletion before
starting any recovered application. A database backup does not include SMTP,
Edge Function secrets, Cloudflare configuration, Supabase project/API settings,
custom-role passwords, or DNS; retain their configuration and recovery credentials
separately in the password manager. Unsent work that existed only on a user's
device is outside a server backup and needs its offline recovery export.

1. Decrypt/verify a completed archive. Use its `source.tar` and migration history
   to identify the matching application/backend version.
2. Restore `database.dump` into a fresh isolated PostgreSQL 17+ database first.
   Create required extensions/roles from reviewed `roles.sql` as appropriate.
   For a local drill on a cluster where fixture roles already exist, first drop
   the default **empty** `public` schema from the newly created disposable target
   (`DROP SCHEMA public;` without `CASCADE`); the archive recreates it:

   ```sh
   # Supply PGHOST/PGPORT/PGUSER/PGPASSWORD securely; target must be empty.
   pg_restore --exit-on-error --no-owner --no-privileges \
     --dbname=DISPOSABLE_EMPTY_DATABASE /private/recovery/verified/database.dump
   ```

   `--no-privileges` is for this sandbox drill only. Production requires restoring
   and checking the intended grants, RLS, functions, and triggers. Managed Supabase
   roles/schemas need the provider's migration procedure; do not blindly replay
   every managed role definition into a fresh Supabase project.
3. Provision a replacement Supabase project, with the matching supported database
   version/extensions. Follow Supabase's current backup/migration guidance for
   managed Auth/Storage schemas. Use a reviewed `pg_restore --list` selection to
   load app schema/data and preserved Auth users/identities, excluding old managed
   migration/session tables as required by the target. Restore Auth users/identities
   before dependent app rows, and review managed-schema triggers and Storage RLS
   from the repository migrations. Require a fresh sign-in; do not reinstate old
   sessions/refresh tokens or revive deleted/revoked account access automatically.
4. **Do not restore `storage.objects` rows as a substitute for uploading files.**
   Recreate bucket settings from `buckets.json` in the replacement, leave object
   metadata empty, then upload originals using the Storage API. Set the replacement
   `RESTORE_SUPABASE_URL` and `RESTORE_SERVICE_ROLE_KEY`:

   ```sh
   python3 tool/backups/files.py /private/recovery/verified --whole-service \
     --confirm-project REPLACEMENT_PROJECT_REF \
     --output /private/recovery/replacement-files
   ```

   Whole-service file restore refuses the current Breeder project and never
   overwrites objects. Review any failure using its upload journal before retrying.
5. Restore/deploy Edge Functions and application source; recreate server secrets,
   Auth/email configuration, API exposure, storage policies, and deployment
   configuration. Set the new project URL/public key in the application and new
   server credentials in Edge Functions/GitHub. Do not publish the service key.
6. Compare per-table counts, owner identity links, relationship samples and original
   file hashes; test fresh sign-in, family isolation/revocation, pedigree rendering,
   sales, attachments and offline redownload. Check that old jobs/emails/deletion
   requests cannot run unexpectedly. Only then cut over DNS/deployment and reopen
   background integrations in a controlled order.

The included local drill verifies a full PostgreSQL archive round trip and
snapshot consistency using synthetic data. The managed replacement-project
migration, real B2 credentials/upload, real Storage API restore, and sign-in must
still be rehearsed in a non-production Supabase project before production
recovery is considered qualified. Repeat the drill quarterly and after major
schema changes, recording counts, hashes, elapsed time and the tested commit.

## Validation and schema maintenance

```sh
python3 -m unittest discover -s test/backups -v
# Against an isolated current schema clone with synthetic records only:
BACKUP_TEST_DB_URL=LOCAL_DISPOSABLE_URI python3 -m unittest discover -s test/backups -v
```

Integration tests refuse databases that are not on loopback or not named
`breeder_backup_test`. The full-service drill commits its synthetic fixture and
truncates it afterward, and creates/drops `breeder_backup_restore_test` on that
same disposable cluster. Never point it at a valuable database.

The backup deliberately fails on any unclassified new/missing `public` or
`breeder_private` table and names the affected tables in its error. Ordinary
deployment CI also checks explicit table additions in migrations against the
classification lists, so omissions can be caught before the next nightly run.
When adding tables, update the recovery/preservation list
in `tool/backups/owner.py`, its ownership predicate and dependency order, then
rerun the recovery drill. This prevents a newly added feature from silently
disappearing from individual recovery. Ordinary backup runs are read-only on the
source database and do not change its schema, access policies, or records.

References: [Supabase backups](https://supabase.com/docs/guides/platform/backups),
[Supabase migration and restore](https://supabase.com/docs/guides/platform/migrating-within-supabase/backup-restore),
[PostgreSQL pg_dump](https://www.postgresql.org/docs/17/app-pgdump.html).
