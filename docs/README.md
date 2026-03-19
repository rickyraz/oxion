# Oxion Docs Map

Dokumen master arsitektur ada di:

- [oxion-infra-deployment-spec.md](./oxion-infra-deployment-spec.md)

Profil produk:

- **Lite Mode**: panel FreeRADIUS-style untuk skenario kecil (deploy cepat, simple menu).
- **Platform Mode**: kapabilitas Oxion penuh untuk multi-tenant dan enterprise.

Fokus runtime plugin v1:

- **TypeScript**
- **Python**
- **Elixir**

Jalur adopsi yang disarankan:

1. Mulai dari Lite Mode.
2. Migrasi data daloRADIUS dari MySQL/MariaDB via migration wizard.
3. Naik ke Platform Mode dan konsolidasi penuh di PostgreSQL 18.

Urutan baca yang direkomendasikan:

1. [oxion-platform-overview.md](./oxion-platform-overview.md)
2. [oxion-infra-deployment-spec.md](./oxion-infra-deployment-spec.md)
3. [oxion-platform-services-spec.md](./oxion-platform-services-spec.md)
4. [oxradius-spec.md](./oxradius-spec.md)
5. [oxcore-spec.md](./oxcore-spec.md)
6. [oxolt-spec.md](./oxolt-spec.md)
7. [oxbill-spec.md](./oxbill-spec.md)
8. [oxnoc-spec.md](./oxnoc-spec.md)
9. [oxion-brand-naming.md](./oxion-brand-naming.md)
10. [oxion-plugin-architecture.md](./oxion-plugin-architecture.md)
11. [oxion-plugin-examples.md](./oxion-plugin-examples.md)
12. [plugin-manifest.schema.json](./plugin-manifest.schema.json)
13. [plugin-starter/README.md](./plugin-starter/README.md)
14. [oxion-dalo-migration-runbook.md](./oxion-dalo-migration-runbook.md)
