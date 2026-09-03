# Test suite

Two layers of tests live here. Run both with: `bats test && test/integration/run.sh`

## Unit tests (bats)

Unit tests for the build script, run with [bats-core](https://github.com/bats-core/bats-core)
(Debian: `apt install bats`):

```
bats test
```

The tests source `build` with `BUILD_TEST_SOURCED=1` set (see the guard at
the bottom of the build script): `main()` does not run and individual
functions are exercised directly. Each test file gets a throwaway fixture
environment (HOME, recipes, a local git repository) from `helper.bash`, so no
network, Docker or real build configuration is needed.

## Integration tests

`test/integration/run.sh` runs real end-to-end builds: each test gets a
throwaway sandbox (own HOME/.buildrc, recipe dir, package dirs, lock file,
DOCKER_IMAGE_PREFIX=inttest-) and drives ./build through actual Docker
container runs against local git fixtures — no internet access needed.

Covers: version detection, forced versions, distro/instance section
selection, B_INSTANCE/B_LINKFILES/B_FILES, conffiles merging, packaging,
provenance, torepo, already-built/-f rebuilds and build numbers, dryrun
side-effect freedom, failing builds, lock contention, `-a` fleet selection
and cacheclean pruning.

Needs a host with Docker (e.g. the build server): `ssh build` a checkout of
the repo and run the script there. Runtime is a few minutes; the inttest Docker image is built on first use and reused afterwards.

Notes for writing tests:

- bats runs every test with `set -e`. Functions with quirky return codes
  (e.g. `recipe_item_get` returns 1 when the item *is* found) need
  `func || rc=$?` instead of a bare call.
- `run` executes its command in a subshell: global side effects
  (`work_recipes`, `B_ARCH`, ...) do not propagate. Call the function
  directly when you need to inspect globals it sets.
- `parse_options` does not reset `OPTIND`; set `OPTIND=1` before each call.