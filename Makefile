# PrusaSlicer — Wayland build (GTK3 + EGL)
#
# Usage:
#   make              # build deps + PrusaSlicer
#   make deps         # build static dependencies (once)
#   make prusa        # configure + compile PrusaSlicer
#   make run          # launch the slicer
#   make test         # run tests
#   make clean-deps   # remove deps build dir
#   make clean-prusa  # remove PrusaSlicer build dir
#   make clean-all    # remove both build dirs
#
# Override parallelism:  make JOBS=8

# Use bash with pipefail so logged commands propagate failures through `tee`.
SHELL       := /bin/bash
.SHELLFLAGS := -eo pipefail -c

# CMake 4.0 (Ubuntu 26.04) removed compatibility with policies < 3.5, which the
# vendored deps (Blosc, Boost, OCCT, ...) still request. Exporting this restores
# the old floor for every cmake invocation, including the ExternalProject child
# configures. Harmless on CMake 3.x. Verified building all 25 deps on CMake 4.2.
export CMAKE_POLICY_VERSION_MINIMUM := 3.5

JOBS      ?= $(shell nproc 2>/dev/null || echo 4)
BUILD_DIR := build-ubuntu
DEPS_DIR  := deps/build-ubuntu
DESTDIR   := $(CURDIR)/$(DEPS_DIR)/destdir/usr/local
LOG_DIR   := build-logs
DEPS_LOG  := $(LOG_DIR)/deps.log
PRUSA_LOG := $(LOG_DIR)/prusa.log

.PHONY: all deps prusa configure build run test install \
        clean-deps clean-prusa clean-logs clean-all

all: deps prusa

# --- Dependencies (static, GTK3) -------------------------------------------

deps: $(DEPS_DIR)/deps.stamp

$(DEPS_DIR)/deps.stamp:
	@mkdir -p $(DEPS_DIR) $(LOG_DIR)
	@echo ">>> Logging deps build to $(DEPS_LOG)"
	cmake -B $(DEPS_DIR) -S deps -DDEP_WX_GTK3=ON 2>&1 | tee $(DEPS_LOG)
	$(MAKE) -C $(DEPS_DIR) -j1 2>&1 | tee -a $(DEPS_LOG)
	@touch $@

# --- PrusaSlicer configure + build -----------------------------------------

prusa: configure build

configure: $(BUILD_DIR)/CMakeCache.txt

$(BUILD_DIR)/CMakeCache.txt: $(DEPS_DIR)/deps.stamp
	@mkdir -p $(LOG_DIR)
	@echo ">>> Logging configure to $(PRUSA_LOG)"
	cmake -B $(BUILD_DIR) -S . \
		-DCMAKE_BUILD_TYPE=Release \
		-DSLIC3R_STATIC=1 \
		-DSLIC3R_GTK=3 \
		-DSLIC3R_PCH=ON \
		-DCMAKE_PREFIX_PATH="$(DESTDIR)" 2>&1 | tee $(PRUSA_LOG)

build: $(BUILD_DIR)/CMakeCache.txt
	@mkdir -p $(LOG_DIR)
	@echo ">>> Logging build to $(PRUSA_LOG)"
	cmake --build $(BUILD_DIR) -j$(JOBS) 2>&1 | tee -a $(PRUSA_LOG)

# --- Run --------------------------------------------------------------------

run: build
	./$(BUILD_DIR)/src/prusa-slicer

# --- Tests ------------------------------------------------------------------

test: build
	cd $(BUILD_DIR) && ctest --output-on-failure

# --- Install (FHS layout) --------------------------------------------------

install: build
	cmake --build $(BUILD_DIR) --target install

# --- Clean ------------------------------------------------------------------

clean-prusa:
	$(RM) -r $(BUILD_DIR)

clean-deps:
	$(RM) -r $(DEPS_DIR)

clean-logs:
	$(RM) -r $(LOG_DIR)

clean-all: clean-prusa clean-deps clean-logs
