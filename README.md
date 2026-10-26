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

## HA Reverse Tunnel (второе дополнение в этом репозитории)

`ha_tunnel/` — отдельное дополнение **HA Reverse Tunnel**: постоянный reverse
SSH туннель с HA Green на VPS, чтобы `ha.plansolo.ru` и MiWiFi VPN API в
дашборде работали без включённого Mac.

```text
127.0.0.1:18123 на VPS → HA 8123          (nginx, бэкенд, home-events)
127.0.0.1:18124 на VPS → 192.168.31.1:80  (MiWiFi VPN API)
```

Ключ генерируется на самом HA (`/data/ssh/id_ed25519`), в лог печатается только
публичная часть (`PUBKEY: …`); на VPS она вносится пользователю `hatunnel`
скриптом `deploy/setup-ha-tunnel-user.sh` из репозитория DashBoardTrag.
Подробности — [`ha_tunnel/DOCS.md`](ha_tunnel/DOCS.md).

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

## С v0.13.0: копия NAS в Google Drive (`archive-sync-gdrive`)

Сервис копирует верхние папки `files_root` (`/share/NAS`) в два аккаунта Google
Drive (`gdrive1`, `gdrive2`) через `rclone sync`, без шифрования: в Drive файлы
лежат как есть, в папке `NAS/`. Удалённое и перезаписанное на NAS не пропадает:
прежняя копия переезжает в `_versions/<YYYY-MM-DD>/<HHMMSS-id>/` (дата и время
прогона, UTC; у каждого прогона своя папка) того же аккаунта и хранится `gdrive_versions_days` дней. Прогон не начинается, если шара
не смонтирована (`mount_check_enabled`) или папка плана пуста. Итог прогона —
`POST /api/sync/nas/gdrive` (агент `nas-gdrive` в дашборде, алерты в Telegram).

| Опция | По умолчанию | Что делает |
| --- | --- | --- |
| `gdrive_enabled` | `false` | Включить сервис |
| `gdrive_rclone_config` | `/homeassistant/.rclone/rclone.conf` | Конфиг rclone с секциями `[gdrive1]`, `[gdrive2]` (токены Google; в лог и отчёт не попадают) |
| `gdrive_plan_json` | `[]` | План раскладки: `[{"dir": "Галерея", "remote": "gdrive1"}, {"dir": "Видео", "remote": "gdrive2"}]`; `dir` — верхняя папка `files_root`. Пустой план — «разведка»: только размеры папок и место в Drive |
| `gdrive_window_start_utc` | `22` | Начало ночного окна, час UTC (22 = 01:00 по Минску) |
| `gdrive_window_hours` | `6` | Длина окна; прогон останавливается к его концу (`--max-duration`) |
| `gdrive_max_transfer_gb` | `700` | Предел выгрузки на аккаунт за прогон (лимит Google — 750 ГБ/сутки); остальное докачается в следующие ночи |
| `gdrive_max_delete` | `2000` | Предел удалений (переносов в `_versions`) за прогон; больше — прогон останавливается со статусом «слишком много удалений» |
| `gdrive_bwlimit` | `""` | Ограничение скорости rclone (`--bwlimit`, например `8M`); действует **на каждый аккаунт** — аккаунты качаются параллельно |
| `gdrive_versions_days` | `90` | Сколько дней хранить `_versions/<дата>/` (папка дня удаляется целиком); чистка раз в неделю, удаляется насовсем (мимо корзины Drive) |

Папки вне плана не копируются и в Drive не трогаются; в отчёте они видны с
размером. Размеры папок на NAS пересчитываются раз в неделю (du по SMB долгий), объём в Drive — раз в сутки.

### Подключение Google (делает владелец)

Токены Google вводит и хранит только владелец; Claude их не видит.

1. На Mac: `brew install rclone`.
2. `rclone authorize "drive"` — откроется браузер: войти в **первый** аккаунт
   Google и разрешить доступ. В терминале появится JSON вида
   `{"access_token":"…","token_type":"Bearer","refresh_token":"…","expiry":"…"}` —
   скопировать его целиком (одной строкой).
3. Ещё раз `rclone authorize "drive"`, в браузере войти во **второй** аккаунт
   (если открылся первый — сменить аккаунт или открыть ссылку в приватном окне),
   скопировать второй JSON.
4. На HA (File editor или Samba, папка `config`) создать
   `/homeassistant/.rclone/rclone.conf`:

   ```ini
   [gdrive1]
   type = drive
   scope = drive
   token = {"access_token":"…","token_type":"Bearer","refresh_token":"…","expiry":"…"}

   [gdrive2]
   type = drive
   scope = drive
   token = {"access_token":"…","token_type":"Bearer","refresh_token":"…","expiry":"…"}
   ```

   Свой OAuth-клиент (рекомендуется, если в отчёте `rateLimitExceeded`): в Google
   Cloud Console создать OAuth client «Desktop app», в шаге 2 выполнить
   `rclone authorize "drive" "<client_id>" "<client_secret>"` и добавить в обе
   секции строки `client_id = …` и `client_secret = …`.
5. В настройках add-on: `gdrive_enabled: true`, план пока `[]`, перезапустить
   add-on. Первый прогон («разведка») идёт сразу: в дашборде появятся размеры
   верхних папок и свободное место в каждом Drive. По ним заполнить
   `gdrive_plan_json` с запасом ≥ 10% на аккаунт и перезапустить add-on.
6. Если токен отозван (статус `auth_error`) — повторить шаг 2 для этого аккаунта
   и заменить строку `token = …` в его секции.

### Восстановление

- Один файл или папку — скачать из веб-интерфейса Drive (`NAS/…`) или из
  `_versions/<дата>/<прогон>/…`, если файл удалили или перезаписали на NAS.
- Папку целиком — rclone с тем же конфигом (в терминале add-on или на Mac с
  копией конфига):

  ```bash
  rclone --config /homeassistant/.rclone/rclone.conf copy \
    "gdrive1:NAS/Галерея/2024" "/share/NAS/Галерея/2024" --progress
  # прежняя версия удалённого/перезаписанного файла:
  rclone --config /homeassistant/.rclone/rclone.conf copy \
    "gdrive1:_versions/2026-10-18/220005-ab12cd/Галерея/2024/01" "/share/NAS/Галерея/2024/01"
  ```

  `copy` ничего не удаляет на NAS; `sync` в обратную сторону не использовать.
