# oxRADIUS FreeRADIUS rlm_rest Harness

Harness ini membuktikan jalur:

```text
radtest/radclient
  -> FreeRADIUS 3.2.3 container
  -> rlm_rest
  -> local oxRADIUS callback server
  -> evidence JSONL
```

Tujuannya adalah memvalidasi kontrak awal `rlm_rest` sebelum API runtime production di `apps/oxradius` dibuat.

## Menjalankan

```bash
just rlm-rest-harness --execute
```

Harness akan:

- menjalankan `apps/oxradius` Policy API runtime pada `0.0.0.0:18088`,
- menjalankan FreeRADIUS container pada UDP `18120` dan `18130`,
- mengirim `Access-Request` via `radtest`,
- mengirim `Accounting-Request` via `radclient`,
- memastikan `Access-Accept` berisi `Reply-Message` dari JSON response callback,
- menulis evidence ke `evidence/oxradius-rlm-rest-callback/callbacks.jsonl`,
- mematikan container dan callback server setelah selesai.

Untuk memakai callback server Node lama sebagai pembanding:

```bash
just rlm-rest-harness --execute --backend callback
```

## Kontrak Callback Tahap 1

`authorize` callback mengembalikan JSON attribute yang diparse oleh `rlm_rest`:

```json
{
  "Reply-Message": {
    "op": ":=",
    "value": ["oxRADIUS callback accepted"]
  }
}
```

FreeRADIUS site config tidak meng-hardcode `Reply-Message`; test harus gagal jika response callback tidak diparse menjadi reply attribute.

## Remote Follow-up

Untuk remote FreeRADIUS, jalankan callback server dan expose via tunnel:

```bash
OXRADIUS_RLM_REST_TOKEN='change-me-lab-token' just rlm-rest-callback-server
cloudflared tunnel --url http://127.0.0.1:8088
```

Lalu arahkan remote `rlm_rest` ke URL Cloudflare sesuai runbook:

```text
docs/operations/freeradius-remote-access-wsl.md
```

Jika quick tunnel `trycloudflare.com` tidak resolve dari WSL, gunakan named Cloudflare Tunnel atau jalankan callback server di host publik/VPS.
