#!/usr/bin/env bats

load helper

bt_setup

# parse_options() is called directly (not via `run`) because it modifies the
# global work_* arrays, which would not propagate out of run's subshell.
# OPTIND must be reset between calls: parse_options only runs once per
# process in production, so it does not reset it itself.

@test "parse_options sets build mode and registers recipe" {
   OPTIND=1
   parse_options -b -d trixie simple
   [ "$?" -eq 0 ]
   [ "$DO_BUILD" -eq 1 ]
   [ "${#work_recipes[@]}" -eq 1 ]
   [[ "${work_recipes[0]}" == "simple" ]]
}

@test "parse_options maps bare codename to debian family" {
   OPTIND=1
   parse_options -b -d trixie simple
   [[ "$distr" == "DEBIAN" ]]
   [[ "$rel" == "TRIXIE" ]]
}

@test "parse_options keeps family-codename form" {
   OPTIND=1
   parse_options -b -d ubuntu-noble simple
   [[ "$distr" == "UBUNTU" ]]
   [[ "$rel" == "NOBLE" ]]
}

@test "parse_options parses recipe@version" {
   OPTIND=1
   parse_options -b -d trixie simple@2.0.4
   [[ "${work_forcever[simple]}" == "2.0.4" ]]
}

@test "parse_options parses recipe:instance" {
   OPTIND=1
   parse_options -b -d trixie simple:myinst
   [[ "${work_instance[simple]}" == "myinst" ]]
}

@test "parse_options parses recipe:instance@version and recipe@version:instance" {
   OPTIND=1
   parse_options -b -d trixie simple:inst1@2.0
   [[ "${work_instance[simple]}" == "inst1" ]]
   [[ "${work_forcever[simple]}" == "2.0" ]]

   OPTIND=1
   parse_options -b -d trixie simple@2.0:inst1
   [[ "${work_instance[simple]}" == "inst1" ]]
   [[ "${work_forcever[simple]}" == "2.0" ]]
}

@test "parse_options -i sets global instance" {
   OPTIND=1
   parse_options -b -d trixie -i glob simple
   [[ "$B_INSTANCE" == "glob" ]]
}

@test "parse_options registers multiple recipes" {
   OPTIND=1
   parse_options -b -d trixie simple multiarch
   [ "${#work_recipes[@]}" -eq 2 ]
}

@test "parse_options skips recipe requiring instance without one" {
   OPTIND=1
   run parse_options -b -d trixie instance
   [ "$status" -eq 1 ]   # nothing registered -> "No recipe(s) specified."
}

@test "parse_options registers instance recipe with instance given" {
   OPTIND=1
   parse_options -b -d trixie instance:inst1
   [ "${#work_recipes[@]}" -eq 1 ]
   [[ "${work_instance[instance]}" == "inst1" ]]
}

@test "parse_options rejects unknown recipe" {
   OPTIND=1
   run parse_options -b -d trixie nonexistent
   [ "$status" -eq 1 ]
   [[ "$output" == *"recipe nonexistent does not exist"* ]]
}

@test "parse_options fails without action flags" {
   OPTIND=1
   run parse_options -d trixie simple
   [ "$status" -eq 1 ]
}

@test "parse_options fails on unknown option" {
   OPTIND=1
   run parse_options -z -b -d trixie simple
   [ "$status" -eq 1 ]
   [[ "$output" == *"Unknown option: -z"* ]]
}

@test "parse_options -a registers arch-matching recipes without instance ones" {
   # simple: arch=all, registered. multiarch: amd64 in list, registered.
   # armonly: arm64 only, skipped on non-arm64 hosts. instance: skipped
   # (requires instance, none given). gitver/variants: no arch restriction.
   OPTIND=1
   parse_options -b -a -d trixie
   [ "$?" -eq 0 ]
   [[ " ${work_recipes[*]} " == *" simple "* ]]
   [[ " ${work_recipes[*]} " == *" multiarch "* ]]
   [[ " ${work_recipes[*]} " != *" armonly "* ]]
   [[ " ${work_recipes[*]} " != *" instance "* ]]
}