#!/usr/bin/env bats

load helper

bt_setup

@test "_cache_stem strips version suffix" {
   run _cache_stem freecad-1.0.2
   [[ "$output" == "freecad" ]]
}

@test "_cache_stem strips multi-digit version suffix" {
   run _cache_stem some-tool-2.10.3
   [[ "$output" == "some-tool" ]]
}

@test "_cache_stem keeps name without version" {
   run _cache_stem git
   [[ "$output" == "git" ]]
}

@test "_cache_stem keeps single-file cache tarballs" {
   run _cache_stem myproject.git
   [[ "$output" == "myproject.git" ]]
}

@test "_cache_stem strips only the version part" {
   run _cache_stem openssl-3.0
   [[ "$output" == "openssl" ]]
}