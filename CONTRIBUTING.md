# Contributing Guide

## Purpose

This document is the primary implementation rulebook for the Oxion repository.

Primary focus:

- modular and orthogonal design
- consistent code style
- every implementation phase must include testing

---

## Read Order (Required)

1. `CONTRIBUTING.md`
2. `AGENTS.md`
3. Documentation workspace main README
4. Documentation workspace MVP fast-track plan
5. Documentation workspace testing strategy
6. Documentation workspace policy schema + EBNF references

---

## Engineering Rules

- One module, one primary responsibility (do one thing well).
- Separate policy from mechanism.
- Avoid hardcoded business rules (day, speed, vendor attrs) in core.
- All behavior changes must be traceable (audit + metrics).
- All enforcement actions must be idempotent.

---

## Code Style and Structure

- Follow each language's native style (Gleam/TS/Python/Elixir) and official formatter.
- Do not add new folders/modules without clear bounded-context rationale.
- Keep vendor-specific logic in adapter/profile layers, not core logic.

---

## Mandatory Testing Per Change

Each phase implementation **must** include testing for Gleam and any touched related stack.

### Minimal matrix

- If changing `Gleam` domain/core:
  - must run `node scripts/run-gleam-all.mjs test`
  - must run `node scripts/run-gleam-all.mjs format-check`
- If changing `TypeScript`:
  - must run relevant TS unit tests
- If changing `Python`:
  - must run relevant Python unit tests
- If changing `Elixir`:
  - must run relevant ExUnit tests
- If changing policy schema/contract:
  - must run contract tests + EBNF conformance tests
- If changing RADIUS/NAS/CoA flow:
  - must run integration tests + update packet-level checklist

### Phase gate rule

For every phase in the documentation workspace MVP fast-track plan, a PR must include:

1. list of added/updated tests,
2. passing test results,
3. if any test cannot run yet, include reason + follow-up task.

Without test evidence, the phase is considered incomplete.

---

## PR Checklist (Required)

- [ ] Change scope follows module/submodule boundaries.
- [ ] No new hardcoded business rule in core.
- [ ] New/updated tests are included for changed areas.
- [ ] `node scripts/run-gleam-all.mjs test` pass.
- [ ] `node scripts/run-gleam-all.mjs format-check` pass.
- [ ] Related documentation workspace content is updated (if contract/flow changes).
- [ ] If billing contract is touched, synchronize public docs with EE private implementation notes.

---

## Commit and Review

- After relevant verification passes, create atomic commits whenever possible.
- Commit messages must be descriptive, use imperative present tense, and clearly explain `what` + `why`.
- Subject lines must be readable by international engineers without chat context.
- Reviewers may reject changes if tests are insufficient for the touched phase.
- Large cross-stack changes should be split into smaller PRs for reviewability.
