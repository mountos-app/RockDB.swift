#!/bin/bash
set -e

ROCKSDB_VERSION="v9.7.4"
SNAPPY_VERSION="1.2.2"
LZ4_VERSION="v1.10.0"
ZSTD_VERSION="v1.5.6"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
THIRD_PARTY="$PROJECT_ROOT/ThirdParty"
OUTPUT_DIR="$PROJECT_ROOT/lib"

# Parse arguments
CLEAN=false
SLIM=false
for arg in "$@"; do
  case $arg in
    --clean) CLEAN=true ;;
    --slim) SLIM=true ;;
  esac
done

if [ "$SLIM" = true ]; then
  echo "=== RocksDB Build Script (SLIM) ==="
  echo "Building WITHOUT compression libraries"
else
  echo "=== RocksDB Build Script ==="
  echo "Building WITH static compression libraries (self-contained)"
fi
echo "RocksDB Version: $ROCKSDB_VERSION"
echo "Output: $OUTPUT_DIR"
echo ""

# Check dependencies
check_dependency() {
  if ! command -v "$1" &> /dev/null; then
    echo "Error: $1 is required but not installed."
    echo "Install with: brew install $2"
    exit 1
  fi
}

check_dependency cmake cmake
check_dependency ninja ninja

mkdir -p "$THIRD_PARTY"
mkdir -p "$OUTPUT_DIR"

# Clean if requested
if [ "$CLEAN" = true ]; then
  echo "Cleaning previous builds..."
  rm -rf "$THIRD_PARTY"
  mkdir -p "$THIRD_PARTY"
fi

# =============================================================================
# Build static compression libraries (unless slim)
# =============================================================================

STATIC_LIBS_DIR="$THIRD_PARTY/static_libs"
mkdir -p "$STATIC_LIBS_DIR/lib"
mkdir -p "$STATIC_LIBS_DIR/include"

if [ "$SLIM" = false ]; then

  # -------------------------------------------------------------------------
  # Build Snappy
  # -------------------------------------------------------------------------
  SNAPPY_SRC="$THIRD_PARTY/snappy"
  if [ ! -f "$STATIC_LIBS_DIR/lib/libsnappy.a" ]; then
    echo ""
    echo "=== Building Snappy $SNAPPY_VERSION ==="

    if [ ! -d "$SNAPPY_SRC" ]; then
      git clone --depth 1 --branch "$SNAPPY_VERSION" \
        https://github.com/google/snappy.git "$SNAPPY_SRC"
    fi

    cd "$SNAPPY_SRC"
    rm -rf build_arm64 build_x86_64

    # Build arm64
    mkdir -p build_arm64 && cd build_arm64
    cmake .. -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_OSX_ARCHITECTURES=arm64 \
      -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
      -DSNAPPY_BUILD_TESTS=OFF \
      -DSNAPPY_BUILD_BENCHMARKS=OFF \
      -DBUILD_SHARED_LIBS=OFF
    ninja snappy
    cd ..

    # Build x86_64
    mkdir -p build_x86_64 && cd build_x86_64
    cmake .. -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_OSX_ARCHITECTURES=x86_64 \
      -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
      -DSNAPPY_BUILD_TESTS=OFF \
      -DSNAPPY_BUILD_BENCHMARKS=OFF \
      -DBUILD_SHARED_LIBS=OFF
    ninja snappy
    cd ..

    # Create universal binary
    lipo -create build_arm64/libsnappy.a build_x86_64/libsnappy.a \
      -output "$STATIC_LIBS_DIR/lib/libsnappy.a"
    cp snappy.h snappy-c.h snappy-sinksource.h snappy-stubs-public.h \
      "$STATIC_LIBS_DIR/include/" 2>/dev/null || true
    cp build_arm64/snappy-stubs-public.h "$STATIC_LIBS_DIR/include/" 2>/dev/null || true

    echo "Snappy built: $STATIC_LIBS_DIR/lib/libsnappy.a"
  else
    echo "Snappy already built"
  fi

  # -------------------------------------------------------------------------
  # Build LZ4
  # -------------------------------------------------------------------------
  LZ4_SRC="$THIRD_PARTY/lz4"
  if [ ! -f "$STATIC_LIBS_DIR/lib/liblz4.a" ]; then
    echo ""
    echo "=== Building LZ4 $LZ4_VERSION ==="

    if [ ! -d "$LZ4_SRC" ]; then
      git clone --depth 1 --branch "$LZ4_VERSION" \
        https://github.com/lz4/lz4.git "$LZ4_SRC"
    fi

    cd "$LZ4_SRC/build/cmake"
    rm -rf build_arm64 build_x86_64

    # Build arm64
    mkdir -p build_arm64 && cd build_arm64
    cmake .. -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_OSX_ARCHITECTURES=arm64 \
      -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
      -DLZ4_BUILD_CLI=OFF \
      -DLZ4_BUILD_LEGACY_LZ4C=OFF \
      -DBUILD_SHARED_LIBS=OFF \
      -DBUILD_STATIC_LIBS=ON
    ninja lz4_static
    cd ..

    # Build x86_64
    mkdir -p build_x86_64 && cd build_x86_64
    cmake .. -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_OSX_ARCHITECTURES=x86_64 \
      -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
      -DLZ4_BUILD_CLI=OFF \
      -DLZ4_BUILD_LEGACY_LZ4C=OFF \
      -DBUILD_SHARED_LIBS=OFF \
      -DBUILD_STATIC_LIBS=ON
    ninja lz4_static
    cd ..

    # Create universal binary
    lipo -create build_arm64/liblz4.a build_x86_64/liblz4.a \
      -output "$STATIC_LIBS_DIR/lib/liblz4.a"
    cp "$LZ4_SRC/lib/lz4.h" "$LZ4_SRC/lib/lz4hc.h" "$LZ4_SRC/lib/lz4frame.h" \
      "$STATIC_LIBS_DIR/include/"

    echo "LZ4 built: $STATIC_LIBS_DIR/lib/liblz4.a"
  else
    echo "LZ4 already built"
  fi

  # -------------------------------------------------------------------------
  # Build Zstd
  # -------------------------------------------------------------------------
  ZSTD_SRC="$THIRD_PARTY/zstd"
  if [ ! -f "$STATIC_LIBS_DIR/lib/libzstd.a" ]; then
    echo ""
    echo "=== Building Zstd $ZSTD_VERSION ==="

    if [ ! -d "$ZSTD_SRC" ]; then
      git clone --depth 1 --branch "$ZSTD_VERSION" \
        https://github.com/facebook/zstd.git "$ZSTD_SRC"
    fi

    cd "$ZSTD_SRC/build/cmake"
    rm -rf build_arm64 build_x86_64

    # Build arm64
    mkdir -p build_arm64 && cd build_arm64
    cmake .. -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_OSX_ARCHITECTURES=arm64 \
      -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
      -DZSTD_BUILD_PROGRAMS=OFF \
      -DZSTD_BUILD_TESTS=OFF \
      -DZSTD_BUILD_SHARED=OFF \
      -DZSTD_BUILD_STATIC=ON
    ninja libzstd_static
    cd ..

    # Build x86_64
    mkdir -p build_x86_64 && cd build_x86_64
    cmake .. -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_OSX_ARCHITECTURES=x86_64 \
      -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
      -DZSTD_BUILD_PROGRAMS=OFF \
      -DZSTD_BUILD_TESTS=OFF \
      -DZSTD_BUILD_SHARED=OFF \
      -DZSTD_BUILD_STATIC=ON
    ninja libzstd_static
    cd ..

    # Create universal binary
    lipo -create build_arm64/lib/libzstd.a build_x86_64/lib/libzstd.a \
      -output "$STATIC_LIBS_DIR/lib/libzstd.a"
    cp "$ZSTD_SRC/lib/zstd.h" "$ZSTD_SRC/lib/zstd_errors.h" \
      "$STATIC_LIBS_DIR/include/"

    echo "Zstd built: $STATIC_LIBS_DIR/lib/libzstd.a"
  else
    echo "Zstd already built"
  fi

fi  # End of compression libs build

# =============================================================================
# Build RocksDB
# =============================================================================

ROCKSDB_SRC="$THIRD_PARTY/rocksdb"

if [ ! -d "$ROCKSDB_SRC" ]; then
  echo ""
  echo "Cloning RocksDB $ROCKSDB_VERSION..."
  git clone --depth 1 --branch "$ROCKSDB_VERSION" \
    https://github.com/facebook/rocksdb.git "$ROCKSDB_SRC"
fi

cd "$ROCKSDB_SRC"

# Clean RocksDB builds if requested
if [ "$CLEAN" = true ]; then
  rm -rf build_arm64 build_x86_64
fi

# Set compression options
if [ "$SLIM" = true ]; then
  COMPRESSION_OPTS=(
    -DWITH_SNAPPY=OFF
    -DWITH_LZ4=OFF
    -DWITH_ZSTD=OFF
    -DWITH_BZ2=OFF
    -DWITH_ZLIB=OFF
    -DWITH_IOSTATS_CONTEXT=OFF
    -DWITH_PERF_CONTEXT=OFF
    -DWITH_TRACE_TOOLS=OFF
    -DWITH_DYNAMIC_EXTENSION=OFF
    -DCMAKE_CXX_FLAGS_RELEASE="-O3 -DNDEBUG -ffunction-sections -fdata-sections"
    -DCMAKE_C_FLAGS_RELEASE="-O3 -DNDEBUG -ffunction-sections -fdata-sections"
  )
else
  COMPRESSION_OPTS=(
    -DWITH_SNAPPY=ON
    -DWITH_LZ4=ON
    -DWITH_ZSTD=ON
    -DWITH_BZ2=OFF
    -DSNAPPY_ROOT_DIR="$STATIC_LIBS_DIR"
    -DLZ4_ROOT_DIR="$STATIC_LIBS_DIR"
    -DZSTD_ROOT_DIR="$STATIC_LIBS_DIR"
    -DCMAKE_PREFIX_PATH="$STATIC_LIBS_DIR"
  )
fi

# Common CMake options
CMAKE_COMMON_OPTS=(
  -G Ninja
  -DCMAKE_BUILD_TYPE=Release
  -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0
  -DROCKSDB_BUILD_SHARED=OFF
  -DWITH_TESTS=OFF
  -DWITH_TOOLS=OFF
  -DWITH_BENCHMARK_TOOLS=OFF
  -DWITH_CORE_TOOLS=OFF
  "${COMPRESSION_OPTS[@]}"
  -DWITH_GFLAGS=OFF
  -DUSE_RTTI=ON
  -DPORTABLE=OFF
  -DFAIL_ON_WARNINGS=OFF
  -DCMAKE_CXX_STANDARD=20
)

# Build for arm64
echo ""
echo "=== Building RocksDB for arm64 ==="
mkdir -p build_arm64 && cd build_arm64

cmake .. \
  "${CMAKE_COMMON_OPTS[@]}" \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_C_FLAGS="-march=armv8-a+crc+crypto" \
  -DCMAKE_CXX_FLAGS="-march=armv8-a+crc+crypto"

ninja rocksdb

cd ..

# Build for x86_64
echo ""
echo "=== Building RocksDB for x86_64 ==="
mkdir -p build_x86_64 && cd build_x86_64

cmake .. \
  "${CMAKE_COMMON_OPTS[@]}" \
  -DCMAKE_OSX_ARCHITECTURES=x86_64 \
  -DPORTABLE=ON

ninja rocksdb

cd ..

# =============================================================================
# Create output
# =============================================================================

echo ""
echo "=== Creating universal binary ==="

mkdir -p "$OUTPUT_DIR/include"

lipo -create \
  build_arm64/librocksdb.a \
  build_x86_64/librocksdb.a \
  -output "$OUTPUT_DIR/librocksdb.a"

cp -r include/rocksdb "$OUTPUT_DIR/include/"

# Copy static compression libs if not slim
if [ "$SLIM" = false ]; then
  cp "$STATIC_LIBS_DIR/lib/libsnappy.a" "$OUTPUT_DIR/"
  cp "$STATIC_LIBS_DIR/lib/liblz4.a" "$OUTPUT_DIR/"
  cp "$STATIC_LIBS_DIR/lib/libzstd.a" "$OUTPUT_DIR/"
fi

echo ""
echo "=== Build Complete ==="
echo "Output: $OUTPUT_DIR/"
echo ""
ls -lh "$OUTPUT_DIR"/*.a

echo ""
echo "Library architectures:"
lipo -info "$OUTPUT_DIR/librocksdb.a"

if [ "$SLIM" = true ]; then
  echo ""
  echo "SLIM BUILD - No compression support"
  echo "Remove from Package.swift:"
  echo '  .linkedLibrary("lz4"),'
  echo '  .linkedLibrary("zstd"),'
  echo '  .linkedLibrary("snappy"),'
else
  echo ""
  echo "FULL BUILD - Static compression libs included"
  echo "Package is self-contained, no brew dependencies needed!"
fi
