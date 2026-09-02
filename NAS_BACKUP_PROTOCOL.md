# Multi-Project NAS Backup Protocol

The Home Assistant add-on pulls backup archives from each project. Production
VPS instances never need a NAS URL, NAS IP, SSH access, VPN route, Telegram ID,
or object-storage credentials.

## NAS layout

Every project uses a unique lowercase slug:

```text
/share/NAS/backups/<project>/<run-stamp>/
```

Examples: `dashboard`, `vboost`, `photohub`, `smmlaba`.

## Project API contract

Each project exposes these endpoints over its existing public HTTPS URL:

```text
GET  /api/sync/nas/backups/manifest
POST /api/sync/nas/backups/complete
```

The manifest response must be:

```json
{
  "schemaVersion": 1,
  "runs": [{
    "runId": "uuid",
    "stamp": "2026-09-02T00-00-00-000Z",
    "kind": "daily",
    "createdAt": "2026-09-02T00:00:00.000Z",
    "objects": [{
      "role": "database",
      "key": "internal-object-key",
      "relativePath": "vboost/2026-09-02T00-00-00-000Z/database.sql.gz",
      "sizeBytes": 123456,
      "md5Hex": "32-lowercase-hex",
      "gcsGeneration": "immutable-version",
      "downloadUrl": "short-lived-https-url"
    }]
  }]
}
```

The add-on downloads each object to a temporary file, verifies size and MD5,
calls `sync`, atomically renames it, then sends this receipt to `complete`:

```json
{
  "receipts": [{
    "runId": "uuid",
    "role": "database",
    "key": "internal-object-key",
    "sizeBytes": 123456,
    "md5Hex": "32-lowercase-hex",
    "gcsGeneration": "immutable-version"
  }]
}
```

Projects must validate every receipt server-side and store an idempotent NAS
acknowledgement. Do not delete transport copies until every object in a run is
acknowledged and at least 24 hours have passed.

## Add-on configuration

The existing Dashboard fields remain compatible. Add external project backups
to `backup_projects_json`; one entry uses an independent token file and worker
identity:

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

Tokens are stored only in Home Assistant files. Do not commit them or send them
in chat. The add-on handles projects sequentially before its Dashboard media
queue.
