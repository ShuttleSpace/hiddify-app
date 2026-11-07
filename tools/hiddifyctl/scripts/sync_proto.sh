#!/usr/bin/env bash
# Sync the hiddify-core gRPC client into this tool as a self-contained snapshot.
#
# Why a snapshot (not importing hiddify-core): importing the full hiddify-core
# module would pull in sing-box and its nested submodules, making the build huge
# and fragile. The Core gRPC client we need only depends on grpc + protobuf, so we
# keep just the generated Go stubs.
#
# This script is idempotent. It prefers regenerating from .proto with protoc; if
# protoc is unavailable it copies the already-generated .pb.go files from the
# hiddify-core submodule and rewrites their import path to this module.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/../../hiddify-core/v2"          # hiddify-core submodule (v2)
NEW_MOD="github.com/hiddify/hiddify-app/tools/hiddifyctl/internal/grpc"

HSRC="$SRC/hcommon/common.proto"
CSRC="$SRC/hcore/hcore.proto"
SSRC="$SRC/hcore/hcore_service.proto"

HOUT="$ROOT/internal/grpc/hcommon"
COUT="$ROOT/internal/grpc/hcore"
mkdir -p "$HOUT" "$COUT"

if command -v protoc >/dev/null 2>&1 && command -v protoc-gen-go >/dev/null 2>&1 && command -v protoc-gen-go-grpc >/dev/null 2>&1; then
  echo ">> regenerating with protoc"
  protoc \
    --proto_path="$SRC" \
    --go_out="$ROOT/internal/grpc" --go_opt=module="$NEW_MOD" \
    --go-grpc_out="$ROOT/internal/grpc" --go-grpc_opt=module="$NEW_MOD" \
    "$HSRC" "$CSRC" "$SSRC"
else
  echo ">> protoc not found; copying pre-generated stubs from hiddify-core and rewriting imports"
  cp "$SRC/hcommon/common.pb.go"        "$HOUT/common.pb.go"
  cp "$SRC/hcore/hcore.pb.go"           "$COUT/hcore.pb.go"
  cp "$SRC/hcore/hcore_service.pb.go"   "$COUT/hcore_service.pb.go"
  cp "$SRC/hcore/hcore_service_grpc.pb.go" "$COUT/hcore_service_grpc.pb.go"
  # rewrite the hiddify-core hcommon import to our module path inside the hcore files
  for f in "$COUT"/*.go; do
    sed -i '' "s#github.com/hiddify/hiddify-core/v2/hcommon#$NEW_MOD/hcommon#g" "$f"
  done
fi

echo ">> done: gRPC client snapshot in $ROOT/internal/grpc"
