# Test suite

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

Notes for writing tests:

- bats runs every test with `set -e`. Functions with quirky return codes
  (e.g. `recipe_item_get` returns 1 when the item *is* found) need
  `func || rc=$?` instead of a bare call.
- `run` executes its command in a subshell: global side effects
  (`work_recipes`, `B_ARCH`, ...) do not propagate. Call the function
  directly when you need to inspect globals it sets.
- `parse_options` does not reset `OPTIND`; set `OPTIND=1` before each call.