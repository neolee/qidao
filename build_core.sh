#!/bin/bash

# Script to build Rust core and copy bindings to SwiftUI project

set -e

CORE_DIR="./qidao-core"
SWIFT_DIR="./QiDao/QiDao/Core"

echo "Building Rust core..."
cd "$CORE_DIR"
cargo build --release

echo "Generating bindings..."
cargo run --features=uniffi/cli --bin uniffi-bindgen -- generate --library target/release/libqidao_core.dylib --language swift --out-dir out

echo "Copying files to SwiftUI project..."
mkdir -p "../$SWIFT_DIR"
cp target/release/libqidao_core.a "../$SWIFT_DIR/"
cp out/qidao_core.swift "../$SWIFT_DIR/"
cp out/qidao_coreFFI.h "../$SWIFT_DIR/"
cp out/qidao_coreFFI.modulemap "../$SWIFT_DIR/"

echo "Done! Please ensure Xcode project is configured to link libqidao_core.a and include the modulemap path."
