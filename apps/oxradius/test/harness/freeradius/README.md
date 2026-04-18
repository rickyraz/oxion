# oxRADIUS FreeRADIUS Harness (Level B Scaffold)

Harness ini menyediakan baseline executable untuk validasi manual:

- `Status-Server` via `radclient`
- `CoA` via `radclient`
- `Disconnect` via `radclient`
- `Access-Request` via `radtest`

Tujuan scaffold:

- menyediakan struktur awal integration harness tanpa menjadi blocker CI default,
- memastikan command/payload test bisa dijalankan berulang dengan input stabil,
- memberi jejak audit yang bisa ditingkatkan ke container/device lab.

## Prasyarat

- Docker + Docker Compose
- `radclient` dan `radtest` tersedia di host (atau di runner terpisah)

## Menjalankan FreeRADIUS container lokal

```bash
docker compose -f apps/oxradius/test/harness/freeradius/docker-compose.yml up -d
```

## Menjalankan harness command

```bash
node scripts/run-oxradius-freeradius-harness.mjs --execute
```

Mode default script adalah dry-run (hanya render command). Tambahkan `--execute` untuk benar-benar menjalankan command.

## File Request Fixtures

- `requests/status-request.txt`
- `requests/coa-request.txt`
- `requests/disconnect-request.txt`

Fixture ini sengaja sederhana sebagai baseline. Tambahkan fixture vendor-specific secara bertahap setelah path dasar stabil.
