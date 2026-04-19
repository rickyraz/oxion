# AGENTS.md

## Scope
Frontend guidance for `frontend/platform` (Solid.js + Tailwind CSS).
This document complements workspace-level guidance in root `AGENTS.md`.

## Stack
- Solid.js
- TypeScript (strict)
- Tailwind CSS
- TanStack Router

## Rules
- Prefer functional components.
- Use `createSignal()` for reactive state.
- Use `.tsx` extension for files with JSX.
- Keep TypeScript strict checks enabled.
- Implement proper typing for event handlers.
- Use type-safe context with `createContext`.
- Use type assertions sparingly and only when necessary.
- Follow TypeScript best practices and naming conventions.
- Use Tailwind utility-first classes as the default styling approach.
- Use Tailwind responsive utilities for responsive design.
- Keep global Tailwind CSS styles in `src/styles.css`.
- Use Tailwind `@apply` only for reusable style patterns.
- Use Tailwind `@layer` for custom style layers.
- Support dark mode with Tailwind `dark:` variant when applicable.
- Ensure production build purges unused styles.
- Follow both Solid.js and Tailwind naming conventions.
- Use Tailwind JIT behavior for fast development feedback (automatic in Tailwind v4).
- Use TanStack Router for routing when applicable.
