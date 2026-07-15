# Fork Release Strategy — PrusaSlicer-Wayland

This fork carries a small set of custom changes on top of upstream
`prusa3d/PrusaSlicer`. This document describes how the branches are organised and
how to cut a release when upstream tags a new version. It is written for any
maintainer — human or AI agent — working from a fresh clone.

## Goals

1. Each feature lives in its **own isolated branch** (only that feature's commits)
   so it can be reviewed or proposed upstream on its own.
2. **Documentation is separate from code**, so an upstream pull request never has
   to carry fork-specific docs.
3. Each upstream version gets a **frozen tag** containing all active features —
   reproducible, never rebased, never force-pushed.
4. On every new upstream tag we **rebase, re-check relevance** (did upstream absorb
   a feature?), and cut a new tag.
5. Every release marks the binary as a **fork build**, visible in the About and
   System Info dialogs.

## Branch model

```
upstream/master ─▶ master                 (mirror only, fast-forward)

version_X.Y.Z (upstream tag)
   ├── feat/wayland         native Wayland (GTK3+EGL) + build env + CMake 4   [upstream-PR candidate]
   │    └── feat/wx3.3       wxWidgets 3.3.3 upgrade + warning cleanup         [stacked on feat/wayland]
   ├── feat/mmu-temp-fix    wipe-tower temperature sync (WipeTower.cpp/.hpp)   [upstream-PR candidate]
   ├── feat/branding        fork identity in the About / System Info dialogs   [fork-only]
   └── feat/docs            all fork docs incl. this file and CLAUDE.md        [fork-only]

release  = version_X.Y.Z + all active features
           + version.inc identity (SLIC3R_FORK_ID)
   └── tag vX.Y.Z-wayland-wx<W>   frozen "my version"
```

- **`feat/*`** are *rolling* branches: each holds only its own commits on top of
  the newest upstream release and is rebased forward each cycle.
- **`feat/wx3.3` is stacked on `feat/wayland`** — it genuinely extends it (shares
  `deps/+wxWidgets/wxWidgets.cmake` and GUI files). Stacked features are branched
  off the feature they extend, not off `version_X.Y.Z`; see the exception below.
- The tag is *frozen*: created once, never rebased. Its commits are cherry-picks
  of the `feat/*` commits — no ref link back, so upstream PRs still come from the
  `feat/*` branch.
- Disjoint-file features (e.g. MMU touches only `WipeTower.*`) cherry-pick together
  conflict-free.
- **Shared files** (`version.inc`) are edited only at release time, not on a
  `feat/*`, to avoid cherry-pick collisions.

### Stacked / non-disjoint features (exception)

`feat/wx3.3` extends `feat/wayland`. The generic `merge-base … version_PREV`
rebase and `version_NEW..feat/$f` cherry-pick are WRONG for it (they replay the
parent's commits twice). Instead:

```bash
# Rebase the stacked branch onto the new base, relative to the PARENT's old tip:
git rebase --onto version_NEW <old parent tip> feat/wx3.3
# Cherry-pick ONLY its delta, AFTER the parent, in dependency order:
git cherry-pick feat/wayland..feat/wx3.3
```

## Fork identity (how a build advertises itself)

Set at **release time**, on the integration branch only:

- `version.inc` → `set(SLIC3R_FORK_ID "Wayland (GTK3 + EGL) · wxWidgets 3.3.3")`
  — the human label shown under the version in the About dialog and on the `Fork:`
  line in System Info. Keep it across version bumps; update it when the shipped
  feature set changes.
- `SLIC3R_BUILD_ID` is left as the upstream `+UNKNOWN` placeholder; `CMakeLists.txt`
  then auto-derives it from `git describe --tags --always --dirty` at configure
  time, so a tagged build reports e.g. `PrusaSlicer-v2.9.6-wayland-wx3.3.3`. Do
  **not** hand-edit `SLIC3R_VERSION` / `SLIC3R_APP_NAME` / `SLIC3R_APP_KEY`.

Because the build id comes from the tag at configure time, **create the tag before
the release build** (or reconfigure after tagging) so it gets embedded.

## Cutting a release for a new upstream `version_NEW`

Enable rerere once: `git config rerere.enabled true`.

```bash
git fetch upstream --tags
git checkout master && git merge --ff-only upstream/master

# 1) Move each feature onto the new base; check whether upstream absorbed it.
#    Disjoint features:
for f in wayland mmu-temp-fix branding docs; do
  old=$(git rev-parse feat/$f)
  base=$(git merge-base feat/$f version_PREV)
  git rebase --empty=drop --onto version_NEW "$base" feat/$f
  git range-diff version_PREV.."$old" version_NEW..feat/$f   # dropped/empty ⇒ upstream absorbed it
done
#    Stacked feat/wx3.3 (see exception above):
git rebase --onto version_NEW <old feat/wayland tip> feat/wx3.3

# 2) Assemble the release on the stacked integration branch (it already carries
#    wayland+wx3.3), then cherry-pick the disjoint features onto it:
git checkout feat/wx3.3
git cherry-pick -x version_NEW..feat/mmu-temp-fix     # MMU (WipeTower.* only)
# (branding is implemented directly on the integration branch this cycle;
#  feat/branding's older SLIC3R_MODIFICATIONS approach is superseded — do not merge it.)

# 3) Set the fork identity on the integration branch (version.inc SLIC3R_FORK_ID).

# 4) Currency audit + build + smoke-test (below), then tag and push.
git tag -a vNEW-wayland-wx<W> -m "PrusaSlicer NEW — Wayland + wxWidgets <W> fork"
git push origin feat/wayland feat/wx3.3 feat/mmu-temp-fix feat/docs vNEW-wayland-wx<W>
```

> Note: this cycle the release was tagged directly on `feat/wx3.3` (the stacked
> integration branch) with the MMU commit cherry-picked onto it, rather than on a
> separate `release/X.Y.Z` branch. Either is fine as long as the tag is frozen.

## Currency audit (mandatory before tagging)

Open every committed doc and reconcile it with reality — no stale version numbers,
no "pending" for things now done, no CMake-3.x-only or X11-only assumptions,
complete dependency lists, no dead branch/tag references, no contradictions
between docs. Land fixes as a `docs: sync to X.Y.Z state` commit.

## Verify before pushing (build + behaviour)

- `make` from a clean-ish tree must configure and build (CMake 4 / wx 3.3.3).
- `make run` must launch; About shows the fork line, System Info shows the
  `Build:`/`Fork:` lines.
- For functional features, drive them: the MMU change alters G-code, so slice a
  multi-material model with a toolchange and inspect the M104/M109 output — a green
  build is not sufficient proof.

## Build environment (Ubuntu 26.04 / CMake 4)

```
sudo apt install -y git build-essential autoconf automake libtool libtool-bin \
    cmake libglu1-mesa-dev libgl1-mesa-dev libegl1-mesa-dev libgtk-3-dev \
    libdbus-1-dev libwebkit2gtk-4.1-dev libwayland-dev wayland-protocols \
    libxkbcommon-dev texinfo libhidapi-dev
```

The `Makefile` exports `CMAKE_POLICY_VERSION_MINIMUM=3.5` (inherited by every child
cmake); `deps/CMakeLists.txt` also appends it to `DEP_CMAKE_OPTS`. Build with
`make` (deps once, then the app). See `CLAUDE.md` and
`doc/How to build - Linux Wayland.md`.

## Features — current status (release `v2.9.6-wayland-wx3.3.3`)

| Feature | Branch | Upstream PR? | Notes |
|---|---|---|---|
| Native Wayland (GTK3+EGL) + build env + CMake 4 | `feat/wayland` | yes | 4 blockers: wx GTK3/EGL, GUI_App gtk-menu-images guard, Setup.cpp GDK_BACKEND, GLEW_EGL |
| wxWidgets 3.3.3 upgrade + API compat + warning cleanup | `feat/wx3.3` (stacked) | yes | Prusa 3.2.6 fork → upstream 3.3.3; `-Wno-overloaded-virtual` scope; CMP0175 fixes |
| `PrintConfig` uninitialized `val1/val2` fix | `feat/wx3.3` | **yes — see `fix/coenums-uninitialized-val`** | one-liner, off upstream/master for a clean PR |
| MMU wipe-tower temperature sync | `feat/mmu-temp-fix` | yes | `WipeTower.cpp/.hpp` only, gated on `m_semm` |
| Fork identity in About / System Info | integration branch | no | `SLIC3R_FORK_ID` + `git describe` build id |
| Fork documentation | `feat/docs` | no | this file, `CLAUDE.md`, Wayland guides, MMU notes |

Superseded: `feat/branding` (older `SLIC3R_MODIFICATIONS` About-only approach) —
replaced by the `SLIC3R_FORK_ID` + auto build-id mechanism; do not merge it.
Planned MMU work: `doc/improvements/mmu-03/04/05` (drafts, not yet implemented).
