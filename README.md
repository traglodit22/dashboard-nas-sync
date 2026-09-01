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
