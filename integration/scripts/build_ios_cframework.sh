#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Build the integration iOS XCFramework and UniFFI Swift bindings.

Usage:
  ./integration/scripts/build_ios_cframework.sh [options]

Options:
  --profile <release|debug>   Cargo profile to build. Default: release
  --output-dir <path>         Output directory. Default: integration/artifacts/ios-cframework
  --help                      Show this help message

Notes:
  - This script keeps `ort` offline for iOS builds by setting `ORT_SKIP_DOWNLOAD=1`.
  - iOS Rust builds point `ort` at the checked-in `onnxruntime.xcframework` via `ORT_IOS_XCFWK_PATH`.
  - The generated package is device-only and includes:
      * IntegrationFFI.xcframework
      * integration.swift
      * onnxruntime.xcframework
  - In Xcode, add both XCFrameworks to "Frameworks, Libraries, and Embedded Content",
    and add `integration.swift` to your target sources.
EOF
}

log() {
    printf '[build_ios_cframework] %s\n' "$*"
}

fail() {
    printf '[build_ios_cframework] error: %s\n' "$*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

require_target() {
    local target="$1"
    if ! rustup target list --installed | grep -qx "$target"; then
        fail "missing Rust target ${target}; run: rustup target add ${target}"
    fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INTEGRATION_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CARGO_MANIFEST_PATH="${INTEGRATION_DIR}/Cargo.toml"
ONNXRUNTIME_XCFRAMEWORK="${INTEGRATION_DIR}/onnxruntime/onnxruntime.xcframework"
MACOS_ORT_ARCHIVE="${ONNXRUNTIME_XCFRAMEWORK}/macos-arm64_x86_64/onnxruntime.framework/Versions/A/onnxruntime"

PROFILE="release"
OUTPUT_DIR="${INTEGRATION_DIR}/artifacts/ios-cframework"
DEVICE_TARGET="aarch64-apple-ios"
CRATE_NAME="integration"
XCFRAMEWORK_NAME="IntegrationFFI"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --profile)
            [[ $# -ge 2 ]] || fail "--profile requires a value"
            PROFILE="$2"
            shift 2
            ;;
        --output-dir)
            [[ $# -ge 2 ]] || fail "--output-dir requires a value"
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            fail "unknown argument: $1"
            ;;
    esac
done

case "${PROFILE}" in
    release|debug)
        ;;
    *)
        fail "unsupported profile: ${PROFILE}; expected release or debug"
        ;;
esac

require_command cargo
require_command rustup
require_command xcodebuild

[[ -f "${CARGO_MANIFEST_PATH}" ]] || fail "missing Cargo.toml at ${CARGO_MANIFEST_PATH}"
[[ -d "${ONNXRUNTIME_XCFRAMEWORK}" ]] || fail "missing onnxruntime.xcframework at ${ONNXRUNTIME_XCFRAMEWORK}"
[[ -f "${MACOS_ORT_ARCHIVE}" ]] || fail "missing macOS onnxruntime archive at ${MACOS_ORT_ARCHIVE}"

require_target "${DEVICE_TARGET}"

TARGET_DIR="${INTEGRATION_DIR}/target"
PROFILE_DIR="${TARGET_DIR}/${PROFILE}"
DEVICE_PROFILE_DIR="${TARGET_DIR}/${DEVICE_TARGET}/${PROFILE}"

TMP_DIR="${OUTPUT_DIR}/.tmp"
GENERATED_DIR="${TMP_DIR}/generated"
HEADERS_DIR="${TMP_DIR}/headers"
HOST_ORT_LIB_DIR="${TMP_DIR}/host-ort-lib"
XCFRAMEWORK_OUTPUT="${OUTPUT_DIR}/${XCFRAMEWORK_NAME}.xcframework"
SWIFT_BINDINGS_OUTPUT="${OUTPUT_DIR}/${CRATE_NAME}.swift"
ONNXRUNTIME_OUTPUT="${OUTPUT_DIR}/onnxruntime.xcframework"
ONNXRUNTIME_DEVICE_FRAMEWORK="${ONNXRUNTIME_XCFRAMEWORK}/ios-arm64/onnxruntime.framework"

mkdir -p "${OUTPUT_DIR}"
rm -rf "${TMP_DIR}" "${XCFRAMEWORK_OUTPUT}" "${SWIFT_BINDINGS_OUTPUT}" "${ONNXRUNTIME_OUTPUT}"
mkdir -p "${GENERATED_DIR}" "${HEADERS_DIR}" "${HOST_ORT_LIB_DIR}"

log "building host library for UniFFI bindings"
ln -sf "${MACOS_ORT_ARCHIVE}" "${HOST_ORT_LIB_DIR}/libonnxruntime.a"
(
    cd "${INTEGRATION_DIR}"
    ORT_LIB_LOCATION="${HOST_ORT_LIB_DIR}" \
    ORT_SKIP_DOWNLOAD=1 \
    cargo build --manifest-path "${CARGO_MANIFEST_PATH}" --lib --profile "${PROFILE}"
)

HOST_CDYLIB="${PROFILE_DIR}/lib${CRATE_NAME}.dylib"
[[ -f "${HOST_CDYLIB}" ]] || fail "expected host cdylib at ${HOST_CDYLIB}"

log "generating UniFFI Swift bindings"
(
    cd "${INTEGRATION_DIR}"
    cargo run --manifest-path "${CARGO_MANIFEST_PATH}" --features bindgen-cli --bin "${CRATE_NAME}" -- \
        generate "${HOST_CDYLIB}" \
        -l swift \
        --metadata-no-deps \
        -o "${GENERATED_DIR}"
)

[[ -f "${GENERATED_DIR}/${CRATE_NAME}.swift" ]] || fail "missing generated Swift bindings"
[[ -f "${GENERATED_DIR}/${CRATE_NAME}FFI.h" ]] || fail "missing generated FFI header"
[[ -f "${GENERATED_DIR}/${CRATE_NAME}FFI.modulemap" ]] || fail "missing generated modulemap"

cp "${GENERATED_DIR}/${CRATE_NAME}.swift" "${SWIFT_BINDINGS_OUTPUT}"
cp "${GENERATED_DIR}/${CRATE_NAME}FFI.h" "${HEADERS_DIR}/${CRATE_NAME}FFI.h"
cp "${GENERATED_DIR}/${CRATE_NAME}FFI.modulemap" "${HEADERS_DIR}/module.modulemap"

log "building iOS device library"
ORT_IOS_XCFWK_PATH="${ONNXRUNTIME_XCFRAMEWORK}" \
ORT_SKIP_DOWNLOAD=1 \
cargo build --manifest-path "${CARGO_MANIFEST_PATH}" --lib --profile "${PROFILE}" --target "${DEVICE_TARGET}"

DEVICE_STATICLIB="${DEVICE_PROFILE_DIR}/lib${CRATE_NAME}.a"
[[ -f "${DEVICE_STATICLIB}" ]] || fail "expected device static library at ${DEVICE_STATICLIB}"

XCODEBUILD_ARGS=(
    -create-xcframework
    -library "${DEVICE_STATICLIB}"
    -headers "${HEADERS_DIR}"
    -output "${XCFRAMEWORK_OUTPUT}"
)

log "creating ${XCFRAMEWORK_NAME}.xcframework"
xcodebuild "${XCODEBUILD_ARGS[@]}"

[[ -d "${ONNXRUNTIME_DEVICE_FRAMEWORK}" ]] || fail "missing iOS device onnxruntime framework at ${ONNXRUNTIME_DEVICE_FRAMEWORK}"

log "creating device-only onnxruntime.xcframework"
xcodebuild -create-xcframework \
    -framework "${ONNXRUNTIME_DEVICE_FRAMEWORK}" \
    -output "${ONNXRUNTIME_OUTPUT}"

rm -rf "${TMP_DIR}"

cat <<EOF

Artifacts written to:
  ${OUTPUT_DIR}

Files:
  ${XCFRAMEWORK_OUTPUT}
  ${SWIFT_BINDINGS_OUTPUT}
  ${ONNXRUNTIME_OUTPUT}

Next steps in Xcode:
  1. Add ${XCFRAMEWORK_NAME}.xcframework and onnxruntime.xcframework to the app target.
  2. Add ${CRATE_NAME}.swift to the app target's source files.
  3. Keep onnxruntime linked from Xcode; this script only packages the Rust side for iOS consumption.
EOF
