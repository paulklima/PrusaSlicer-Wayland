# CLAUDE.md

Guidance for Claude Code (and any coding agent) working in this repository.

## What this repository is

PrusaSlicer — a C++ slicer for FFF and mSLA 3D printers — **forked from
`prusa3d/PrusaSlicer`**. This fork adds, on top of upstream **2.9.6**:

| Change | Where | Upstream-PR candidate? |
|--------|-------|------------------------|
| Native **Wayland** support (GTK3 + EGL) | `src/slic3r/GUI/*`, `deps/+wxWidgets` | yes (Wayland/CMake parts) |
| **wxWidgets 3.3.3** upgrade + API compat | `deps/+wxWidgets`, GUI TUs | yes |
| **CMake 4 / Ubuntu 26.04** build support | `Makefile`, `deps/`, `CMakeLists.txt` | yes |
| GCC 15 **warning cleanup** + `PrintConfig` uninit fix | `src/libslic3r`, `src/slic3r` | yes (PrintConfig) |
| **MMU** hybrid toolchange temperature sync (M104 early + M109 barrier) | `src/libslic3r/GCode/WipeTower.*` | yes |
| **Fork identity** in About / System Info dialogs | `version.inc`, `AboutDialog`, `SysInfoDialog` | no (fork-only) |

The current frozen release is tag **`v2.9.6-wayland-wx3.3.3`**. For the branch
model and how to cut a release, read **`doc/FORK-RELEASE-STRATEGY.md`**.

## Build

Two stages: static dependencies (`deps/`) first, then the app. **The dependency
destdir is NOT relocatable** — wxWidgets and other deps bake their absolute
install path into pkg-config/CMake config files. Moving the tree (or building the
same tree under a different mount path) breaks the app configure with
`wx/version.h not found`; rebuild the deps if that happens.

### Canonical path — the top-level `Makefile`

```bash
make            # deps (once) into deps/build-ubuntu, then app into build-ubuntu
make run        # ./build-ubuntu/src/prusa-slicer
make test       # ctest
make JOBS=8     # override parallelism
```

The `Makefile` exports `CMAKE_POLICY_VERSION_MINIMUM=3.5` for every cmake
invocation — required on **Ubuntu 26.04 (CMake 4.x)**, which dropped compatibility
with the `< 3.5` policy versions the vendored deps still request. Build logs go to
`build-logs/`.

### Manual (what `make` wraps)

```bash
cmake -B deps/build-ubuntu -S deps -DDEP_WX_GTK3=ON
make -C deps/build-ubuntu -j$(nproc)
cmake -B build-ubuntu -S . -DSLIC3R_STATIC=1 -DSLIC3R_GTK=3 -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_PREFIX_PATH="$PWD/deps/build-ubuntu/destdir/usr/local"
cmake --build build-ubuntu -j$(nproc)
```

Key flags: `SLIC3R_GTK=2|3` (must match how wx was built — this fork is 3),
`SLIC3R_STATIC`, `SLIC3R_GUI=no` (console-only), `SLIC3R_ASAN=ON`,
`CMAKE_BUILD_TYPE=Debug` (full assert coverage for tests), `SLIC3R_FHS=1`
(FHS install layout).

### System packages (Ubuntu / Debian)

```
git build-essential autoconf automake libtool libtool-bin cmake \
libglu1-mesa-dev libgl1-mesa-dev libegl1-mesa-dev libgtk-3-dev libdbus-1-dev \
libwebkit2gtk-4.1-dev libwayland-dev wayland-protocols libxkbcommon-dev \
texinfo libhidapi-dev
```

- `automake`/`libtool`/`libtool-bin` — needed by the autotools deps (GMP/MPFR);
  without them the deps build fails at `libtoolize`.
- `libhidapi-dev` — required since upstream 2.9.5, or the app configure fails with
  `Package 'hidapi-libusb' not found`.
- The EGL/Wayland/xkbcommon packages are the extras beyond a stock X11 build.

Full Linux/Wayland walkthrough: **`doc/How to build - Linux Wayland.md`**.

## Fork identity (version strings)

Version macros are **compile-time** (`version.inc` → `configure_file` →
`libslic3r_version.h`), not runtime resources — changing them needs a rebuild, not
a resource update.

- `SLIC3R_FORK_ID` (`version.inc`) — human label shown in About / System Info.
- `SLIC3R_BUILD_ID` — when still the `+UNKNOWN` placeholder, `CMakeLists.txt`
  auto-derives it from `git describe --tags --always --dirty` at **configure**
  time, so every tagged build self-identifies (e.g.
  `PrusaSlicer-v2.9.6-wayland-wx3.3.3`). Reconfigure to pick up a new tag.

## Tests

Catch2-based; build `-DCMAKE_BUILD_TYPE=Debug` to exercise asserts.

```bash
cmake --build build-ubuntu --target test    # or: cd build-ubuntu && ctest
./build-ubuntu/tests/fff_print/fff_print_tests "[some_tag]"
```

Test subdirs mirror the source libs: `tests/{libslic3r,fff_print,sla_print,arrange,slic3rutils,thumbnails}`.

## Architecture

Strict one-directional layering:

1. **`src/libslic3r/`** — pure slicing core, no GUI/wx. Models → G-code (FFF) or
   PNG layers (mSLA). Print logic, infill, supports, gcode emission, print config.
2. **`src/slic3r/`** — wxWidgets GUI over `libslic3r` (`GUI/`: windows, dialogs,
   `wxGLCanvas`/OpenGL 3D view, presets, webkit2gtk WebView integrations).
3. **`src/CLI/`** — thin CLI over `libslic3r`. Entry `PrusaSlicer.cpp`;
   `Setup.cpp` handles Linux WebKit/GTK env.

Supporting: `libvgcode/` (gcode preview), `clipper/` (vendored), `slic3r-arrange*`
(nesting), `occt_wrapper/` (STEP import), `platform/`. Dependencies are built by
`deps/+<name>/<name>.cmake`; the wx dep pulls `github.com/prusa3d/wxWidgets` — **the
repo to retarget when bumping wx**.

## Conventions

- Raw GTK APIs are guarded with `__WXGTK__` / `__WXGTK2__` / `__WXGTK3__`; any new
  raw GTK call must pick the right guard.
- HiDPI uses `wxBitmapBundle`, `wxDisplay::GetScaleFactor()`,
  `GetContentScaleFactor()`, `wxDPIChangedEvent` — don't reintroduce per-pixel
  bitmap paths.
- The `#undef Convex` in `GLCanvas3D.cpp` is an intentional X11 header-collision
  guard — leave it.
- Single-instance detection is D-Bus (`InstanceCheck.cpp`), Wayland-compatible —
  don't replace with X11 atoms.
- Commit style: `type: summary` (`feat:`, `build:`, `docs:`, `Fix …`). Keep each
  fork feature to its own branch and disjoint files where possible (see the
  release strategy doc).

## Sandbox / shared-mount caveat (agents)

If you build in a sandbox that mounts this tree at a different path than the host
(e.g. host `/home/paul/...`, sandbox `/home/nhp/project`), do **not** rewrite the
baked deps paths to make an in-sandbox build work — the deps destdir is shared, so
that corrupts the host build (`wx/version.h not found`). Either build on the host,
or rebuild deps in the sandbox at its own path (expensive). Version strings and
warnings can be reasoned about without a full link.
