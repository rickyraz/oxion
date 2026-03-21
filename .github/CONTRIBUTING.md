# Contributing

Silakan baca dokumen utama berikut sebelum implementasi:

1. [`/CONTRIBUTING.md`](../CONTRIBUTING.md)
2. [`/AGENTS.md`](../AGENTS.md)
3. [`/docs/README.md`](../docs/README.md)
4. [`/docs/policies/oxion-mvp-fasttrack-plan.md`](../docs/policies/oxion-mvp-fasttrack-plan.md)
5. [`/docs/operations/oxion-testing-strategy.md`](../docs/operations/oxion-testing-strategy.md)
6. [`/docs/policies/collection-policy.schema.json`](../docs/policies/collection-policy.schema.json)
7. [`/docs/policies/collection-policy-ebnf.md`](../docs/policies/collection-policy-ebnf.md)

Rule paling penting:

- Setiap perubahan behavior wajib disertai testing pada stack terkait.
- Tidak ada hardcoded business rule di core.
- Setelah verification lulus, usahakan commit atomik dengan message yang deskriptif dan berstandar engineering internasional.
