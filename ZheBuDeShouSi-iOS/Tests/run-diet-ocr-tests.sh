#!/bin/zsh
set -euo pipefail

test_directory=${0:A:h}
ios_directory=${test_directory:h}
test_output=$(mktemp -d /private/tmp/migao-diet-ocr-tests.XXXXXX)
trap 'rm -f "$test_output/DietLocalOCRTests"; rmdir "$test_output"' EXIT

xcrun swiftc \
  -parse-as-library \
  -module-cache-path /private/tmp/migao-diet-ocr-test-module-cache \
  "$ios_directory/ZheBuDeShouSi/Features/Diet/Domain/DietModels.swift" \
  "$ios_directory/ZheBuDeShouSi/Features/Diet/Infrastructure/DietPhotoAnalysisService.swift" \
  "$test_directory/DietLocalOCRTests.swift" \
  -o "$test_output/DietLocalOCRTests"
"$test_output/DietLocalOCRTests"
