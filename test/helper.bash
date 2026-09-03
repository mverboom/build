# Shared setup for the build test suite. Run with: bats test
#
# Each test file calls bt_setup in setup_file, which creates a fixture
# environment (fixture HOME with a minimal .buildrc, fixture recipe
# directory, local git repository for version-detection tests) and sources
# the build script with BUILD_TEST_SOURCED set. main() then does not run and
# individual functions can be exercised directly.

BUILD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_SCRIPT="$BUILD_ROOT/build"

bt_setup() {
   BT_FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/build-test.XXXXXX")"
   export BT_FIXTURE

   # Fixture HOME with a minimal .buildrc. build sources ~/.buildrc on the
   # host and refuses to run without one; the fixture keeps the test suite
   # independent of any real build configuration.
   BT_HOME="$BT_FIXTURE/home"
   mkdir -p "$BT_HOME"
   cat > "$BT_HOME/.buildrc" <<EOF
DESTDIR="$BT_FIXTURE/build"
CACHEDIR="$BT_FIXTURE/cache"
TMPDIR="$BT_FIXTURE/temp"
RECIPEDIR="$BT_FIXTURE/recipes"
PKGDIR="$BT_FIXTURE/packages"
LOGDIR="$BT_FIXTURE/log"
EOF
   export HOME="$BT_HOME"

   # Fixture recipes.
   mkdir -p "$BT_FIXTURE/recipes"
   cat > "$BT_FIXTURE/recipes/simple.recipe" <<'EOF'
[VERSION]
echo 1.2.3

[INFO]
arch=all

[BUILD]
echo building simple

[PKG]
type=deb

[DEB]
Package: simple
Version: B_VERSION
Description: simple fixture
EOF

   cat > "$BT_FIXTURE/recipes/multiarch.recipe" <<'EOF'
[VERSION]
echo 1.0

[INFO]
arch=amd64,arm64

[BUILD]
echo building multiarch
EOF

   cat > "$BT_FIXTURE/recipes/armonly.recipe" <<'EOF'
[VERSION]
echo 1.0

[INFO]
arch=arm64

[BUILD]
echo building armonly
EOF

   cat > "$BT_FIXTURE/recipes/instance.recipe" <<'EOF'
[VERSION]
echo 1.0

[INFO]
instance=inst1

[BUILD]
echo building instance
EOF

   # Recipe with distro/instance specific section variants.
   cat > "$BT_FIXTURE/recipes/variants.recipe" <<'EOF'
[VERSION]
echo 1.0

[BUILD DEBIAN TRIXIE]
echo trixie specific

[BUILD DEBIAN]
echo debian generic

[BUILD]
echo generic

[BUILD DEBIAN TRIXIE INST prod]
echo trixie prod
EOF

   # Local git repository with tags for B_GITVER tests (no network needed).
   BT_REPO="$BT_FIXTURE/repo"
   git init -q "$BT_REPO"
   git -C "$BT_REPO" -c user.name=test -c user.email=test@example.com commit --allow-empty -q -m init
   git -C "$BT_REPO" tag v1.0.0
   git -C "$BT_REPO" tag v1.1.0-beta
   git -C "$BT_REPO" tag v1.2.0

   cat > "$BT_FIXTURE/recipes/gitver.recipe" <<EOF
[VERSION]
B_GITVER -r 's/^v//' $BT_REPO

[BUILD]
echo building gitver
EOF

   # Source the build script without running main().
   # shellcheck disable=SC1091
   BUILD_TEST_SOURCED=1 source "$BUILD_SCRIPT"

   # Common globals the functions under test rely on (SC2034: consumed by
   # the sourced build functions, not directly by the test files).
   # shellcheck disable=SC2034
   B_SARCH=$(arch_get)
   # shellcheck disable=SC2034
   declare -a work_recipes=() work_version=() work_build=() work_package=() \
      work_packaged=() work_buildtime=()
   # shellcheck disable=SC2034
   declare -A work_arch=() work_forcever=() work_instance=()
}