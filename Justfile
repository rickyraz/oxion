# Oxion Monorepo - Build & Development Commands
# Run inside `nix develop` for hermetic environment, or directly with local tools.

default:
    @just --list

# Build all Gleam packages and apps
build: _require-build-tools
    bazel build //packages/policy:oxion_policy //packages/interop:oxion_interop //apps/oxcore:oxcore //apps/oxradius:oxradius //apps/oxnoc:oxnoc //apps/oxolt:oxolt //apps/oxbgp:oxbgp //apps/oxacs:oxacs

# Test all Gleam packages and apps
test: _require-build-tools
    bazel test //packages/policy:oxion_policy_test //packages/interop:oxion_interop_test //apps/oxcore:oxcore_test //apps/oxradius:oxradius_test //apps/oxnoc:oxnoc_test //apps/oxolt:oxolt_test //apps/oxbgp:oxbgp_test //apps/oxacs:oxacs_test

# Internal: verify tools required by Gleam dependencies with non-Gleam build steps
_require-build-tools:
    @command -v rebar3 >/dev/null || (echo "error: rebar3 is required to build oxradius dependency hpack_erl. Run 'nix develop' or install rebar3 locally." >&2; exit 127)

# Format check for all Gleam code
lint:
    @just _gleam-each "gleam format --check src test"

# Typecheck all Gleam code
typecheck:
    @just _gleam-each "gleam check"

# Internal: run a gleam command in each package
_gleam-each cmd:
    @for dir in packages/policy packages/interop apps/oxcore apps/oxradius apps/oxnoc apps/oxolt apps/oxbgp apps/oxacs; do if [ -f "$dir/gleam.toml" ]; then echo "[$dir] {{cmd}}"; (cd "$dir" && sh -c "{{cmd}}"); fi; done

# Generate contracts from Gleam interfaces
generate:
    node ./scripts/generate-contracts.mjs
    node --experimental-strip-types ./scripts/generate-zod.ts

# Check generated files are up to date
check-generated: generate
    git diff --exit-code -- generated

# Build frontend
build-frontend:
    cd frontend/platform && pnpm install --frozen-lockfile && pnpm run build

# Test frontend
test-frontend:
    cd frontend/platform && pnpm install --frozen-lockfile && pnpm run test

# Lint frontend
lint-frontend:
    cd frontend/platform && pnpm install --frozen-lockfile && pnpm run check

# Typecheck frontend
typecheck-frontend:
    cd frontend/platform && pnpm install --frozen-lockfile && pnpm run typecheck

# Start frontend dev server
dev:
    cd frontend/platform && pnpm run dev

# Clean Bazel cache
clean:
    bazel clean

# Clean everything including node_modules
clean-all: clean
    rm -rf node_modules
    rm -rf frontend/platform/node_modules
    rm -rf frontend/platform/dist

# Run FreeRADIUS harness test
harness-freeradius:
    node ./scripts/run-oxradius-freeradius-harness.mjs

# Run remote FreeRADIUS test against the configured lab server.
# Add --execute to run commands; default mode is dry-run.
harness-freeradius-remote *ARGS:
    node ./scripts/run-oxradius-remote-freeradius-test.mjs {{ARGS}}

# Run local callback server for remote FreeRADIUS rlm_rest tunnel testing.
rlm-rest-callback-server *ARGS:
    node ./scripts/run-oxradius-rlm-rest-callback-server.mjs {{ARGS}}

# Run local FreeRADIUS -> rlm_rest -> callback integration harness.
rlm-rest-harness *ARGS:
    node ./scripts/run-oxradius-rlm-rest-harness.mjs {{ARGS}}

# Changeset commands
changeset:
    pnpm changeset

version-packages:
    pnpm version:packages

release-check:
    pnpm release:check

release:
    pnpm release

# Build all (Gleam + Frontend)
build-all: build build-frontend

# Test all (Gleam + Frontend)
test-all: test test-frontend

# Lint all (Gleam + Frontend)
lint-all: lint lint-frontend

# Typecheck all (Gleam + Frontend)
typecheck-all: typecheck typecheck-frontend

# Full CI check
ci: lint-all typecheck-all test-all
