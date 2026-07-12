# Fork Release Strategy — PrusaSlicer-Wayland

This fork carries a small set of custom changes on top of upstream
`prusa3d/PrusaSlicer`. This document describes how the branches are organised and
how to cut a new release when upstream tags a new version. It is meant for any
maintainer (human or AI agent) working on the fork.

## Goals

1. Each feature lives in its **own isolated branch** — only that feature's
   commits — so it can be reviewed or proposed upstream on its own.
2. **Documentation is separate from code**, so an upstream pull request (e.g. the
   MMU fix) never has to carry fork-specific docs.
3. Each upstream version gets a **frozen custom tag** containing all active
   features — reproducible, never rebased, never force-pushed.
4. On every new upstream tag we **rebase, re-check relevance** (is a feature still
   needed, or did upstream absorb it?), and cut a new tag.
5. Every release marks the binary as **modified** (visible in the About dialog).

## Branch model

```
upstream/master ─▶ master                (mirror only, fast-forward)

version_X.Y.Z (upstream tag)
   ├── feat/wayland          native Wayland (GTK3+EGL) + build env + CMake 4   [upstream-PR candidate]
   ├── feat/mmu-temp-fix     wipe-tower temperature sync (WipeTower.cpp/.hpp)   [upstream-PR candidate]
   ├── feat/branding         "modified build" info in the About dialog          [fork-only]
   └── feat/docs             all fork docs incl. this file and CLAUDE.md        [fork-only]

release/X.Y.Z  = version_X.Y.Z + all active feat/* (cherry-picked, disjoint)
                 + version.inc identity edit (SLIC3R_BUILD_ID + SLIC3R_MODIFICATIONS)
   └── tag vX.Y.Z-wayland    frozen "my version"
```

- **`feat/*`** are *rolling* branches: each holds only its own commits on top of
  the newest upstream release, and is rebased forward each cycle. They are
  intentionally **doc-free** (except `feat/docs`) so a PR stays clean. Because of
  that, `CLAUDE.md` and this file live only on `feat/docs` and `release/*` — do
  fork onboarding from `release/*`.
- **`release/X.Y.Z` + `vX.Y.Z-wayland`** are *frozen*: created once, never rebased.
  Their commits are copies (cherry-picks) of the `feat/*` commits — there is no
  ref link back, so upstream PRs always come from the `feat/*` branch.
- The features touch **disjoint files**, so cherry-picking them together is
  conflict-free and order-independent.
- **Shared files** (`version.inc`) are edited only on `release/*`, never on a
  `feat/*`, to avoid cherry-pick collisions.

## Cutting a release for a new upstream `version_NEW`

Enable rerere once: `git config rerere.enabled true`.

```bash
git fetch upstream --tags
git checkout master && git merge --ff-only upstream/master

# 1) Move each feature onto the new base and check whether upstream absorbed it.
for f in wayland mmu-temp-fix branding docs; do
  old=$(git rev-parse feat/$f)
  base=$(git merge-base feat/$f version_PREV)
  git rebase --empty=drop --onto version_NEW "$base" feat/$f
  # Symmetric relevance check (old patch vs new patch, both custom-only):
  git range-diff version_PREV.."$old" version_NEW..feat/$f
  #   a commit shown as dropped / empty  ⇒ upstream absorbed it ⇒ leave it out below.
done

# 2) Assemble the release (adjust the list to the features active THIS release).
git checkout -b release/NEW version_NEW
git cherry-pick version_NEW..feat/wayland version_NEW..feat/mmu-temp-fix \
                 version_NEW..feat/branding version_NEW..feat/docs

# 3) Set the version identity ON release/* ONLY (shared file):
#    version.inc:
#      set(SLIC3R_BUILD_ID     "PrusaSlicer-${SLIC3R_VERSION}+wayland.mmu.cmake4")
#      set(SLIC3R_MODIFICATIONS "Wayland · MMU temp-sync · CMake 4")
#    Do NOT touch SLIC3R_VERSION / SLIC3R_APP_NAME / SLIC3R_APP_KEY.

# 4) Currency audit (see below), build + smoke-test, then tag.
git tag -a vNEW-wayland release/NEW -m "PrusaSlicer NEW — Wayland edition (mmu-temp, cmake4)"
git push origin feat/wayland feat/mmu-temp-fix feat/branding feat/docs release/NEW vNEW-wayland
```

## Currency audit (mandatory before tagging)

Open every committed file and reconcile it with reality — no stale version
numbers, no "pending" for things now done, no CMake-3.x-only or X11-only
assumptions, complete dependency lists, no dead branch/tag references, no
contradictions between docs. Fix as a `docs: sync to X.Y.Z state` commit.

## Build environment (Ubuntu 26.04 / CMake 4)

System packages:

```
sudo apt install -y git build-essential autoconf automake libtool libtool-bin \
    cmake libglu1-mesa-dev libgtk-3-dev libdbus-1-dev libwebkit2gtk-4.1-dev \
    texinfo libhidapi-dev
```

CMake 4 removed compatibility with policy versions < 3.5 that the vendored deps
still request. The `Makefile` exports `CMAKE_POLICY_VERSION_MINIMUM=3.5` (inherited
by every child cmake) and `deps/CMakeLists.txt` appends it to `DEP_CMAKE_OPTS`;
both are part of `feat/wayland`. Build with `make` (deps once, then the app).

## Features — current status

| Feature | Branch | Upstream PR? | Notes |
|---|---|---|---|
| Native Wayland (GTK3+EGL) + build env + CMake 4 | `feat/wayland` | yes (Wayland/CMake4 parts) | 4 blockers: wxWidgets GTK3/EGL, GUI_App gtk-menu-images guard, Setup.cpp GDK_BACKEND, GLEW_EGL |
| MMU wipe-tower temperature sync | `feat/mmu-temp-fix` | yes | WipeTower.cpp/.hpp only, gated on `m_semm` |
| Modified-build info in About | `feat/branding` | no | `SLIC3R_MODIFICATIONS` macro |
| Fork documentation | `feat/docs` | no | this file, CLAUDE.md, Wayland guides, MMU notes |

Pending / not part of the current release: `test/wx3.3` (wxWidgets 3.3.2 upgrade)
— decide per cycle whether to adopt it as `feat/wx3.3` or retire it.
Planned MMU work: `doc/improvements/mmu-03/04/05` (drafts, not yet implemented).
