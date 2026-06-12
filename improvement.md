# Improvement Report — Build Repository

This document lists findings from an analysis of the `build.git` repository, organized by category. Each finding references the relevant file and, where applicable, the bash scripting guideline that is violated.

> **Related documents:**
> - `docker-research.md` — Feasibility research for Docker-based builds
> - `docker-implementation-plan.md` — Phased implementation plan (Phase 0 addresses the items below)

---

## 1. Bash Skill Guideline Violations

### 1.1 Shebang — Use `/usr/bin/env bash` (Structure and Shebang)

All four scripts use `#!/bin/bash` instead of the recommended `/usr/bin/env bash`.

| File | Line |
|------|------|
| `build` | 1 |
| `torepo` | 1 |
| `clean` | 1 |
| `debclean` | 1 |

**Recommendation:** Change all shebangs to `#!/usr/bin/env bash`.

### 1.2 Missing `set -u` (Error Handling and Robustness)

The bash skill requires `set -u` (never `set -e` or `set -o pipefail`). Only `torepo` uses `set -e` (which is explicitly forbidden), and none of the other scripts use `set -u`.

| File | Issue |
|------|-------|
| `build` | No `set -u` |
| `torepo` | Uses `set -e` (forbidden) instead of `set -u` |
| `clean` | No `set -u` |
| `debclean` | No `set -u` |

**Recommendation:** Remove `set -e` from `torepo`, add `set -u` to all four scripts.

### 1.3 Missing Main Function Structure (Structure)

Scripts over 30 lines should wrap all logic in functions, including a `main` function, with a call to `main` at the bottom.

| File | Lines | Issue |
|------|-------|-------|
| `torepo` | ~45 lines | All logic is top-level, no `main` function |
| `clean` | ~70 lines | All logic is top-level, no `main` function |
| `debclean` | ~55 lines | All logic is top-level, no `main` function |
| `build` | ~1000 lines | Has a `main` function ✅ |

**Recommendation:** Refactor `torepo`, `clean`, and `debclean` to use a `main` function pattern.

### 1.4 Script Ordering (Structure)

Scripts should be ordered: shebang → set options → global variables/constants → utility functions → domain functions → main function → call to main.

| File | Issue |
|------|-------|
| `build` | Global variables are scattered inside `main()` instead of being at the top of the script |
| `torepo` | No structured ordering at all — config sourcing, variable checks, and logic are interleaved at the top level |
| `clean` | Global variables and logic are interleaved at the top level |
| `debclean` | Same as `clean` |

**Recommendation:** Move global constant definitions (like default paths) near the top of the script, before function definitions. Keep `main()` focused on orchestration.

### 1.5 Indentation — Use 3 Spaces (Formatting and Style)

All four scripts use 3-space indentation. ✅

No issues found.

### 1.6 Use `printf` Instead of `echo` (Command Usage)

The bash skill requires `printf` for output because `echo` has inconsistent behavior with flags and escape sequences.

| File | Lines with `echo` |
|------|-------------------|
| `build` | Extensive use of `echo` throughout (usage, output function, B_GET, version_get, package_deb, etc.) |
| `torepo` | `echo` on lines 30, 31, 34 |
| `clean` | `echo` used throughout |
| `debclean` | `echo` used throughout |

**Recommendation:** Replace all `echo` calls with `printf '%s\n'` (or `printf` with appropriate format strings).

### 1.7 Use `[[` Instead of `test`/`[` (Conditionals and Control Flow)

The bash skill recommends `[[` over `test` or `[` for tests.

| File | Issue |
|------|-------|
| `build` | Extensive use of `test` throughout the entire script (dozens of occurrences) |
| `torepo` | Uses `test` on lines 28, 29, 30, 33 |
| `clean` | Uses `test` throughout |
| `debclean` | Uses `test` throughout |

**Recommendation:** Replace `test`/`[` with `[[` for all conditionals. This avoids quoting pitfalls and supports pattern matching.

### 1.8 Use `(( ))` for Arithmetic (Conditionals and Control Flow)

The bash skill requires `$(( ))` for arithmetic expansion and `(( ))` for arithmetic conditions, never `expr` or `let`.

| File | Issue |
|------|-------|
| `build` | Uses `$(( BUILDNR + 1 ))` correctly in `package_buildnr_get` ✅, but uses `-eq`, `-ne`, `-lt` etc. with `test` for numeric comparisons throughout |
| `clean` | Uses `-eq`, `-ne` with `test` for numeric comparisons |
| `debclean` | Same pattern |

**Recommendation:** When switching to `[[ ]]`, use `(( ))` for arithmetic comparisons (e.g., `(( DO_CHECK == 1 ))` instead of `test $DO_CHECK -eq 1`).

### 1.9 Double-Quote Variable Expansions (Variables and Scope)

The bash skill requires always double-quoting variable expansions unless word splitting is explicitly desired.

| File | Issues |
|------|--------|
| `build` | Multiple unquoted expansions: `${work_built[$i]}`, `${work_packaged[$i]}`, `$DO_CHECK`, `$B_FORCE`, `$missing`, etc. |
| `torepo` | Unquoted: `$pkg`, `$SERVER`, `$REPONAME`, `$flags`, `$filename` |
| `clean` | Unquoted: `$BASE`, `$CUR`, `${PIPESTATUS[3]}`, `${BASH_SOURCE[0]}` |
| `debclean` | Unquoted: `$BASE`, `$CUR`, `${PIPESTATUS[3]}`, `${BASH_SOURCE[0]}` |

**Recommendation:** Wrap all variable expansions in double quotes. This is also flagged by shellcheck as SC2086.

### 1.10 Use `local` for Function-Scoped Variables (Variables and Scope)

The bash skill requires `local` for variables only used within a function.

| File | Issue |
|------|-------|
| `build` | Several functions have variables without `local`: `build()` sets `B_NAME`, `B_VERSION`, `versiondir` without `local` (some are intentionally global/exported, but `versiondir` is local-only); `version_get()` sets `ver` without `local`; `package_deb()` has many unlocalised vars; `require_software()` exits before returning |
| `torepo` | `ret`, `filename` are not declared `local` |
| `clean` | `answer` is not `local` |
| `debclean` | `answer` is not `local` |

**Recommendation:** Audit each function and add `local` to variables that don't need to be global.

### 1.11 Use `readonly` for Constants (Variables and Scope)

Variables that should never change after assignment should use `readonly`.

| File | Issue |
|------|-------|
| `build` | Constants like `LOCK=/tmp/build.lck` and default paths are set without `readonly` |
| `torepo` | No `readonly` usage |
| `clean` | `BASE`, `CUR`, `LOCATION` should be `readonly` after assignment |
| `debclean` | Same as `clean` |

### 1.12 Use `command -v` Not `which` (Command Usage)

No instances of `which` were found. ✅

### 1.13 Never Parse `ls` Output (Command Usage)

No instances of parsing `ls` output were found. ✅

### 1.14 Never Use `eval` (Command Usage)

| File | Line | Issue |
|------|------|-------|
| `build` | ~line 935 | `eval "${OS/*=/OS=}"` — evaluates arbitrary content from `/etc/os-release` |
| `clean` | ~line 31 | `eval ${os/*=/os=}` — same pattern |
| `build` | ~line 648 | `B_GITVER` constructs a command string and runs it with `bash -c "$CMD"` — functionally similar to `eval` |

**Recommendation:** Replace `eval` with safer alternatives. For `/etc/os-release` parsing, use `source /etc/os-release` directly (it's designed for that) or parse with `grep`/`cut`. For `B_GITVER`, consider restructuring using arrays.

### 1.15 Use `$(command)` Not Backticks (Command Usage)

No instances of backticks were found. ✅

### 1.16 Guard Clauses (Conditionals and Control Flow)

The bash skill prefers guard clauses (early returns) over deeply nested if/then/else.

| File | Issue |
|------|-------|
| `build` | `build()` has deeply nested conditionals for BUILD section fallback; `recipe_section_get()` uses nested `if/else` instead of guard clauses; `B_GET()` has nested if/else for each method |
| `clean` | Deep nesting in case statements |
| `debclean` | Same as `clean` |

**Recommendation:** Refactor to use guard clauses where possible (return early on error conditions).

### 1.17 Prefer Long Options (Formatting and Style)

The bash skill prefers long options (e.g., `--force`) over short flags (e.g., `-f`) in scripts for readability.

| File | Examples |
|------|----------|
| `build` | `mkdir -p`, `rm -rf`, `grep -v`, `tar cfz`, `tar xfB -`, `cut -d`, `sort -t`, `flock -w 60`, `wget -q -O -` |
| `torepo` | `scp -q`, `basename -s` |
| `clean` | `dpkg -l`, `xargs sudo apt-get -qq -y install`, `xargs sudo apt-get -qq --purge -y remove` |

**Recommendation:** Replace short flags with their long equivalents where available. Note: not all commands have long options (e.g., `tar`, `cut`, `grep`), so use judgment.

### 1.18 Use `trap` for Cleanup (Error Handling and Robustness)

The bash skill requires `trap` to clean up temporary files and resources on exit.

| File | Issue |
|------|-------|
| `build` | `build()` creates a temp dir with `mktemp` and does `rm -rf "$TMP"`, but if the script is interrupted (SIGINT/SIGTERM), the temp dir is leaked |
| `torepo` | No cleanup concerns |
| `clean` | Creates `$CUR` temp file; has `rm -f $CUR` but not in a trap |
| `debclean` | Same as `clean` |

**Recommendation:** Add `trap 'rm -rf "$TMP"' EXIT` (or similar) patterns to ensure cleanup on script termination.

### 1.19 Function Definition Style (Formatting and Style)

The bash skill requires `funcname()` style, not `function funcname()`.

All functions use the `funcname()` style. ✅

### 1.20 Naming Conventions (Naming)

- Use `snake_case` for functions and variables
- Global variables must be fully UPPERCASE

| File | Issue |
|------|-------|
| `build` | Mix of conventions: `distr`, `rel`, `retval`, `pkgs`, `result`, `opts` are lowercase locals (some should be uppercased globals); function names are `snake_case` ✅ |
| `torepo` | `ret`, `filename`, `flags` should be `local` |
| `clean` | `answer` should be `local` |

**Recommendation:** Audit globals — make them UPPERCASE. Ensure locals are `local` and `snake_case`.

### 1.21 Avoid Redirecting to `/dev/null` if Output Might Be Useful (Error Handling)

| File | Issue |
|------|-------|
| `build` | Many `> /dev/null 2>&1` suppressions that could hide useful debugging info (e.g., `apt-get` install output, `dpkg-query` errors, `git clone` errors) |
| `torepo` | `scp -q` and `ssh` errors are not captured |
| `clean` | `apt-get` output fully suppressed with `> /dev/null 2>&1` |
| `debclean` | Same as `clean` |

**Recommendation:** Only redirect stderr intentionally. When suppressing for quiet mode, redirect to a log file instead.

---

## 2. Shellcheck Findings

### 2.1 `build` — Shellcheck Issues

| Code | Severity | Description |
|------|----------|-------------|
| SC2086 | Info | Multiple unquoted variable expansions (e.g., `${work_built[$i]}`, `$DO_CHECK`, `$B_FORCE`) |
| SC2004 | Style | Unnecessary `$` on arithmetic variables (e.g., `work_version[$i]`, `work_built[$i]`) |
| SC1091 | Info | Not following sourced file `.buildrc` (expected, but add shellcheck directive) |
| SC2329 | Info | Functions `B_GITVER`, `B_GITLABVER`, etc. never invoked directly (they're exported via `export -f`) |

### 2.2 `torepo` — Shellcheck Issues

| Code | Severity | Description |
|------|----------|-------------|
| SC1090 | Warning | Can't follow non-constant source `~/.toreporc` |
| SC2048 | Warning | Use `"$@"` instead of `$*` to prevent whitespace problems |
| SC2086 | Info | Multiple unquoted variable expansions (`$pkg`, `$SERVER`, `$filename`, `$REPONAME`) |
| SC2029 | Info | `ssh` command expands variables on client side instead of server |

### 2.3 `clean` — Shellcheck Issues

| Code | Severity | Description |
|------|----------|-------------|
| SC1090 | Warning | Can't follow non-constant source `~/.cleanrc` |
| SC2086 | Info | Unquoted expansions (`$BASE`, `$CUR`, `${BASH_SOURCE[0]}`, `${PIPESTATUS[3]}`) |
| SC2162 | Info | `read` without `-r` will mangle backslashes |

### 2.4 `debclean` — Shellcheck Issues

Same issues as `clean` (SC2086, SC2162) plus identical unquoted variable patterns.

---

## 3. Structural and Code Quality Issues

### 3.1 `build` — Script Too Large

The `build` script is approximately 1000 lines with deeply nested logic. The `build()` function alone is ~200 lines and defines inner functions (`B_GET`, `B_UPDATEPKGBLD`, `B_LINKFILES`, `B_LINKFILE`) that are exported via `export -f`.

**Recommendation:** Consider splitting into multiple files (e.g., `lib/recipe.sh`, `lib/package.sh`, `lib/version.sh`) and sourcing them. This improves maintainability and testability.

### 3.2 `build` — Inconsistent Error Handling

- `B_GET()` uses `exit 1` instead of `return 1` in several places (http, sf, git, go, hg, svn methods). This terminates the entire script rather than allowing the caller to handle the error.
- `require_software()` calls `exit 1` after echoing required packages — the `echo` line exits with 1, not the function.
- `build()` mixes `return 1` and `exit 1` patterns.

**Recommendation:** Use `return` consistently within functions. Reserve `exit` for `main()` or top-level error handling. Let callers decide how to handle failures.

### 3.3 `build` — Unused Code

- `package_rpm()` is defined but only contains `echo "Creating rpm packages is not implemented."` followed by `exit 1`. This is dead code that should either be removed or properly stubbed.
- `recipe_check_builddistro()` is defined but appears identical to `recipe_select_arch()`. It's never called.
- `B_GITVER`, `B_GITLABVER`, `B_GITHUBVER`, `B_SFVER`, `B_SVNDATE`, `B_SVNREV`, `B_HGREV` are exported but shellcheck flags them as never invoked directly (they're used in evaluated recipe code, so this is by design — add shellcheck directives).

### 3.4 `build` — `PIPESTATUS` Usage Issues

The script uses `${PIPESTATUS[0]}` and `${PIPESTATUS[1]}` in `build_require()` and other places. After any intervening command, `PIPESTATUS` is reset. This is fragile and error-prone.

**Recommendation:** Refactor pipelines to avoid relying on `PIPESTATUS`. Use process substitution or temporary files instead.

### 3.5 `build` — `eval` Usage for OS Detection

```bash
OS=$(grep "^NAME" /etc/os-release)
eval "${OS/*=/OS=}"
```

This is dangerous — if `/etc/os-release` contains unexpected content, it could lead to code injection. `/etc/os-release` is designed to be sourced directly.

**Recommendation:** Replace with:
```bash
source /etc/os-release
```

### 3.6 `torepo` — Uses `set -e` (Forbidden)

Line 28 has `set -e`, which the bash skill explicitly forbids.

**Recommendation:** Remove `set -e` and add explicit error checking on commands that matter.

### 3.7 `torepo` — Missing Proper Argument Parsing

The script uses ad-hoc `test` checks for arguments instead of `getopts`. It also uses `$*` instead of `"$@"`.

**Recommendation:** Use `getopts` for proper option parsing and `"$@"` for argument iteration.

### 3.8 `clean` and `debclean` — Near-Duplicate Code

These two scripts are almost identical. The only differences are:
- Configuration file name (`~/.cleanrc` vs `~/.debcleanrc`)
- Base list filename prefix (`clean` vs `debclean`)
- `clean` has OS detection and case statements; `debclean` is Debian-only
- `clean` has slightly different confirmation logic (`Y`/`YES` vs `y`)

**Recommendation:** Merge into a single script with OS-aware behavior. The `clean` script already has the framework for this.

### 3.9 `clean` — Inconsistent Confirmation Logic

In `clean`, the confirmation for `-u` checks for `Y` or `YES` (case-insensitive via `${answer^^}`), while `debclean` only checks for `y`. This inconsistency could be confusing.

**Recommendation:** Standardize confirmation logic across both scripts (or the merged script).

### 3.10 `clean` — Missing OS Detection Fallback

The `clean` script detects the OS but only implements functionality for Debian. Other OSes just print "Not implemented" and silently do nothing for `-c` and `-l` options.

**Recommendation:** Add a meaningful error message and non-zero exit code for unsupported OSes.

### 3.11 Documentation Typos

| File | Line/Section | Typo |
|------|--------------|------|
| `BUILD.md` | Synopsis | "secition" → "section" |
| `BUILD.md` | -r option | "specfified" → "specified" |
| `BUILD.md` | VERSION section | "repostiory" → "repository" |
| `BUILD.md` | BUILD section | "refrence" → "reference" |
| `BUILD.md` | BUILD section | "perviously" → "previously" |
| `BUILD.md` | BUILD section | "succesfully" → "successfully" |
| `BUILD.md` | BUILD section | "doens't" → "doesn't" |
| `BUILD.md` | BUILD section | "sustituted" → "substituted" |
| `BUILD.md` | BUILD section | "specifiec" → "specific" |
| `BUILD.md` | BUILD section | "environemnt" → "environment" |
| `BUILD.md` | BUILD section | "besta" → "beta" |
| `BUILD.md` | PACKAGE section | "pacakge" → "package" |
| `BUILD.md` | PACKAGE section | "dependancy" → "dependency" (multiple occurrences) |
| `BUILD.md` | DEB section | "inforation" → "information" |
| `BUILD.md` | DEB section | "dependancies" → "dependencies" |
| `BUILD.md` | DEB section | "One specifiec" → "One specific" |
| `BUILD.md` | DEB_DEPENDS section | "dependancies" → "dependencies" |
| `BUILD.md` | TO REPO section | "build" → "built" |
| `BUILD.md` | REPORTING BUGS | "Prefferably" → "Preferably" |
| `CLEAN.md` | FILES section | "cliean" → "clean" |
| `CLEAN.md` | DESCRIPTION | "administation" → "administration" |
| `DEBCLEAN.md` | FILES section | "debcliean" → "debclean" |
| `DEBCLEAN.md` | DESCRIPTION | "administation" → "administration" |
| `TOREPO.md` | REPORTING BUGS | "Prefferably" → "Preferably" |
| `MULTI.md` | Global assumptions | "envirements" → "environments" |
| `MULTI.md` | Binary storage | "versio" → "version" |
| `README.md` | Description | "dependancies" → "dependencies" |
| `INSTALL.md` | Heading | "Dependancies" → "Dependencies" |
| `buildrc-example` | Comment | "dependancies" → "dependencies" |
| `build` (script) | Multiple | "dependancies" → "dependencies" |
| `build` (script) | Multiple | "dependancy" → "dependency" |
| `test.recipe` | [PKG] | "torepo=y" section placement |
| `build.recipe` | [DEB] | Two `Depends:` lines (second will override first) |

---

## 4. Security Concerns

### 4.1 `build` — Arbitrary Code Execution via `eval` and `bash -c`

The `eval` on line ~935 and the `bash -c "$CMD"` pattern in `B_GITVER` execute arbitrary strings as shell commands. While this is by design (recipe files contain shell code), it's a significant attack surface if recipe files are not trusted.

**Recommendation:** At minimum, document that recipe files must be from trusted sources. Consider adding a warning in documentation.

### 4.2 `torepo` — Unquoted Variables in SSH/SCP Commands

`$pkg`, `$SERVER`, `$REPONAME` are passed unquoted to `scp` and `ssh`, which could lead to injection if these values contain spaces or special characters.

**Recommendation:** Quote all variables, especially those used in remote commands.

### 4.3 `build` — Source Command Sourcing Arbitrary Config

Sourcing `~/.buildrc` and `~/.toreporc` without validation means any code in those files is executed with the user's privileges.

**Recommendation:** Document that these config files should be protected. Consider validating them or reading them with a safer method.

---

## 5. Missing Features / Enhancements

### 5.1 No `--help` Long Option

None of the scripts support `--help` as a long option (only `-h`). The bash skill recommends long options.

### 5.2 No Proper Logging Framework

The `build` script has an `output()` function but the other scripts just use `echo`. Consider a unified logging approach.

### 5.3 No `--version` Flag

None of the scripts have a `--version` flag.

### 5.4 No Temporary File Cleanup in `build()`

While `build()` does `rm -rf "$TMP"` at the end, if the script crashes or is killed mid-build, the temporary directory is left behind.

### 5.5 Lock File in `/tmp`

The lock file is created at `/tmp/build.lck`, which is world-writable. This could allow symlink attacks.

**Recommendation:** Use `XDG_RUNTIME_DIR` or a dedicated directory under the user's home.

---

## 6. Summary of Priority Fixes

| Priority | Issue | Files |
|----------|-------|-------|
| **High** | Use `set -u`; remove `set -e` from `torepo` | All |
| **High** | Quote all variable expansions | All |
| **High** | Replace `eval` with safer alternatives | `build`, `clean` |
| **High** | Replace `test` with `[[`; use `(( ))` for arithmetic | All |
| **High** | Replace `echo` with `printf` | All |
| **High** | Use `return` instead of `exit` in functions | `build` |
| **Medium** | Use `#!/usr/bin/env bash` shebang | All |
| **Medium** | Add `main` function to `torepo`, `clean`, `debclean` | 3 files |
| **Medium** | Use `local` for function-scoped variables | All |
| **Medium** | Use `readonly` for constants | All |
| **Medium** | Add `trap` for temp file cleanup | `build`, `clean`, `debclean` |
| **Medium** | Use `"$@"` instead of `$*` | `torepo` |
| **Medium** | Add `read -r` | `clean`, `debclean` |
| **Medium** | Fix shellcheck SC2086 warnings | All |
| **Low** | Use long options where available | All |
| **Low** | Fix documentation typos | All `.md` files |
| **Low** | Merge `clean` and `debclean` | `clean`, `debclean` |
| **Low** | Use guard clauses instead of deep nesting | `build` |
| **Low** | Add `--version` and `--help` long options | All |