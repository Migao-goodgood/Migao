#!/bin/zsh
set -euo pipefail

test_directory=${0:A:h}
ios_directory=${test_directory:h}
test_output=$(mktemp -d /private/tmp/migao-diet-ai-tests.XXXXXX)
trap 'rm -f "$test_output/DietAIAnalysisTests" "$test_output/DietAIAnalysisReleaseTests"; rmdir "$test_output"' EXIT

for configuration in debug release; do
  flags=()
  if [[ "$configuration" == debug ]]; then
    flags=(-D DEBUG)
  fi
  xcrun swiftc "${flags[@]}" \
    -module-cache-path /private/tmp/migao-diet-test-module-cache \
    "$ios_directory/ZheBuDeShouSi/Features/Diet/Domain/DietModels.swift" \
    "$ios_directory/ZheBuDeShouSi/Features/Diet/Application/DietStore.swift" \
    "$ios_directory/ZheBuDeShouSi/Features/Diet/Infrastructure/DietAIAnalysisService.swift" \
    "$test_directory/DietAIAnalysisTests.swift" \
    -o "$test_output/DietAIAnalysisTests"
  "$test_output/DietAIAnalysisTests"
done
