# Dashboard NAS Sync

Home Assistant add-on for resumable, logical-name synchronization from the private Dashboard/GCS archive to a mounted NAS share.

## Install

Add this repository to Home Assistant:

```text
https://github.com/traglodit22/dashboard-nas-sync
```

Install **Dashboard NAS Sync** from the add-on store.

## Configuration

The NAS must be mounted at `/share/NAS`. Store the Dashboard WebDAV token in:

```text
/config/nas-sync-token
```

The add-on reads that file as `/homeassistant/nas-sync-token` and never stores the token in this repository.

The first supported direction is Dashboard/GCS to NAS. It uses batches, verifies size and SHA-256, and does not delete files. Bidirectional synchronization is intentionally not enabled until conflict handling is implemented.
