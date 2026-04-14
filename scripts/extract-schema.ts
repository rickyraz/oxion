/**
 * Legacy placeholder from schema-first approach.
 *
 * Current type generation uses Gleam-first hybrid flow in:
 * - scripts/generate-contracts.mjs
 *   - gleam export package-interface
 *   - emit generated/interfaces/*.json
 *   - emit generated/contracts.generated.ts
 * - scripts/generate-zod.ts
 *   - map generated/interfaces/*.json -> generated/contracts.zod.ts
 */
export {};
