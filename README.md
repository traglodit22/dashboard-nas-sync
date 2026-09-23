# Archive Sync Worker

Home Assistant add-on for resumable synchronization to a mounted storage share.

## Install

Add this repository to Home Assistant:

```text
https://github.com/traglodit22/dashboard-nas-sync
```

Install **Archive Sync Worker** from the add-on store.

## Configuration

The target share must be mounted at `/share/NAS`. Store the access token in:

```text
/config/.archive-sync-token
```

The add-on reads that file as `/homeassistant/.archive-sync-token` and never stores the token in this repository.

The worker uses batches, verifies size and SHA-256, and does not delete files. Bidirectional synchronization is intentionally disabled until conflict handling is implemented.

Version 0.2.9 also supports pulling encrypted project backups. Enable
`backup_enabled` and set `backup_project_name` to a unique lowercase project
slug. Backups are stored at `/share/NAS/backups/<project>/<run>/` and are
acknowledged only after size and MD5 verification. Backup synchronization is
run before the media queue, so long media transfers do not delay backups. The
worker never receives object-storage credentials.

Version 0.3.2 adds multi-project backup pull. See
[`NAS_BACKUP_PROTOCOL.md`](NAS_BACKUP_PROTOCOL.md) for the public project API
contract and the `backup_projects_json` configuration format.

## File API and reverse tunnel (v0.5.0)

Optional HTTP file server for the synced files (read/write under `files_root`,
default `/share/NAS`), same Bearer token as the sync worker:

- `files_enabled: true` — serves `GET/HEAD/PUT/DELETE /files/<path>` on port 8099
  (Range supported, atomic uploads with MD5 receipt).
- `tunnel_enabled: true` + `tunnel_host` + `tunnel_private_key` — reverse SSH
  tunnel so the Dashboard VPS can reach the file API via `tunnel_remote_bind`
  (default `127.0.0.1:18125`) when the user is away from the home LAN.
  Use a dedicated locked-down SSH account on the VPS
  (`permitlisten="127.0.0.1:18125"`, no shell).

## Storage resilience (v0.10.41)

Service processes now refuse to write when the share is not actually mounted.
The check compares the device id (`st_dev`) of the target path with the one of
`/share` (override with `NAS_MOUNT_BASE`), so a nested destination such as
`/share/NAS/backups` is still accepted when the share is mounted. Disable the
check with `mount_check_enabled: false` if needed.

- `mount_check_enabled` (default `true`) — refuse backup/file-API writes when
  the share is not a real mount; an undeterminable state only warns.
- `import_storage_probe_timeout_seconds` (default `30`) — timeout for the
  importer's read/write probe of `import_root` before each pass.
- `import_storage_fail_limit` (default `3`) — consecutive storage failures
  (hash timeout, HTTP 503, connection error) after which the importer stops the
  pass and reports `error: хранилище недоступно` instead of spinning.

Rationale: if the share is unmounted, `/share/NAS` is a plain directory on the
HA host. Writing there fills the internal disk, makes the mount point non-empty
(which blocks the Supervisor from re-mounting the share) and silently loses
data. Backup runs now also remove stale `*.archive-sync.tmp.*` leftovers before
downloading.
