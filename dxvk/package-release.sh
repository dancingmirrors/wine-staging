#!/usr/bin/env bash

set -e

shopt -s extglob

print_usage() {
  echo "Usage: $0 version destdir [--no-package] [--dev-build] [--build-id] [--no-ccache]"
  echo ""
  echo "Positional arguments:"
  echo "  version     Version string for the build (e.g., 'master', 'v1.0.0')"
  echo "  destdir     Destination directory for the build output"
  echo ""
  echo "Options:"
  echo "  --no-package  Don't create a tarball package after building"
  echo "  --dev-build   Development build (implies --no-package, keeps build files)"
  echo "  --build-id    Include build ID in the output"
  echo "  --no-ccache   Disable ccache even if available"
  echo ""
  echo "Example:"
  echo "  $0 master ./build --no-package"
}

# Parse options first, then positional arguments
opt_nopackage=0
opt_devbuild=0
opt_buildid=false
opt_noccache=0
positional_args=()

while [ $# -gt 0 ]; do
  case "$1" in
  "--no-package")
    opt_nopackage=1
    shift
    ;;
  "--dev-build")
    opt_nopackage=1
    opt_devbuild=1
    shift
    ;;
  "--build-id")
    opt_buildid=true
    shift
    ;;
  "--no-ccache")
    opt_noccache=1
    shift
    ;;
  "--help"|"-h")
    print_usage
    exit 0
    ;;
  --*)
    echo "Error: Unrecognized option: $1" >&2
    echo ""
    print_usage
    exit 1
    ;;
  *)
    positional_args+=("$1")
    shift
    ;;
  esac
done

# Validate positional arguments
if [ ${#positional_args[@]} -lt 2 ]; then
  echo "Error: Missing required arguments." >&2
  echo "Expected: version destdir" >&2
  if [ ${#positional_args[@]} -eq 1 ]; then
    echo "Got: version='${positional_args[0]}' destdir=<missing>" >&2
  fi
  echo ""
  print_usage
  exit 1
fi

if [ ${#positional_args[@]} -gt 2 ]; then
  echo "Error: Too many positional arguments." >&2
  echo "Expected: version destdir" >&2
  echo "Got: ${positional_args[*]}" >&2
  echo ""
  print_usage
  exit 1
fi

DXVK_VERSION="${positional_args[0]}"
DXVK_DESTDIR="${positional_args[1]}"

# Validate that version doesn't look like an option
if [[ "$DXVK_VERSION" == -* ]]; then
  echo "Error: Version '$DXVK_VERSION' looks like an option. Did you forget to specify a version?" >&2
  echo ""
  print_usage
  exit 1
fi

# Validate destdir exists or can be created
if [ ! -d "$DXVK_DESTDIR" ]; then
  if ! mkdir -p "$DXVK_DESTDIR" 2>/dev/null; then
    echo "Error: Cannot create destination directory '$DXVK_DESTDIR'" >&2
    exit 1
  fi
fi

DXVK_SRC_DIR=$(dirname "$(readlink -f "$0")")
DXVK_BUILD_DIR=$(realpath "$DXVK_DESTDIR")"/dxvk-$DXVK_VERSION"
DXVK_ARCHIVE_PATH=$(realpath "$DXVK_DESTDIR")"/dxvk-$DXVK_VERSION.tar.gz"

if [ -e "$DXVK_BUILD_DIR" ]; then
  echo "Error: Build directory $DXVK_BUILD_DIR already exists" >&2
  echo "Remove it first or choose a different version/destdir." >&2
  exit 1
fi

# Check for ccache and set up compiler wrapper
ccache_bin=""
if [ $opt_noccache -eq 0 ] && command -v ccache &> /dev/null; then
  ccache_bin="ccache"
  echo "Using ccache for faster builds"
fi

# Generate cross-file with ccache support if available
function generate_crossfile {
  local arch="$1"
  local crossfile_in="$DXVK_SRC_DIR/build-win${arch}.txt"
  local crossfile_out="$DXVK_BUILD_DIR/build-win${arch}.txt"

  if [ -z "$ccache_bin" ]; then
    # No ccache, use original cross-file
    echo "$crossfile_in"
    return
  fi

  # Read compiler names from original cross-file
  local c_compiler cpp_compiler ar_tool strip_tool windres_tool
  c_compiler=$(grep "^c = " "$crossfile_in" | sed "s/^c = '\(.*\)'$/\1/")
  cpp_compiler=$(grep "^cpp = " "$crossfile_in" | sed "s/^cpp = '\(.*\)'$/\1/")
  ar_tool=$(grep "^ar = " "$crossfile_in" | sed "s/^ar = '\(.*\)'$/\1/")
  strip_tool=$(grep "^strip = " "$crossfile_in" | sed "s/^strip = '\(.*\)'$/\1/")
  windres_tool=$(grep "^windres = " "$crossfile_in" | sed "s/^windres = '\(.*\)'$/\1/")

  # Read [properties] and [host_machine] sections
  local properties host_machine
  properties=$(sed -n '/^\[properties\]/,/^\[/p' "$crossfile_in" | grep -v '^\[')
  host_machine=$(sed -n '/^\[host_machine\]/,/^\[/p' "$crossfile_in" | grep -v '^\[' | grep -v '^$')

  # Generate cross-file with ccache
  mkdir -p "$DXVK_BUILD_DIR"

  cat > "$crossfile_out" <<EOF
[binaries]
c = ['ccache', '$c_compiler']
cpp = ['ccache', '$cpp_compiler']
ar = '$ar_tool'
strip = '$strip_tool'
windres = '$windres_tool'

[properties]
$properties
[host_machine]
$host_machine
EOF

  echo "$crossfile_out"
}

function build_arch {
  export WINEARCH="win$1"
  export WINEPREFIX="$DXVK_BUILD_DIR/wine.$1"

  cd "$DXVK_SRC_DIR"

  opt_strip=
  if [ $opt_devbuild -eq 0 ]; then
    opt_strip=--strip
  fi

  # Get cross-file (with ccache if available)
  crossfile_path=$(generate_crossfile "$1")

  meson setup --cross-file "$crossfile_path"               \
              --buildtype "release"                         \
              --prefix "$DXVK_BUILD_DIR"                    \
              $opt_strip                                    \
              --bindir "x$1"                                \
              --libdir "x$1"                                \
              -Denable_tests=false                          \
              -Dbuild_id=$opt_buildid                       \
              "$DXVK_BUILD_DIR/build.$1"

  cd "$DXVK_BUILD_DIR/build.$1"
  ninja install

  if [ $opt_devbuild -eq 0 ]; then
    # get rid of some useless .a files
    rm "$DXVK_BUILD_DIR/x$1/"*.!(dll)
    rm -R "$DXVK_BUILD_DIR/build.$1"
  fi
}

function build_script {
  cp "$DXVK_SRC_DIR/setup_dxvk.sh" "$DXVK_BUILD_DIR/setup_dxvk.sh"
  chmod +x "$DXVK_BUILD_DIR/setup_dxvk.sh"
}

function package {
  cd "$DXVK_BUILD_DIR/.."
  tar -czf "$DXVK_ARCHIVE_PATH" "dxvk-$DXVK_VERSION"
  rm -R "dxvk-$DXVK_VERSION"
}

build_arch 64
build_arch 32
build_script

if [ $opt_nopackage -eq 0 ]; then
  package
fi
