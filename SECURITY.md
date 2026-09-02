# Supply Chain Security

This document analyses the supply-chain risks introduced by the `build`
project and proposes a roadmap of mitigations that can be implemented
within this repository.

`build` automates a pipeline that, when run on a schedule (e.g.
`build -b -p -r -a`), reaches out to the internet, fetches source code,
compiles it, packages it into `.deb` files, and publishes them to an apt
repository that downstream machines then `apt install` from.

The project's stated purpose is to package software that has **frequent
updates**. That is also its chief supply-chain liability: the
fetch → build → ship loop runs unattended and repeatedly, so a compromise
of any upstream source is propagated to consumers quickly and silently.
This document exists to make that risk explicit and to lay out concrete
reductions implementable inside this codebase.

It is a *recommendations document only*. No behaviour described here is
implemented yet; each section is a proposal to be reviewed and accepted
before code is written.

---

## 1. Threat model

The assets at risk are the **consumers of the packages** produced by
this system. The build host itself is also an asset, but is out of scope
here (build-system-local issues to keep in mind: `eval`, unquoted
`ssh`/`scp` arguments, sourcing untrusted config).

The adversaries of interest, in rough order of likelihood for
frequent-update software:

1. **Compromised upstream maintainer or upstream account.** A maintainer
   pushes a malicious tag/commit, or their account/GPG key is taken over.
   Without signature or pinning checks the build happily packages it.
2. **Compromised upstream infrastructure.** The git host, SourceForge,
   GitHub API, or the download mirror serves altered content to the build
   host (MITM, repo hijack, CDN compromise). Plain `http` fetches and
   unverified `wget` downloads are directly exposed.
3. **Backdoored build tooling / build-time network calls.** The build
   process itself reaches out during compile (the XZ/libxz pattern) to
   fetch or activate payload. Today the container has unrestricted
   network access for the whole build.
4. **Tampering between build and consumer.** A package is altered on the
   apt repo, in transit, or in the staging `/tmp` used by `torepo`.
   Without signatures there is nothing to detect this.
5. **Loss of auditability.** `torepo` deletes the local package after
   pushing (`rm "$pkg"`), so after the fact there is nothing to compare
   against what is published.
6. **Malicious or vulnerable transitive build-time dependencies.** The
   software being built does not just compile its own source — its build
   system pulls in external dependencies at build time: Python packages
   (`pip`), Node modules (`npm`/`yarn`), Rust crates (`cargo`), Go
   modules, C/C++ libraries via `vcpkg`/`conan`/`meson`/`cmake
   FetchContent`, git submodules, and autoconf/m4 macros. These are
   fetched from public registries with no pinning, no hashing, and no
   scanning. This is the exact vector the **XZ/liblzma backdoor** used:
   the payload was hidden inside the maintainer's release tarball and
   extracted by a modified `build-to-host.m4` macro during `./configure`,
   then compiled into `liblzma` only when built in a specific distro
   environment. Source-integrity checks on the primary fetch (group A)
   do **not** cover this, because the malicious content was inside the
   trusted release artifact itself and was activated by the build
   process fetching/extracting it.

Threats 1–3 and 6 are mitigated by **source integrity + hermetic builds
+ dependency integrity (groups A, B3, F)**.
Threats 4–5 are mitigated by **output signing + provenance + retention
(group D, E)**.

---

## 2. Current exposure, by stage

| Stage | Code path | Risk |
|------|-----------|------|
| Version check | `B_GITVER` (`git ls-remote --tags`), `B_GITHUBVER`/`B_GITLABVER` (unauthenticated REST), `B_SFVER` (SourceForge RSS) | Newest tag/commit becomes the "version" with no authorship check. A moved tag is silently built. |
| Source fetch | `B_GET` (`git clone`, `wget`, `go get`, `svn`, `hg`) | No commit signature verification. No checksum/SBOM pinning. Plain `http` allowed. TLS not enforced. |
| Build deps | `apt-get install` of `[REQUIRED]` inside container; entrypoint runs `apt-get update > /dev/null 2>&1` | No apt pinning. `apt-get update` failure swallowed, so a malicious mirror/MITM could inject packages unnoticed. Non-reproducible. |
| Build | Recipe `[BUILD]` shell runs arbitrary code from fetched source | No isolation between network and build. Recipe code runs as `builduser` with broad mounted dirs. |
| Build-time deps | `pip`, `npm`, `cargo`, `go get`, `vcpkg`/`conan`, `cmake FetchContent`, git submodules, autoconf/m4 macros run inside `[BUILD]` | No lockfile/hash enforcement. No registry pinning (dependency confusion, typosquatting). No vulnerability scanning of resolved deps. Hidden payload (XZ pattern) not detected. |
| Package | `fakeroot dpkg --build`; control file from unvalidated strings | `.deb` is unsigned. No integrity metadata attached. |
| Publish | `torepo`: `scp` + `ssh … repo-add`; then `rm "$pkg"` | No integrity metadata stored. `repo-add` not verified. Package deleted after send → no local audit trail. |
| Base images | `docker/Dockerfile.*` use `FROM debian:<distro>` (mutable tag); `:latest` image selection | Image not pinned by digest. `apt-get install` at image build time is non-reproducible. |

The Docker-based ephemeral build model is a good foundation (isolated,
throwaway containers, host not polluted). The mitigations below leverage
that foundation rather than replace it.

---

## 3. Proposed mitigations

Grouped by priority and effort. Each is implementable within this
repository (the `build` script, recipe format, Dockerfiles, `torepo`).

### A. Source integrity at fetch time — highest impact, low effort

**Status: implemented.** A1–A4 are implemented in the `build` script, the
`[INFO]` recipe keys (`gpgkey`, `gpgkeyfile`, `commit`, `sha256`,
`allow_insecure`), the `B_GITCHECKOUT` helper, the Docker base images (which
now install `gnupg`), and `BUILD.md`. See `BUILD.md` for the recipe-facing
documentation. `gpgkeyfile` lets a recipe ship the public key locally so A1
works in network-restricted build environments; otherwise `B_GITCHECKOUT`
falls back to fetching from keyservers.

**A1. Verify git tag/commit signatures.**
`B_GET git` currently does `git clone` then `git checkout tags/v$B_VERSION`.
Add GPG verification:

```bash
git verify-tag --raw "v$B_VERSION" || { output "Tag signature invalid/missing"; return 1; }
```

Allow recipes to declare an expected signer in a new `[INFO]` key:

```
gpgkey=<40-char fingerprint or keyring id>
```

`git` already ships in the container; adding `gnupg` is one Dockerfile
line. Recipes without a `gpgkey` could be allowed but warned, or refused
when a strict mode is enabled.

**A2. Support pinned commits/SHAs in recipes.**
A recipe today only knows a version *string*, then checks out
`tags/v$B_VERSION`. Tags can be moved by upstream. Add optional fields:

```
commit=<40-char sha>
sha256=<hex digest of a fetched http asset>
```

Refuse to build if the resolved ref doesn't match the pinned commit. This
makes "what was built" deterministic and auditable, and makes
version-string-only recipes the explicitly opt-in default rather than the
only option.

**A3. Verify checksums for `http`/`sf` downloads.**
`B_GET http` blindly runs `wget -O "$target" "$url"`. Let recipes declare
`sha256=<…>` (or a `.sha256` sibling URL) and verify with `sha256sum -c`
before caching. Reject unsigned plain `http` unless explicitly allowed.

**A4. Enforce HTTPS / reject downgrade.**
Add a sanity check that `url` starts with `https://`, `git@`, or
`ssh://`. Pass `wget --https-only --secure-protocol=TLSv1_2`. The
`B_SFVER` SourceForge `http` RSS fetch is a weak link to address.

### B. Build & base-image reproducibility — medium effort

**B1. Pin Docker base images by digest.**
`docker/Dockerfile.*` use `FROM debian:trixie` — a tag that moves. Pin to
`debian:trixie@sha256:…` and record the digest. `docker_image_select`
returns `build-trixie:latest`; builds should record the resolved image
digest (`docker inspect --format='{{index .RepoDigests 0}}'`) into the
provenance sidecar (see D1).

**B2. Make `apt-get` failures visible and reproducible.**
The entrypoint does `apt-get update > /dev/null 2>&1` then installs deps,
swallowing errors. At minimum:

- fail the build when `apt-get update` exits non-zero,
- log the installed package versions (`dpkg -l` snapshot) into provenance.

`clean` already provides a baseline-snapshot mechanism that could be
reused to make `[REQUIRED]` installs reproducible per build.

**B3. Hermetic build phase (separate fetch from build).**
The container currently has network access for the whole build. A strong
mitigation, modelled on how reproducible-build projects and SLSA Build L3
hardening work:

1. **Fetch phase** — run with network, retrieve and verify all sources
   into `$B_CACHEDIR` (applying A1–A4).
2. **Build phase** — run the container with `--network=none`, compiling
   only from the cache.

This blocks the "build script phones home during compile" attack (the XZ
backdoor's hidden fetch step). The Dockerfile/entrypoint split already
supports two phases; it is a matter of running `docker run --network=none`
for the build phase once sources are populated. `[REQUIRED]` dependency
installation must finish before the network is removed.

### C. Recipe trust & build-system provenance

**C1. Sign and verify recipes.**
Recipes are executable shell — they are the highest-trust input. If
`RECIPEDIR` is a git repository (it effectively is, on the build host),
the script should:

- record the recipe directory's `git rev-parse HEAD`,
- refuse to run if the recipe directory has uncommitted changes
  (`git diff --quiet`),
- optionally verify recipe commits against a maintainer key.

**C2. Constrain recipe code execution.**
Longer-term, recipes should declare network/filesystem needs
declaratively rather than run arbitrary shell. A practical interim: run
the build phase under `firejail`/AppArmor with a profile that denies
network except to a pinned allow-list of hosts and denies writes outside
`$B_INSTALLDIR`.

### D. Output integrity & provenance — medium-high effort, big consumer benefit

**D1. Generate SLSA-style build provenance.**

**Status: implemented.** After a successful package build, a
`<pkgfile>.provenance.json` sidecar is written next to the `.deb` in
`$PKGDIR`, recording: recipe name, version, arch, distro, package filename
and SHA-256, build number, recipe-dir `git rev-parse HEAD`, the
source-integrity pins (`commit`/`gpgkey`/`sha256`), the Docker image ID
(content digest), the real build host, a sorted `dpkg-query` snapshot of
installed packages (B2), and a UTC timestamp. See `BUILD.md` for details.

This project is a self-contained build service — exactly what SLSA's
Build track targets. After a successful build, write a JSON sidecar next
to each `.deb` recording:

- recipe name + `git rev-parse HEAD` of recipe dir,
- resolved source URL(s), tag/commit, and any verified signature,
- Docker image digest used (B1),
- `dpkg -l` snapshot of build deps (B2),
- start/end time, build host,
- `B_BUILDNR` / package ID.

This is low effort (the script already holds all these values) and gives
consumers something to verify against. It corresponds to **SLSA Build L1**
("provenance exists").

**D2. Sign the produced packages.**
`.deb` files can be signed with `dpkg-sig`, and/or the apt repo's
`Release`/`InRelease` files signed with a project GPG key. Currently
`torepo` just `scp`s the file and runs `repo-add`. The apt repo should
publish `InRelease` with detached signatures, and downstream consumers
should `apt`-verify them. Add a `SIGNKEY` config and sign in the
packaging step.

**D3. Generate an SBOM.**
A `Package:` line plus `Depends:` already exists in the control file.
Extend the packaging step to emit a CycloneDX/SPDX SBOM per package
(source URL, version, build deps, license). Frequent-update packages
especially benefit: consumers can diff SBOMs between versions to spot
suspicious new dependencies (the XZ pattern).

### E. Repository & transport hardening — low effort, high value

**E1. Replace `scp` + `ssh repo-add` with an integrity-preserving push.**
`torepo` currently:

```bash
scp -q "$pkg" "${SERVER}:/tmp"
ssh "$SERVER" "repo-add $flags $REPONAME /tmp/$filename"
rm "$pkg"
```

Problems:

- unquoted vars enable filename
  injection,
- `rm "$pkg"` destroys the local audit copy,
- `/tmp` on the server is a world-writable staging area.

Fixes: keep a signed copy in `$PKGDIR` (don't delete), transfer over a
verified channel, and have the repo verify the package signature before
adding.

**E2. Retain built artifacts + provenance.**
Keep packages and their provenance/SBOM sidecars in `$PKGDIR` for a
configurable retention window (e.g. `RETENTION=90` days). This allows
after-the-fact comparison of "what was published" vs "what's on the repo"
after a suspected compromise.

**E3. Serve provenance to consumers.**
Publish the D1 provenance + D2 signatures alongside packages on the apt
repo, so downstream clients (or a separate `build-verify` script) can
check that a package was built by the trusted build host from a signed
source.

### F. Build-time dependency integrity (transitive dependencies) — high impact, the XZ-class threat

The mitigations in groups A–E verify the *primary* source the recipe
fetches. They do not cover what the build process itself pulls in while
compiling: Python packages, Node modules, Rust crates, Go modules, C/C++
libraries via `vcpkg`/`conan`/`cmake FetchContent`/`meson wrap`, git
submodules, and autoconf/m4 macros. The XZ backdoor demonstrates that
this is the most realistic path for a sophisticated attacker: the payload
lived inside the released tarball and was extracted and compiled by the
build system, not visible in the upstream git history.

**F1. Enforce dependency lockfiles with hashes per language.**
Recipes should declare a lockfile and the build must install from it
*exactly*, refusing floating versions. Language-specific enforcement:

- **Python (pip):** `pip install --require-hashes -r requirements.txt` or
  `pip install --no-deps` from a hashed `requirements.txt`. Reject any
  recipe that runs bare `pip install <pkg>`.
- **Node (npm/yarn):** install with `npm ci` (which honours
  `package-lock.json` and refuses to mutate it) rather than `npm
  install`. Honour `--ignore-scripts` to block postinstall scripts
  unless explicitly allowed.
- **Rust (cargo):** build with `--locked --offline` so `Cargo.lock` is
  honoured and no network resolution happens; resolve through a vetted
  mirror (see F2).
- **Go:** build with `GOFLAGS=-mod=vendor` (vendored `vendor/`) or
  `-mod=readonly` against a pinned `go.sum`. The `B_GET go` method
  currently runs `go get -u`, which *upgrades* — that should never be
  the default for a release build.
- **C/C++ (vcpkg/conan/FetchContent):** pin to a manifest + baseline and
  verify asset hashes.

The `build` script can provide a `B_DEPS_VERIFY` helper, or simply
refuse to run a recipe in strict mode if no lockfile is present for a
detected ecosystem.

**F2. Route package-manager fetches through a controlled mirror.**
A private, cached, vetted registry/mirror (a pull-through cache such as
a Devpi/Nexus/Artifactory/Verdaccio/proxy) gives two protections at
once:

- **dependency confusion / typosquatting:** internal/private package
  names resolve to your mirror, not a public registry where an attacker
  can register a lookalike;
- **immutable snapshots:** the mirror can be snapshotted per build, so a
  dependency version that was safe at snapshot time cannot be silently
  replaced later (registry immutability / reproducibility).

Configure each package manager to point at the mirror (pip `index-url`,
npm `registry`, cargo `[source]`, Go `GOPROXY`) and make the public
registries unreachable during the build phase by combining with F3.

**F3. Network allow-list during the build phase (complements B3).**
B3 proposes a fully hermetic (`--network=none`) build phase. When a
recipe genuinely cannot vendor everything, a middle ground is an
egress allow-list permitting *only* the controlled mirror host(s) from
F2 and nothing else. This blocks the classic "build script phones home
to an attacker-controlled host" pattern while still allowing verified
dependency fetches. Implement with an egress-filtering Docker network
(`docker network create --internal` + a gateway, or a transparent proxy
that only forwards to the allow-list).

**F4. Vulnerability scanning of resolved dependencies (block on
known-bad).**

**Status: implemented.** The `[SECURITY]` `vulnscan=` key (`advisory` or
`enforce`) enables an automatic post-build scan of the **staged package
tree** — only what actually ships in the produced package. The installed
tree (`$B_INSTALLDIR`) is inventoried with `syft` (baked into the Docker base
image, pinned version + SHA-256 verified) into a CycloneDX SBOM, and the SBOM
is checked with `osv-scanner` (also baked into the image, pinned + verified)
against the OSV database. Scanning the staged tree rather than the whole
build tree means build-only tooling (dev dependencies, vendored test deps,
the build toolchain itself) does not trigger findings. `enforce` fails the
build on any HIGH/CRITICAL vulnerability; `advisory` reports but continues.
Per-issue exceptions can be declared in the same `[SECURITY]` section
(`vulnscan-ignore=ID1,ID2`), plus a global `VULNSCAN_IGNORE` list in
`~/.buildrc` for reviewed advisories that recur across recipes; the build
script generates the osv-scanner config from those lists and applies it to
the whole scan, so `enforce` stays active for everything else. Findings are
always logged in a copy-pasteable `[SECURITY]` format. Build-tree-wide
visibility (dev deps, vendored test deps) is provided separately by the
`security-scan` tool without failing builds. See `BUILD.md` for the
recipe-facing documentation.

After resolving dependencies (and before packaging), generate an SBOM
of the resolved dependency set and scan it against a vulnerability
database. Suitable tools that cover many ecosystems in one pass:

- **osv-scanner** (Google) — reads lockfiles/SBOMs across npm, pip,
  cargo, go, maven, gem, composer, nuget, etc. and queries the
  authoritative OSV.dev database.
- **syft** (generate SBOM) + **grype** (scan SBOM) — Anchore toolchain,
  also scans container images and the built `.deb`.
- **trivy** — filesystem/repo/image scanning in one tool.
- Per-language: `pip-audit`, `npm audit`/`pnpm audit`, `cargo audit`,
  `govulncheck`, `bundle-audit`.

For frequent-update software this is especially valuable: it surfaces a
newly-disclosed vulnerable transitive dependency before it ships.

**F5. Reproducible-build verification against a trusted reference.**
For high-value recipes, keep a trusted reference build of a known-good
version and compare a new build of the *same* inputs with
`diffoscope`/`reproducible-checks`. A divergent binary where the source
hasn't meaningfully changed is a strong signal of injected payload (the
XZ `.o` file would have shown up here). This requires recipes to be
reproducible (set `SOURCE_DATE_EPOCH`, sort file lists, etc.), which is
itself a worthwhile goal; Debian's reproducible-builds effort is the
reference. Full reproducibility is hard, so this is the highest-effort
item and best applied to a curated subset.

**F6. Detect suspicious in-tree build scripts (static guard).**

**Status: implemented.** The `[SECURITY]` `srcguard=` key (`advisory` or
`enforce`) enables an automatic post-build scan of the build tree for
suspicious build-script patterns (network access or embedded-blob decoding
in `configure`/`*.m4`/`CMakeLists.txt`/`Makefile`/`package.json` scripts).
`enforce` fails the build on any hit; `advisory` reports but continues. A
global `SRCGUARD` default in `~/.buildrc` is also supported. Per-file
exceptions can be declared in the same `[SECURITY]` section
(`srcguard-ignore=path/to/file`, paths relative to the build root; glob
patterns are supported); all hits in an ignored file are suppressed, so
`enforce` stays active for everything else. A global `SRCGUARD_IGNORE` list
in `~/.buildrc` (also glob-capable) is merged with the recipe's list. Findings
are always logged in a copy-pasteable `[SECURITY]` format. See `BUILD.md`
for the recipe-facing documentation.

A lightweight, high-signal pre-build check: scan the fetched source
tree for build scripts that perform network access or decode embedded
payloads — exactly the XZ signature (`build-to-host.m4` calling
`awk`/`sed` to decode a hidden `.xz`, `curl`/`wget`/`git clone` inside
`configure`/`m4`/`cmake`/`Makefile`). Concretely:

- grep the source tree for network-fetching commands inside
  `configure*`, `*.m4`, `CMakeLists.txt`, `Makefile*`, `*.cmake`,
  `package.json` scripts;
- flag any build script that decodes/evals embedded binary blobs
  (`base64 -d`, `xxd -r`, `eval`, `bash -c` on extracted content);
- warn (or fail in strict mode) on `curl|wget|git|svn|go get` invoked
  from anywhere under the build root other than the recipe's own
  `B_GET` calls.

This is heuristic and will produce false positives, so default to
advisory and let recipes allow-list expected patterns. It would,
however, have caught the XZ `build-to-host.m4` extraction step.

**F7. Prefer git-tag builds over maintainer tarballs; diff tarball vs
git export.**
The XZ payload existed only in the release tarball, not in the git
repository, so building from a verified git tag (A1) and *ignoring*
maintainer-provided tarballs sidesteps the entire class. Where a
tarball is unavoidable (e.g. SourceForge releases), compute and record
the diff between the tarball and `git archive` of the same tag and
review the differences (added generated files are expected; added
opaque blobs in `tests/` are not). The `B_GET http` method currently
treats a fetched tarball as opaque — this check makes it auditable.

---

## 4. SLSA alignment

The proposals map onto the [SLSA Build track](https://slsa.dev/spec/v1.0-rc2/levels):

| SLSA level | Requirement | Covered by |
|-----------|-------------|------------|
| Build L1 | Provenance showing how the package was built | D1 |
| Build L2 | Signed provenance, generated by a hosted build service | D1 + D2 |
| Build L3 | Hardened build service (isolated, non-forgeable) | B3 + C2 + F3 |

Today the project sits at **Build L0** (no provenance, no signing, no
hardening). The roadmap below reaches L1/L2 with modest effort and L3
with the hermetic-build work.

---

## 5. Prioritised roadmap

If only a few things are done, these give the most reduction per effort:

1. **B1 + D2** — pin image digest, sign packages. Closes the "is this
   even from us?" gap for consumers.
2. **A1 + A2** — verify tag signatures, allow pinned commits. Closes the
   "did we build what the maintainer actually released?" gap, the most
   common real attack vector for frequent-update software.
3. **F1 + F4** — enforce hashed lockfiles per language and scan resolved
   dependencies for known vulnerabilities. Directly addresses the XZ-class
   build-time dependency threat, which A/B do not cover.
4. **B3 + F3** — hermetic / allow-listed build phase. Defends against
   backdoors that fetch at build time, the modern threat model.
5. **D1 + D3** — provenance + consumer verification. Gives a story
   equivalent to SLSA Build L1/L2 and lets the whole downstream estate
   verify rather than trust.

F5 (reproducible-build verification) and F6 (static build-script guard)
are higher-effort, high-value additions for a curated subset of
security-critical recipes (anything that ends up in `sshd`, `sudo`,
privilege boundary, etc.).

Each item is independently shippable and testable on the `build`
container.

---

## 6. Out of scope

- Build-host-local security (untrusted `~/.buildrc`, `eval`, unquoted
  `ssh` arguments) is out of scope for this document.
- General Debian/apt repo operational security (key custody, repo host
  hardening): belongs in the repository operator's runbook, not this
  build tool.
- Hardware supply chain, certificate/root-of-trust management, incident
  response.

## 7. References

- SLSA (Supply-chain Levels for Software Artifacts), Build track:
  https://slsa.dev/spec/v1.0-rc2/levels
- CNCF TAG Security, *Software Supply Chain Best Practices v2*:
  https://github.com/cncf/tag-security/blob/main/community/working-groups/supply-chain-security/supply-chain-security-paper-v2/SSCBPv2.md
- OpenSSF *Package Manager Best Practices* (npm guide, others linked):
  https://github.com/ossf/package-manager-best-practices
- How the XZ/liblzma backdoor worked (build-time payload via m4 macro):
  https://lwn.net/Articles/967192/
- osv-scanner (multi-ecosystem dependency vulnerability scanner):
  https://github.com/google/osv-scanner
- syft (SBOM generation) and grype (SBOM/image scanning):
  https://github.com/anchore/syft , https://github.com/anchore/grype
- trivy (filesystem/repo/image vulnerability scanner):
  https://github.com/aquasecurity/trivy
- diffoscope (reproducible-build verification):
  https://diffoscope.org/
- pip secure installs (`--require-hashes`):
  https://pip.pypa.io/en/latest/topics/secure-installs/