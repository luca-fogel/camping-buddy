#!/bin/zsh
set -euo pipefail
# Compiles the actual ChatModel coordinator against deterministic doubles.
# This is a state/lifecycle test, never inference or download evidence.
repo_root="${0:A:h:h}"
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/camping-chat-flow.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
cd "$repo_root"
xcrun swiftc -parse-as-library -swift-version 6 \
  Core/ReferenceLibrary.swift Core/AnswerPolicy.swift Core/ModelCatalog.swift \
  App/ChatModel.swift DeveloperChecks/ChatModelFlowCheck.swift \
  -o "$check_dir/ChatModelFlowCheck"
"$check_dir/ChatModelFlowCheck"
