#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
xcodebuild -project App/LocalMacCleaner.xcodeproj -scheme LocalMacCleaner -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath "${LMC_DERIVED_DATA:-.local/build}" CODE_SIGN_IDENTITY=- ARCHS=arm64 build
