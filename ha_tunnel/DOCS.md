# HA Reverse Tunnel

Дополнение для Home Assistant OS: держит **постоянный** reverse SSH туннель с
HA Green на VPS, чтобы `ha.plansolo.ru` и MiWiFi VPN API в дашборде не зависели
от включённого Mac.

```
HA Green ──ssh -R──▶ VPS 135.106.197.184
   127.0.0.1:18123 на VPS → HA 127.0.0.1:8123   (nginx ha.plansolo.ru, бэкенд, home-events)
   127.0.0.1:18124 на VPS → роутер 192.168.31.1:80 (MiWiFi VPN API)
```

## Установка

1. Репозиторий дополнений `https://github.com/traglodit22/dashboard-nas-sync`
   уже добавлен в HA (там же `Archive Sync Worker`). Обновите магазин:
   Настройки → Дополнения → Магазин → ⋮ → «Перезагрузить» (или `ha store reload`).
2. Установите **HA Reverse Tunnel** (`ha apps install 3076975b_ha_tunnel`).
3. Запустите. В логе появится строка `PUBKEY: ssh-ed25519 AAAA...`.
   Ключ сгенерирован **на самом HA** и лежит в `/data/ssh/id_ed25519`; приватная
   часть никогда не покидает устройство.
4. На VPS внесите этот публичный ключ пользователю `hatunnel`:
   ```bash
   bash deploy/setup-ha-tunnel-user.sh 'ssh-ed25519 AAAA... ha-tunnel@homeassistant'
   ```
5. Перезапустите дополнение. В логе должно быть `ssh -N -R 127.0.0.1:18123:...`.

## Параметры

| Опция | По умолчанию | Смысл |
| --- | --- | --- |
| `ssh_host` | `135.106.197.184` | VPS |
| `ssh_port` | `2222` | второй порт sshd (исходящий 22 у владельца нестабилен) |
| `ssh_user` | `hatunnel` | отдельный пользователь без shell, только туннель |
| `ha_remote_bind` | `127.0.0.1:18123` | порт на VPS для HA (менять нельзя — nginx и бэкенд) |
| `ha_local` | `127.0.0.1:8123` | HA внутри хоста (дополнение в `host_network`) |
| `router_remote_bind` | `127.0.0.1:18124` | порт на VPS для MiWiFi VPN API |
| `router_local` | `192.168.31.1:80` | админка Xiaomi-роутера |
| `server_alive_interval` | `15` | keepalive клиента |
| `server_alive_count_max` | `3` | сколько keepalive подряд можно пропустить |

## Поведение

- `ExitOnForwardFailure=yes`: если порт на VPS занят (например, ещё живёт
  туннель с Mac), ssh выходит и повторяет попытку через 15 с — молчаливого
  «туннель есть, а проброса нет» не бывает.
- Роутер проверяется отдельно: если `192.168.31.1:80` не отвечает, туннель
  поднимается без второго проброса, чтобы не терять HA.
- Если HA ещё не слушает `127.0.0.1:8123` (сразу после загрузки), скрипт ждёт
  до минуты, затем всё равно поднимает проброс.
- Со стороны VPS мёртвую сессию добивает sshd: `ClientAliveInterval 15` ×
  `ClientAliveCountMax 3` = ≤45 с до разрыва и освобождения портов
  (`deploy/setup-ha-tunnel-user.sh` в репозитории DashBoardTrag).

## Почему не autossh

`autossh -M 0` — обёртка ровно над этим циклом перезапуска ssh, но при занятом
порту она молотит попытки без паузы. Здесь обычный `ssh` в цикле с паузой 15 с,
а s6-overlay перезапускает сам сервис, если умрёт скрипт.

## Обновление (важно)

Дополнение собирается **локально на устройстве** (GitHub Release не публикуется),
поэтому после `git push` в этот репозиторий HA не подхватит код сам:

```bash
ha store reload
ha apps rebuild 3076975b_ha_tunnel   # пересборка образа из нового кода
ha apps restart 3076975b_ha_tunnel
```

Проверка после обновления: `ha apps logs 3076975b_ha_tunnel | tail` — строка
`ssh -N -R ...` без `Permission denied` / `remote port forwarding failed`.

`boot: auto` — туннель поднимается сам после перезагрузки HA OS;
`watchdog: true` — Supervisor перезапускает дополнение, если контейнер умер.
Здоровье самого туннеля (а не контейнера) стережёт watchdog на VPS:
`systemctl status ha-tunnel-watchdog.timer` (из `deploy/setup-ha-tunnel-user.sh`).

## Логи

```bash
ha apps logs 3076975b_ha_tunnel        # поток
ha apps logs 3076975b_ha_tunnel | grep PUBKEY
```

## Удаление

```bash
ha apps stop 3076975b_ha_tunnel
ha apps uninstall 3076975b_ha_tunnel
```
