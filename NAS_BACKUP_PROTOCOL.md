# NAS Backup Protocol

This protocol lets a project publish encrypted backup archives for a trusted
home NAS without giving the NAS any cloud credentials — and without any cloud
storage at all. Dashboard acts as the authenticated transport relay: projects
push encrypted archives to Dashboard, the pull-only NAS agent downloads them.

## Transport

1. The project creates a backup archive locally and encrypts it.
2. The project pushes the archive to Dashboard:
   `POST /api/sync/nas/backups/upload` (see "Upload endpoint" below).
   Dashboard stores it in a local transport directory (`BACKUP_TRANSPORT_DIR`,
   must not be inside `UPLOAD_DIR`).
3. The NAS agent requests `GET /api/sync/nas/backups/manifest` with the
   dedicated NAS token and `X-NAS-Agent-Id`.
4. The response contains deterministic paths, sizes, MD5/SHA-256, object
   generations and token-authorized download URLs
   (`GET /api/sync/nas/backups/download`, Range supported).
5. The agent downloads to a temporary file, verifies size and MD5, calls
   `sync`, atomically renames the file, and posts a receipt to
   `POST /api/sync/nas/backups/complete`.
6. Dashboard deletes the transport object only after the receipt is accepted
   and has been present for at least 24 hours (explicit admin release
   operation). Retention never removes an unverified transport object.

## Upload endpoint

`POST /api/sync/nas/backups/upload`

Auth: same as the manifest — `Authorization: Bearer <NAS token>` and
`X-NAS-Agent-Id`. Each project uses its own token and `agent_id`.

Metadata goes in headers, the encrypted archive is the raw request body
(`Content-Type: application/octet-stream`, streamed, so multi-GB archives are
fine):

- `X-Backup-Project`: lowercase slug, e.g. `photohub` (determines the NAS path).
- `X-Backup-Run-Id`: shared stamp of the backup run, e.g. `2026-09-03T04-00-00`.
- `X-Backup-Role`: object role within the run, e.g. `database`, `files`.
- `X-Backup-File-Name`: archive file name, e.g. `database.sql.gz.enc`.
- `X-Backup-Md5` (optional), `X-Backup-Sha256` (optional): declared checksums;
  a mismatch rejects the upload with 422 and removes the partial file.

Example:

```bash
MD5=$(md5sum database.sql.gz.enc | cut -d' ' -f1)
SHA=$(sha256sum database.sql.gz.enc | cut -d' ' -f1)

curl -fsS -X POST "https://<dashboard-host>/api/sync/nas/backups/upload" \
  -H "Authorization: Bearer <NAS_TOKEN>" \
  -H "X-NAS-Agent-Id: <project-agent-id>" \
  -H "X-Backup-Project: photohub" \
  -H "X-Backup-Run-Id: $(date -u +%FT%H-%M-%S)" \
  -H "X-Backup-Role: database" \
  -H "X-Backup-File-Name: database.sql.gz.enc" \
  -H "X-Backup-Md5: $MD5" \
  -H "X-Backup-Sha256: $SHA" \
  -H "Content-Type: application/octet-stream" \
  --data-binary @database.sql.gz.enc
```

Semantics:

- Idempotent per (agent, project, run id, role): re-upload replaces the
  previous archive atomically.
- Limits: per-object `BACKUP_UPLOAD_MAX_BYTES` (default 10 GiB) and per-project
  transport quota `BACKUP_PROJECT_QUOTA_BYTES` (default 50 GiB).
- Uploads go to a temporary file, checksums and size are verified, `fsync`,
  atomic rename. Partial or mismatched uploads are deleted.
- The project cannot choose the destination path: the server derives it as
  `backups/<project>/<run_id>/<file_name>`. There is no read, listing or
  delete operation on this endpoint — write-only.
- If the upload fails (Dashboard unreachable), retry later from the project's
  cron; Dashboard must be reachable at push time.

## Security requirements

- The NAS agent is pull-only and never receives any upstream credentials;
  download URLs carry a per-object random token issued only via the
  authenticated manifest.
- Projects only ever send ciphertext; decryption keys never leave the project.
- The project must generate run ids and file names; the NAS must not submit
  paths.
- Receipts are checked against the project database and current object
  metadata (size, MD5, generation) before they are accepted.
- Secrets and environment files must be encrypted before backup.
- Each project should use a separate `agent_id` and token.
- A backup is complete only when every archive belonging to the same run has
  an accepted receipt.

## Other projects

A project joins by getting its own NAS token + `agent_id` from the Dashboard
admin and calling the upload endpoint above. The NAS side needs nothing new:
the same add-on instance picks the objects up from the shared manifest.

Alternatively, a project may keep exposing its own
`GET /api/sync/nas/backups/manifest` and `POST /api/sync/nas/backups/complete`
(legacy pull contract). In that case it is registered in the add-on via
`backup_projects_json` with an independent token file and worker identity:

```json
[
  {
    "slug": "vboost",
    "service_url": "https://vboost.example.com",
    "token_file": "/homeassistant/.vboost-nas-token",
    "worker_id": "vboost-nas"
  }
]
```

Tokens are stored only in Home Assistant files. Do not commit them or send
them in chat. The add-on handles backup projects sequentially before its
media queue; a failing backup project no longer blocks media sync.

The NAS layout is always explicit: `/share/NAS/backups/<project>/<run>/`.
For example, Dashboard uses `/share/NAS/backups/dashboard/<stamp>/`, while a
second project uses `/share/NAS/backups/photohub/<stamp>/`.
