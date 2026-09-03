#!/usr/bin/env bats

load helper

bt_setup

setup() {
   BT_ENVFILE="$BT_FIXTURE/env-$BATS_TEST_NUMBER.sh"

   # B_GET and friends are not defined at source time: build() defines them
   # dynamically before docker_prepare_env runs. Provide stubs so the
   # declare -f export block behaves as it does in a real build.
   B_GET() { :; }
   B_GITCHECKOUT() { :; }
   B_LINKFILES() { :; }
   B_LINKFILE() { :; }
   B_VULNSCAN() { :; }
   B_SRCGUARD() { :; }

   # B_INSTANCE and PKGPOSTFIX are free-form user-supplied values in the
   # (readonly) BUILD_ENV_VARS list. Give them shell-hostile content: if the
   # generated script is not properly quoted the source below breaks or
   # executes part of the value.
   UNSAFE_VALUE='hello world; "quoted" $HOME `cmd` $(x) & |'
   B_INSTANCE="$UNSAFE_VALUE"
   PKGPOSTFIX="$UNSAFE_VALUE"
   B_NAME=envtest
   B_FILES="$BT_FIXTURE/files"
   B_FORCE=1
   QUIET=0
   VERBOSE=0
}

# docker_prepare_env writes a bash script; these tests source it in a fresh
# bash and compare the resulting variable values with the originals.

@test "docker_prepare_env writes shell-safe variable values (%q)" {
   docker_prepare_env "$BT_ENVFILE"
   [ "$?" -eq 0 ]

   run bash -c "source '$BT_ENVFILE' > /dev/null && printf '%s' \"\$B_INSTANCE\""
   [ "$status" -eq 0 ]
   [[ "$output" == "$UNSAFE_VALUE" ]]
}

@test "docker_prepare_env quotes literal-passed PKGPOSTFIX too" {
   docker_prepare_env "$BT_ENVFILE"

   run bash -c "source '$BT_ENVFILE' > /dev/null && printf '%s' \"\$PKGPOSTFIX\""
   [ "$status" -eq 0 ]
   [[ "$output" == "$UNSAFE_VALUE" ]]
}

@test "docker_prepare_env passes fixed-value entries through" {
   docker_prepare_env "$BT_ENVFILE"

   run bash -c "source '$BT_ENVFILE' > /dev/null && printf '%s' \"\$BUILDMODE\""
   [ "$status" -eq 0 ]
   [[ "$output" == "docker" ]]
}

@test "docker_prepare_env exports build variables" {
   docker_prepare_env "$BT_ENVFILE"

   run bash -c "source '$BT_ENVFILE' > /dev/null && printf '%s' \"\$B_FILES|\$B_FORCE|\$QUIET\""
   [ "$status" -eq 0 ]
   [[ "$output" == "$BT_FIXTURE/files|1|0" ]]
}

@test "docker_prepare_env sets tool cache locations" {
   docker_prepare_env "$BT_ENVFILE"

   run bash -c "source '$BT_ENVFILE' > /dev/null && printf '%s' \"\$npm_config_cache|\$GOPATH|\$PYTHONDONTWRITEBYTECODE\""
   [ "$status" -eq 0 ]
   [[ "$output" == "/tmp/.npm|/tmp/.go|1" ]]
}

@test "docker_prepare_env includes function definitions" {
   docker_prepare_env "$BT_ENVFILE"
   grep -q "B_GET ()" "$BT_ENVFILE"
   grep -q "package_deb ()" "$BT_ENVFILE"
   grep -q "recipe_section_get ()" "$BT_ENVFILE"
}