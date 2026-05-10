# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

PrusaSlicer — C++ slicer for FFF and mSLA 3D printers. This tree is a fork; the immediate goal is native **Wayland support on Linux**, which requires upgrading wxWidgets (GTK2 → GTK3, EGL on). See `doc/wxWidgets-Wayland-Migration-Linux.md` for the full migration plan.

## Build

Two-stage build: static dependencies first (`deps/`), then the app. The dependency destdir is **not relocatable** — wxWidgets hardcodes its install path.

CMake presets are defined in `CMakePresets.json`:

- `default` — static deps, GTK3, builds into `build-default/`
- `no-occt` — same, no STEP file support
- `shareddeps` — dynamic linking against system libs

Typical Linux build (matching the `default` preset, and the target config for the Wayland work):

```bash
# 1. Build deps (once; GTK3 is required for Wayland)
cd deps && mkdir -p build && cd build
cmake .. -DDEP_WX_GTK3=ON
make -j$(nproc)
cd ../..

# 2. Build PrusaSlicer
cmake --preset default          # or: mkdir build && cd build && cmake .. -DSLIC3R_STATIC=1 -DSLIC3R_GTK=3 -DCMAKE_PREFIX_PATH=$PWD/../deps/build/destdir/usr/local
cmake --build build-default -j$(nproc)
./build-default/src/prusa-slicer
```

Key CMake flags: `SLIC3R_GTK=2|3` (must match wx), `SLIC3R_STATIC`, `SLIC3R_GUI=no` (console-only), `SLIC3R_ASAN=ON`, `CMAKE_BUILD_TYPE=Debug` (required for full assert coverage in tests), `SLIC3R_FHS=1` (FHS install layout, hardcodes `share/slic3r-prusa3d`).

Ubuntu 24.04 / Debian 12 system packages: `git build-essential autoconf cmake libglu1-mesa-dev libgtk-3-dev libdbus-1-dev libwebkit2gtk-4.1-dev texinfo`.

## Tests

Catch2-based. Build with `-DCMAKE_BUILD_TYPE=Debug` to exercise asserts.

```bash
cmake --build build-default --target test    # or: cd build-default && ctest
# Individual binaries:
./build-default/tests/fff_print/fff_print_tests
./build-default/tests/libslic3r/libslic3r_tests
./build-default/tests/sla_print/sla_print_tests
# Filter by Catch2 tag/name:
./build-default/tests/fff_print/fff_print_tests "[some_tag]"
```

Test subdirs mirror the source libraries: `tests/{libslic3r,fff_print,sla_print,arrange,slic3rutils,thumbnails}`.

## Architecture

Three layers, separated by strict dependency direction:

1. **`src/libslic3r/`** — pure slicing core. No GUI, no wx. Can be built and used standalone. Takes 3D models (STL/OBJ/AMF/3MF) → G-code for FFF, or PNG layers for mSLA. This is where print logic, infill, supports, gcode emission, and print config live.
2. **`src/slic3r/`** — wxWidgets GUI wrapping `libslic3r`. Contains `GUI/` (main windows, dialogs, 3D view via `wxGLCanvas`/OpenGL, preset management, WebView-based integrations via webkit2gtk on Linux).
3. **`src/CLI/`** — thin CLI wrapper over `libslic3r`. Entry point `PrusaSlicer.cpp`. `Setup.cpp` handles Linux-specific env vars for WebKit/GTK.

Supporting libraries under `src/`:

- `libvgcode/` — G-code visualization for the GUI preview.
- `clipper/` — vendored polygon clipping.
- `libseqarrange/`, `slic3r-arrange/`, `slic3r-arrange-wrapper/` — plate arrangement / nesting.
- `occt_wrapper/` — OpenCASCADE wrapper for STEP import (toggled by `SLIC3R_ENABLE_FORMAT_STEP`).
- `platform/` — small platform abstractions.

Dependencies are built by `deps/+<name>/<name>.cmake` scripts (e.g. `deps/+wxWidgets/wxWidgets.cmake`, `deps/+GMP/GMP.cmake`). The wxWidgets dep pulls `github.com/prusa3d/wxWidgets` with a macOS-only patch applied — **this is the fork to retarget when upgrading wx**.

## Wayland migration notes (active work)

The Wayland goal is gated by four small changes documented in `doc/wxWidgets-Wayland-Migration-Linux.md`. Critical files:

- `deps/+wxWidgets/wxWidgets.cmake` — flip `DEP_WX_GTK3` default ON, set `wxUSE_GLCANVAS_EGL=ON`, bump wx URL/hash.
- `src/slic3r/GUI/GUI_App.cpp` — the `gtk_settings_get_default()` / `"gtk-menu-images"` call (around line 1368) must be guarded with `#ifdef __WXGTK2__` because GTK 3.10+ removed that property.
- `src/CLI/Setup.cpp` — upstream actively forces `setenv("GDK_BACKEND", "x11", ...)` (around line 218); the Wayland patch comments this out so GTK3 can auto-detect Wayland. Keep the two `WEBKIT_DISABLE_*` env vars for now.

An earlier EGL attempt lives on `origin/tm_wxEGL_GOOD` (8 ahead, 7150 behind master) — do **not** try to rebase it; redo the changes on `master` as a small patch.

## Conventions

- GUI code using raw GTK APIs is guarded with `__WXGTK__` / `__WXGTK2__` / `__WXGTK3__`. Any new raw GTK call must pick the right guard (see the table in the Wayland doc).
- HiDPI code uses `wxBitmapBundle`, `wxDisplay::GetScaleFactor()`, `GetContentScaleFactor()`, and `wxDPIChangedEvent` — keep to these, don't reintroduce per-pixel bitmap paths.
- The `#undef Convex` guard in `src/slic3r/GUI/GLCanvas3D.cpp` is intentional (X11 header collision) — leave it even if X11 headers are no longer pulled in; it is harmless.
- Single-instance detection uses D-Bus (`InstanceCheck.cpp`), not X11 atoms — Wayland-compatible, don't replace with X-specific mechanisms.
