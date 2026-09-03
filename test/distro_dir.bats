#!/usr/bin/env bats

load helper

bt_setup

@test "distro_dir maps bare debian codename to debian family" {
   BUILDDISTRO=trixie
   distro_dir
   [[ "$B_DISTRODIR" == "debian-trixie" ]]
   [[ "$B_DISTRO" == "trixie" ]]
}

@test "distro_dir keeps family-codename form" {
   BUILDDISTRO=debian-bookworm
   distro_dir
   [[ "$B_DISTRODIR" == "debian-bookworm" ]]
   [[ "$B_DISTRO" == "bookworm" ]]
}

@test "distro_dir keeps non-debian family as-is" {
   BUILDDISTRO=ubuntu-noble
   distro_dir
   [[ "$B_DISTRODIR" == "ubuntu-noble" ]]
   [[ "$B_DISTRO" == "noble" ]]
}

@test "distro_dir maps unknown codename to itself as family" {
   BUILDDISTRO=forky
   distro_dir
   [[ "$B_DISTRODIR" == "forky-forky" ]]
   [[ "$B_DISTRO" == "forky" ]]
}

@test "distro_dir uses lsb_release values in native mode" {
   BUILDDISTRO=""
   distr=DEBIAN rel=TRIXIE
   distro_dir
   [[ "$B_DISTRODIR" == "debian-trixie" ]]
}