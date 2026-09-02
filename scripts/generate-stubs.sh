#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Generates the Ballerina gRPC stub (rental_pb.bal) for the Question 2 server
# and client from proto/rental.proto.
#
# Run this once after cloning, before `bal run` in either Question 2 package.
#
#   ./scripts/generate-stubs.sh
# ---------------------------------------------------------------------------
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROTO="$ROOT/proto/rental.proto"

command -v bal >/dev/null 2>&1 || {
    echo "Ballerina ('bal') is not on the PATH. Install Swan Lake from https://ballerina.io/downloads/"
    exit 1
}

echo "Generating stub for the server ..."
bal grpc --input "$PROTO" --output "$ROOT/question2-rental-server"

echo "Generating stub for the client ..."
bal grpc --input "$PROTO" --output "$ROOT/question2-rental-client"

echo
echo "Done. Both packages now contain rental_pb.bal:"
ls -1 "$ROOT/question2-rental-server/rental_pb.bal" "$ROOT/question2-rental-client/rental_pb.bal"
