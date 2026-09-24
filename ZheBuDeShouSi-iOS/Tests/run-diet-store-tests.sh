#!/bin/zsh
set -euo pipefail

test_directory=${0:A:h}
ios_directory=${test_directory:h}
test_output=$(mktemp -d /private/tmp/migao-diet-tests.XXXXXX)
trap 'rm -f "$test_output/DietStoreReliabilityTests"; rmdir "$test_output"' EXIT

xcrun swiftc \
  -module-cache-path /private/tmp/migao-diet-test-module-cache \
  "$ios_directory/ZheBuDeShouSi/Features/Diet/Domain/DietModels.swift" \
  "$ios_directory/ZheBuDeShouSi/Features/Diet/Application/DietStore.swift" \
  "$test_directory/DietStoreReliabilityTests.swift" \
  -o "$test_output/DietStoreReliabilityTests"
"$test_output/DietStoreReliabilityTests"
