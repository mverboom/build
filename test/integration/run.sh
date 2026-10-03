#!/usr/bin/env bash
#
# Integration tests for the build script: run real builds in Docker against
# small local fixtures and assert on the outcomes (packages, files, exit
# codes). No internet access needed: sources come from a local git fixture.
#
# Requires: docker (on the host), git, jq, dpkg. Run from anywhere:
#
#     test/integration/run.sh
#
# The harness copies nothing: it runs ./build and ./cacheclean from the
# repository checkout this file lives in, each test against its own throwaway
# sandbox (own HOME/.buildrc, recipes, cache, package dirs, lock file and
# DOCKER_IMAGE_PREFIX=inttest- so production Docker images are never touched).

set -u

BT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD="$BT_ROOT/build"
CACHECLEAN="$BT_ROOT/cacheclean"

PASS=0
FAIL=0
FAILED_TESTS=()

# --- sandbox ---

# Create a throwaway build environment and point SB at it. Every test calls
# this first; all state (dirs, recipes, .buildrc, stubs) lives under SB.
new_sandbox() {
   SB=$(mktemp -d /tmp/build-inttest.XXXXXX)
   # The test runs in a subshell (for errexit isolation); the runner reads the
   # sandbox path from here for cleanup/inspection.
   printf '%s\n' "$SB" > /tmp/build-inttest.last
   mkdir -p "$SB/home" "$SB/dest" "$SB/cache" "$SB/temp" "$SB/log" \
      "$SB/recipes" "$SB/packages" "$SB/repo"

   # .buildrc: everything isolated under SB. LOCK override keeps tests from
   # contending with production builds on the same host; DOCKER_IMAGE_PREFIX
   # keeps the test image build separate from the production one.
   cat > "$SB/home/.buildrc" <<EOF
DESTDIR="$SB/dest"
DESTSPLIT=y
CACHEDIR="$SB/cache"
TMPDIR="$SB/temp"
LOGDIR="$SB/log"
RECIPEDIR="$SB/recipes"
PKGLIST="$SB/recipes/pkglist"
PKGDIR="$SB/packages"
TODEBREPO="$SB/torepo-stub"
LOCK="$SB/build.lck"
BUILDMODE=docker
DOCKER_DIR="$BT_ROOT/docker"
DOCKER_IMAGE_PREFIX=inttest-
DOCKERAUTOPRUNE=off
EOF

   # Stand-in for the real torepo command: records what would be pushed.
   cat > "$SB/torepo-stub" <<EOF
#!/bin/bash
mkdir -p "$SB/repo"
cp -a -- "\$@" "$SB/repo/"
EOF
   chmod +x "$SB/torepo-stub"

   # Local git fixture with tags; visible inside the container because
   # RECIPEDIR is bind-mounted at an identical path.
   git init -q "$SB/recipes/.fixtures/repo"
   git -C "$SB/recipes/.fixtures/repo" -c user.name=test -c user.email=test@example.com \
      commit --allow-empty -q -m init
   git -C "$SB/recipes/.fixtures/repo" tag v1.0.0
   git -C "$SB/recipes/.fixtures/repo" tag v1.2.0
   git -C "$SB/recipes/.fixtures/repo" tag v1.3.0-beta

   # hello.sh lands in the package via B_FILES + B_LINKFILES (t_happy).
   mkdir -p "$SB/recipes/gitver.files/B_BUILD" "$SB/recipes/gitver.files/B_DEBIAN/etc/gitver"
   printf '#!/bin/sh\necho hello-from-gitver\n' > "$SB/recipes/gitver.files/B_BUILD/hello.sh"
   chmod +x "$SB/recipes/gitver.files/B_BUILD/hello.sh"
   printf 'test-config=1\n' > "$SB/recipes/gitver.files/B_DEBIAN/etc/gitver/gitver.conf"

   cat > "$SB/recipes/gitver.recipe" <<EOF
[VERSION]
B_GITVER -r 's/^v//' $SB/recipes/.fixtures/repo

[INFO]
arch=all

[BUILD]
mkdir -p \$B_INSTALLDIR/opt/gitver/bin
cp \$B_FILES/hello.sh \$B_INSTALLDIR/opt/gitver/bin/gitver
B_LINKFILES /opt/gitver/bin /usr/bin

[PKG]
type=deb
torepo=y

[DEB]
Package: gitver
Version: B_VERSION
Section: test
Priority: optional
Architecture: B_ARCH
Maintainer: test@example.org
Description: gitver fixture package
EOF
}

# Run build (or cacheclean) with the sandbox HOME; capture combined output in
# BUILD_OUT and the exit code as return value.
run_build() {
   BUILD_OUT=$(cd "$BT_ROOT" && HOME="$SB/home" "$BUILD" "$@" 2>&1)
   return $?
}

run_cacheclean() {
   BUILD_OUT=$(cd "$BT_ROOT" && HOME="$SB/home" "$CACHECLEAN" 2>&1)
   return $?
}

# --- assertions ---

fail() {
   printf '    FAIL: %s\n' "$1" >&2
   printf '%s\n' "---- build output ----" >&2
   printf '%s\n' "$BUILD_OUT" >&2
   printf '----------------------\n' >&2
   FAIL=$(( FAIL + 1 ))
}

assert_contains() {
   local hay="$1" needle="$2"
   [[ "$hay" == *"$needle"* ]] || fail "output does not contain '$needle'"
}

assert_not_contains() {
   local hay="$1" needle="$2"
   [[ "$hay" != *"$needle"* ]] || fail "output unexpectedly contains '$needle'"
}

assert_file() {
   [[ -f "$1" ]] || fail "missing file: $1"
}

assert_glob() {
   compgen -G "$1" > /dev/null || fail "no file matches: $1"
}

assert_no_glob() {
   if compgen -G "$1" > /dev/null; then
      fail "unexpected match: $1"
      return 1
   fi
}

# --- tests ---

# Full happy path: version detection from local git, build in container,
# packaging, torepo, provenance, conffiles, B_LINKFILES.
t_happy() {
   new_sandbox
   if run_build -bp -d trixie gitver; then :; else fail "build -bp exited nonzero"; return 1; fi

   local deb="$SB/packages/gitver_120-1+deb13_all.deb"
   assert_file "$deb"

   local info
   info=$(dpkg -I "$deb")
   assert_contains "$info" "Package: gitver"
   assert_contains "$info" "Version: 120-1+deb13"
   assert_contains "$info" "Architecture: all"

   local contents
   contents=$(dpkg -c "$deb")
   assert_contains "$contents" "usr/bin/gitver"
   assert_contains "$contents" "opt/gitver/bin/gitver"
   assert_contains "$contents" "etc/gitver/gitver.conf"

   # Conffiles: shipped B_DEBIAN/etc file must be marked as conffile.
   assert_contains "$(dpkg-deb --info "$deb" conffiles)" "/etc/gitver/gitver.conf"

   # torepo stub received the package.
   assert_file "$SB/repo/gitver_120-1+deb13_all.deb"

   # Provenance sidecar.
   assert_file "$SB/packages/gitver_120-1+deb13_all.deb.provenance.json"

   # Package list entry with build number.
   assert_contains "$(cat "$SB/recipes/pkglist")" "gitver_1.2.0_all"

   # Logs are grouped per target distro; the host truncate path and the
   # container entrypoint must agree, and no distro-less log is left behind.
   assert_file "$SB/log/trixie/gitver-all.log"
   assert_no_glob "$SB/log/gitver-all.log"
}

# Forced version via recipe@version skips the version check section.
t_forcedver() {
   new_sandbox
   cat > "$SB/recipes/forcedver.recipe" <<'EOF'
[VERSION]
echo 9.9.9

[BUILD]
mkdir -p $B_INSTALLDIR/opt/forcedver
printf forced > $B_INSTALLDIR/opt/forcedver/marker

[PKG]
type=deb

[DEB]
Package: forcedver
Version: B_VERSION
Architecture: B_ARCH
Maintainer: test@example.org
Description: forcedver fixture
EOF
   if run_build -bp -d trixie forcedver@2.0.0; then :; else fail "build -bp exited nonzero"; return 1; fi

   assert_glob "$SB/packages/forcedver_200-1+deb13_amd64.deb"
   assert_contains "$(dpkg -I "$SB/packages/forcedver_200-1+deb13_amd64.deb")" "Version: 200-1+deb13"
   # Build output must be under the forced version, not the recipe's 9.9.9.
   assert_file "$SB/dest/debian-trixie/amd64/forcedver/2.0.0/opt/forcedver/marker"
   assert_no_glob "$SB/dest/debian-trixie/amd64/forcedver/9.9.9/*"
}

# Distro-specific BUILD section is preferred over the bare one.
t_distro_sections() {
   new_sandbox
   cat > "$SB/recipes/variants.recipe" <<'EOF'
[VERSION]
echo 1.0

[BUILD DEBIAN TRIXIE]
mkdir -p $B_INSTALLDIR/opt/variants
printf trixie-specific > $B_INSTALLDIR/opt/variants/marker

[BUILD]
mkdir -p $B_INSTALLDIR/opt/variants
printf generic > $B_INSTALLDIR/opt/variants/marker
EOF
   cat > "$SB/recipes/novariant.recipe" <<'EOF'
[VERSION]
echo 1.0

[BUILD]
mkdir -p $B_INSTALLDIR/opt/novariant
printf generic > $B_INSTALLDIR/opt/novariant/marker
EOF
   if run_build -b -d trixie variants; then :; else fail "variants build exited nonzero"; return 1; fi
   if run_build -b -d trixie novariant; then :; else fail "novariant build exited nonzero"; return 1; fi

   assert_contains "$(cat "$SB/dest/debian-trixie/amd64/variants/1.0/opt/variants/marker")" "trixie-specific"
   assert_contains "$(cat "$SB/dest/debian-trixie/amd64/novariant/1.0/opt/novariant/marker")" "generic"
}

# Instance: B_INSTANCE keyword substitution in the [DEB] section and the
# instance-suffixed output paths.
t_instance() {
   new_sandbox
   cat > "$SB/recipes/instance.recipe" <<'EOF'
[VERSION]
echo 1.0

[BUILD]
mkdir -p $B_INSTALLDIR/opt/instance
printf inst > $B_INSTALLDIR/opt/instance/marker

[PKG]
type=deb

[DEB]
Package: instpkg-B_INSTANCE
Version: B_VERSION
Architecture: B_ARCH
Maintainer: test@example.org
Description: instance fixture
EOF
   if run_build -bp -d trixie instance:inst1; then :; else fail "build -bp exited nonzero"; return 1; fi

   assert_glob "$SB/packages/instpkg-inst1_10-1+deb13_amd64.deb"
   assert_file "$SB/dest/debian-trixie/amd64/instpkg/1.0-inst1/opt/instance/marker"
   assert_contains "$(cat "$SB/recipes/pkglist")" "instpkg_1.0-inst1_amd64"
}

# Already-built detection and forced rebuild (-f), including build numbers.
t_force_rebuild() {
   new_sandbox
   if run_build -bp -d trixie gitver; then :; else fail "run1 exited nonzero"; return 1; fi
   assert_glob "$SB/packages/gitver_120-1+deb13_all.deb"

   # Second run: build skipped, package redone with the next build number.
   if run_build -bp -d trixie gitver; then :; else fail "run2 exited nonzero"; return 1; fi
   assert_contains "$BUILD_OUT" "(already built)"
   assert_file "$SB/packages/gitver_120-2+deb13_all.deb"

   # -f forces an actual rebuild.
   if run_build -bfp -d trixie gitver; then :; else fail "run3 (-f) exited nonzero"; return 1; fi
   assert_not_contains "$BUILD_OUT" "(already built)"
   assert_file "$SB/packages/gitver_120-3+deb13_all.deb"
   [[ "$(grep -c "^gitver_1.2.0_all" "$SB/recipes/pkglist")" -eq 3 ]] \
      || fail "expected 3 pkglist lines for gitver_1.2.0_all"
}

# Dryrun reports but does not touch anything.
t_dryrun() {
   new_sandbox
   if run_build -bpl -d trixie gitver; then :; else fail "dryrun exited nonzero"; return 1; fi
   assert_contains "$BUILD_OUT" "Would build gitver 1.2.0"
   [[ -z "$(find "$SB/dest" -mindepth 1 -print -quit 2>/dev/null)" ]] || fail "dryrun wrote to DESTDIR"
   assert_no_glob "$SB/packages/*"
   [[ ! -e "$SB/recipes/pkglist" ]] || fail "dryrun wrote pkglist"
}

# A failing BUILD section fails the whole run.
t_failbuild() {
   new_sandbox
   cat > "$SB/recipes/failbuild.recipe" <<'EOF'
[VERSION]
echo 1.0

[BUILD]
exit 3
EOF
   if run_build -b -d trixie failbuild; then
      fail "failing build unexpectedly exited 0"
   fi
}

# Concurrent runs: the second one refuses on the lock instead of waiting.
t_lock() {
   new_sandbox
   cat > "$SB/recipes/slow.recipe" <<'EOF'
[VERSION]
echo 1.0

[BUILD]
sleep 6
EOF
   ( cd "$BT_ROOT" && HOME="$SB/home" "$BUILD" -b -d trixie slow > "$SB/lock-bg.log" 2>&1 ) &
   local bgpid=$!

   # Wait until the background run actually holds the lock (image ensure and
   # recipe registration run before lock_get). flock probes with a harmless
   # true command; when the probe fails the lock is held and we continue.
   local n=0
   until ! flock -n "$SB/build.lck" true 2> /dev/null; do
      (( n += 1 ))
      if (( n > 60 )); then break; fi
      sleep 1
   done

   run_build -b -d trixie gitver || true
   assert_contains "$BUILD_OUT" "Unable to get lock"
   wait "$bgpid"
   assert_contains "$(cat "$SB/lock-bg.log")" "slow 1.0 (build succeeded)"
}

# -a fleet selection: arch filtering, instance requirement, excludefromall.
t_select_all() {
   new_sandbox
   cat > "$SB/recipes/simple.recipe" <<'EOF'
[VERSION]
echo 1.0

[INFO]
arch=all

[BUILD]
echo ok
EOF
   cat > "$SB/recipes/armonly.recipe" <<'EOF'
[VERSION]
echo 1.0

[INFO]
arch=arm64

[BUILD]
echo ok
EOF
   cat > "$SB/recipes/instance.recipe" <<'EOF'
[VERSION]
echo 1.0

[INFO]
instance=inst1

[BUILD]
echo ok
EOF
   if run_build -bal -d trixie; then :; else fail "-bal exited nonzero"; return 1; fi
   assert_contains "$BUILD_OUT" "Would build simple 1.0"
   assert_contains "$BUILD_OUT" "Would build gitver 1.2.0"
   assert_contains "$BUILD_OUT" "not for this architecture"
   assert_contains "$BUILD_OUT" "requires an instance"
   assert_not_contains "$BUILD_OUT" "Would build armonly"
   assert_not_contains "$BUILD_OUT" "Would build instance"
}

# cacheclean: prune versioned downloads per stem, keep single-file caches.
t_cacheclean() {
   new_sandbox
   mkdir -p "$SB/cache/foo" "$SB/cache/bar"
   for v in 1.0 1.1 1.2 1.3; do printf x > "$SB/cache/foo/foo-$v"; done
   printf x > "$SB/cache/bar/bar.git"

   if run_cacheclean; then :; else fail "cacheclean exited nonzero"; return 1; fi

   assert_file "$SB/cache/foo/foo-1.1"
   assert_file "$SB/cache/foo/foo-1.2"
   assert_file "$SB/cache/foo/foo-1.3"
   assert_file "$SB/cache/bar/bar.git"
   [[ ! -e "$SB/cache/foo/foo-1.0" ]] || fail "oldest cached version foo-1.0 not pruned"
}

TESTS=(
   t_happy
   t_forcedver
   t_distro_sections
   t_instance
   t_force_rebuild
   t_dryrun
   t_failbuild
   t_lock
   t_select_all
   t_cacheclean
)

for t in "${TESTS[@]}"; do
   printf '%s: ' "$t"
   if output=$( { set -e; "$t"; } 2>&1 ); then
      printf 'ok\n'
      PASS=$(( PASS + 1 ))
      rm -rf "$(cat /tmp/build-inttest.last)"
   else
      printf 'FAILED\n'
      printf '%s\n' "$output" | sed 's/^/    /' >&2
      FAIL=$(( FAIL + 1 ))
      FAILED_TESTS+=("$t")
      SB=$(cat /tmp/build-inttest.last)
      printf '    (sandbox kept for inspection: %s)\n' "$SB" >&2
   fi
done

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 )) || { printf 'failed: %s\n' "${FAILED_TESTS[*]}"; exit 1; }