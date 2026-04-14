# Future Rustler NIF Pattern (External Types)

## Tujuan

Dokumen ini menyiapkan pola boundary saat package Rustler NIF benar-benar dibuat,
sambil menjaga keputusan hybrid saat ini:

- Gleam tetap jadi source of truth untuk kontrak/domain.
- TypeScript contracts + Zod tetap di-generate dari `package-interface` Gleam.
- Rust NIF dipakai untuk workload performa berat, bukan menyimpan business policy.

## Rule Penting

- Bentuk `@external(type, ...)` **bukan** sintaks Gleam yang valid.
- Pola yang benar adalah `@external(<target>, <module_or_path>, <symbol>)` ditempel pada `pub type` atau `pub fn`.
- Untuk cross-target, satu `pub type` boleh punya lebih dari satu anotasi `@external`.

## Blueprint Lokasi (Saat NIF Package Dibuat)

```text
apps/oxradius/
|-- src/oxion/radius/nif/
|   |-- rustler_types.gleam
|   `-- rustler_bridge.gleam
|-- src/oxion_radius_rustler_ffi.erl
`-- native/oxion_radius_rustler_nif/
    |-- Cargo.toml
    `-- src/lib.rs
```

## Pattern Gleam

```gleam
// apps/oxradius/src/oxion/radius/nif/rustler_types.gleam

// External type dari boundary NIF (opaque reference).
@external(erlang, "oxion_radius_rustler_ffi", "digest_ref")
@external(javascript, "../nif/rustler_js_types.mjs", "DigestRef")
pub type DigestRef

pub type DigestError {
  DigestError(code: String, message: String)
}
```

```gleam
// apps/oxradius/src/oxion/radius/nif/rustler_bridge.gleam
import oxion/radius/nif/rustler_types.{type DigestError, type DigestRef}

@external(erlang, "oxion_radius_rustler_ffi", "digest")
pub fn digest(payload: BitArray) -> Result(DigestRef, DigestError)
```

## Pattern Erlang Wrapper

```erlang
-module(oxion_radius_rustler_ffi).
-export([digest/1]).
-on_load(init/0).

init() ->
    ok = erlang:load_nif("./native/oxion_radius_rustler_nif", 0).

digest(_Payload) ->
    erlang:nif_error(not_loaded).
```

## Dampak ke Flow Codegen Saat Ini

- `pnpm run generate:contracts` tetap membaca `gleam export package-interface`.
- `pnpm run generate:zod` memetakan `generated/interfaces/*.interface.json` ke Zod.
- External type yang tidak punya constructor akan di-output sebagai `z.unknown()` pada `generated/contracts.zod.ts`.
  Ini sengaja untuk menjaga safety sampai ada representasi domain yang lebih spesifik.

## Rekomendasi Implementasi Bertahap

1. Buat wrapper API Gleam yang stabil dulu (`rustler_bridge.gleam`).
2. Jaga type domain publik tetap di Gleam (record/union), jangan expose term mentah NIF ke caller.
3. Setelah package NIF aktif, tambahkan test integration untuk jalur `@external(erlang, ...)`.
4. Jika target JS untuk module yang sama diaktifkan, sinkronkan adapter JS pada anotasi `@external(javascript, ...)`.
