# schema

Schema area untuk kontrak eksplisit tambahan (opsional).

Aturan:

- Source of truth utama TypeScript contract saat ini adalah **public Gleam types/functions**
  di `packages/policy` dan `packages/interop`.
- Folder `schema/` tetap bisa dipakai untuk kebutuhan schema-first khusus
  (misalnya OpenAPI/JSON Schema eksternal), tapi bukan jalur utama generate types saat ini.
