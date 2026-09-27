#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_classes="$(mktemp -d)"
trap 'rm -rf "$test_classes"' EXIT
javac --release 8 -cp "$project_dir/android/app/libs/openrq-3.3.2.jar" -d "$test_classes" \
  "$project_dir/android/app/src/main/java/com/example/qrcodeapp/RaptorTransferCodec.java" \
  "$project_dir/test/native/RaptorTransferCodecTest.java"
java -cp "$test_classes:$project_dir/android/app/libs/openrq-3.3.2.jar" com.example.qrcodeapp.RaptorTransferCodecTest
