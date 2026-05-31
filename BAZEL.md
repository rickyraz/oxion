# Bazel + Nix Build System

## Quick Start

### Option A: With Nix (Recommended — Hermetic)

```bash
# Enter hermetic dev shell (Gleam, Erlang, Node, Bazel all pinned)
nix develop

# Then use just normally
just build
just test
just lint
just typecheck
```

### Option B: Without Nix (Local tools)

```bash
# Requires: gleam, erlang/otp, node, bazelisk, just installed locally
just build
just test
```

## Commands

| Command | Description |
|---|---|
| `just build` | Build all Gleam packages and apps |
| `just test` | Run all tests |
| `just lint` | Format check all Gleam code |
| `just typecheck` | Typecheck all Gleam code |
| `just generate` | Generate contracts from Gleam interfaces |
| `just dev` | Start frontend dev server |
| `just ci` | Full CI check (lint + typecheck + test) |
| `just clean` | Clean Bazel cache |

## Architecture

```
Bazel (orchestration)
  ├── WORKSPACE / MODULE.bazel    → dependency declarations
  ├── BUILD.bazel (per package)   → build targets
  └── tools/rules_gleam/          → custom Gleam rules

Just (developer interface)
  └── Justfile                    → wraps Bazel + Gleam commands

Nix (hermetic environment)
  └── flake.nix                   → pins Gleam, Erlang, Node, Bazel versions
```

## Known Limitations

### 1. Gleam Sandboxing

**Issue:** Gleam CLI requires full filesystem access to resolve `path = "..."` dependencies in `gleam.toml`. Bazel's sandbox restricts filesystem access, breaking Gleam builds.

**Current workaround:** `--spawn_strategy=local` disables sandboxing for all actions.

**Impact:** Builds are not fully hermetic at the action level. The Nix flake provides hermeticity at the environment level (pinned toolchain versions), which is the practical trade-off.

**Future fix:** When `rules_gleam` matures for Bazel, or Gleam adds support for hermetic build inputs, sandboxing can be re-enabled.

### 2. Hardcoded Workspace Path

**Issue:** Test and build rules use `cd /home/rickyraz/objectives/oxion/{package}` which is specific to this machine.

**Current workaround:** Works for local development. For CI, the workflow sets the correct working directory.

**Future fix:** Use `$BUILD_WORKSPACE_DIRECTORY` or Bazel's runfiles mechanism once Gleam sandboxing is resolved.

### 3. Path Dependencies in gleam.toml

**Issue:** Gleam's `path = "..."` dependencies (e.g., `oxcore = { path = "../oxcore" }`) expect a specific directory layout. Bazel's output directory structure differs from the source tree.

**Current workaround:** Tests run from the source tree directly, not from Bazel's output directory.

**Future fix:** Migrate to Gleam's hex package registry for dependencies, or wait for native Bazel rules for Gleam.

## Nix Integration Details

The `flake.nix` provides:

- **Gleam** — pinned to nixpkgs version (currently 1.16.0)
- **Erlang/OTP 28** — matching CI configuration
- **Node.js 22** — for frontend and scripts
- **Bazelisk** — auto-selects Bazel version from `.bazelversion`
- **Just** — command runner

All versions are pinned in `flake.lock` for reproducibility.

### Updating Nix Dependencies

```bash
# Update all inputs
nix flake update

# Update specific input
nix flake update nixpkgs

# Test with updated inputs
nix develop --command just test
```

## CI Integration

GitHub Actions workflows use `erlef/setup-beam` for Gleam/Erlang and `bazel-contrib/setup-bazel` for Bazel. Nix is not used in CI to avoid the overhead of installing Nix in GitHub Actions.

The CI environment mirrors the Nix dev shell versions:
- Gleam 1.15.1 (CI) / 1.16.0 (Nix)
- Erlang/OTP 28
- Node.js 22
- Bazel 8.0.0

## Bazel Best Practices Applied

- `size = "small"` on all test rules (timeout: 60s)
- `--test_output=errors` for concise test output
- `--spawn_strategy=local` for Gleam compatibility
- `MODULE.bazel` for bzlmod dependency management
- `bazel_skylib` for cross-platform utilities
