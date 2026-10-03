#!/usr/bin/env bats
# shellcheck disable=SC2034  # B_DISTRO is consumed by the sourced b_logdir.

load helper

bt_setup

# Log paths are grouped per target distribution so a multi-distro build
# session (e.g. the nightly trixie/bookworm/android runs on one host) cannot
# overwrite another distribution's per-recipe log.

@test "b_logdir groups logs by target distro" {
   B_DISTRO=trixie
   run b_logdir
   [ "$status" -eq 0 ]
   [ "$output" = "$BT_FIXTURE/log/trixie" ]
}

@test "b_logfile places the per-recipe log inside the distro dir" {
   B_DISTRO=bookworm
   run b_logfile foo amd64
   [ "$status" -eq 0 ]
   [ "$output" = "$BT_FIXTURE/log/bookworm/foo-amd64.log" ]
}

@test "b_logdir falls back to unknown when no distro was resolved" {
   unset B_DISTRO
   run b_logdir
   [ "$status" -eq 0 ]
   [ "$output" = "$BT_FIXTURE/log/unknown" ]
}
