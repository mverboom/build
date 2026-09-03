#!/usr/bin/env bats

load helper

bt_setup

@test "version_get returns newest tag with default prefilter (v stripped)" {
   run version_get gitver
   [ "$status" -eq 0 ]
   [[ "$output" == "1.2.0" ]]
}

@test "version_get excludes pre-release tags by default" {
   git -C "$BT_REPO" tag v1.3.0-beta
   run version_get gitver
   [ "$status" -eq 0 ]
   [[ "$output" == "1.2.0" ]]
}

@test "version_get fails when version command produces no output" {
   cat > "$RECIPEDIR/emptyver.recipe" <<'EOF'
[VERSION]
true

[BUILD]
echo ok
EOF
   run version_get emptyver
   [ "$status" -eq 1 ]
}

@test "version_get fails on recipe without VERSION section" {
   cat > "$RECIPEDIR/nover.recipe" <<'EOF'
[BUILD]
echo ok
EOF
   run version_get nover
   [ "$status" -eq 1 ]
}