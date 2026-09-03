#!/usr/bin/env bats

load helper

bt_setup

@test "recipe_section_get prints section body and skips comments" {
   run recipe_section_get simple PKG
   [ "$status" -eq 0 ]
   [[ "$output" == *"type=deb"* ]]
   [[ "$output" != *"#"* ]]
}

@test "recipe_section_get fails for absent section" {
   # awk reports rc 2 (absent); the function maps that to 1 with a message.
   run recipe_section_get simple NOSUCH
   [ "$status" -eq 1 ]
   [[ "$output" == *"No section NOSUCH"* ]]
}

@test "recipe_section_get fails for absent recipe" {
   run recipe_section_get nonexistent VERSION
   [ "$status" -eq 1 ]
}

@test "recipe_section_get optional succeeds silently on absent section" {
   run recipe_section_get simple NOSUCH opt
   [ "$status" -eq 0 ]
   [ -z "$output" ]
}

@test "recipe_section_lookup prefers distro+release specific section" {
   distr=DEBIAN rel=TRIXIE
   run recipe_section_lookup variants BUILD
   [ "$status" -eq 0 ]
   [[ "$output" == *"trixie specific"* ]]
}

@test "recipe_section_lookup falls back to distro generic section" {
   distr=DEBIAN rel=BOOKWORM
   run recipe_section_lookup variants BUILD
   [ "$status" -eq 0 ]
   [[ "$output" == *"debian generic"* ]]
}

@test "recipe_section_lookup falls back to bare section" {
   distr=UBUNTU rel=NOBLE
   run recipe_section_lookup variants BUILD
   [ "$status" -eq 0 ]
   [[ "$output" == *"generic"* ]]
}

@test "recipe_item_get returns item value" {
   run recipe_item_get simple INFO arch
   [[ "$output" == "all" ]]
}

@test "recipe_item_get returns default for missing item" {
   # variants.recipe has no [INFO] section at all.
   run recipe_item_get variants INFO arch noarch
   [[ "$output" == "noarch" ]]
}

@test "recipe_select_arch accepts all" {
   B_SARCH=amd64
   local rc=0
   recipe_select_arch simple || rc=$?
   [ "$rc" -eq 0 ]
   [[ "$B_ARCH" == "all" ]]
}

@test "recipe_select_arch matches a listed arch" {
   B_SARCH=amd64
   local rc=0
   recipe_select_arch multiarch || rc=$?
   [ "$rc" -eq 0 ]
   [[ "$B_ARCH" == "amd64" ]]
}

@test "recipe_select_arch handles 3+ arch lists (all commas)" {
   B_SARCH=arm64
   cat > "$RECIPEDIR/threearch.recipe" <<'EOF'
[VERSION]
echo 1.0

[INFO]
arch=amd64,arm64,riscv64

[BUILD]
echo ok
EOF
   local rc=0
   recipe_select_arch threearch || rc=$?
   [ "$rc" -eq 0 ]
   [[ "$B_ARCH" == "arm64" ]]
}

@test "recipe_select_arch rejects non-matching arch" {
   B_SARCH=amd64
   run recipe_select_arch armonly
   [ "$status" -eq 1 ]
}

@test "recipe_select_arch defaults to system arch when unset" {
   B_SARCH=amd64
   cat > "$RECIPEDIR/noarchspec.recipe" <<'EOF'
[VERSION]
echo 1.0

[BUILD]
echo ok
EOF
   local rc=0
   recipe_select_arch noarchspec || rc=$?
   [ "$rc" -eq 0 ]
   [[ "$B_ARCH" == "amd64" ]]
}