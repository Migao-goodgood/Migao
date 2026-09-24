#!/bin/zsh
set -euo pipefail

test_directory=${0:A:h}
ios_directory=${test_directory:h}
test_output=$(mktemp -d /private/tmp/migao-diet-capture-tests.XXXXXX)
trap 'rm -f "$test_output/DietCaptureFlowTests"; rmdir "$test_output"' EXIT

xcrun swiftc \
  -D DEBUG \
  -parse-as-library \
  -module-cache-path /private/tmp/migao-diet-capture-test-module-cache \
  "$ios_directory/ZheBuDeShouSi/Features/Diet/Domain/DietModels.swift" \
  "$ios_directory/ZheBuDeShouSi/Features/Diet/Application/DietStore.swift" \
  "$ios_directory/ZheBuDeShouSi/Features/Diet/Application/DietCaptureCoordinator.swift" \
  "$ios_directory/ZheBuDeShouSi/Features/Diet/Infrastructure/DietPhotoAnalysisService.swift" \
  "$ios_directory/ZheBuDeShouSi/Features/Diet/Infrastructure/DietPhotoPreparation.swift" \
  "$test_directory/DietCaptureFlowTests.swift" \
  -o "$test_output/DietCaptureFlowTests"
"$test_output/DietCaptureFlowTests"
