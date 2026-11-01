#!/bin/bash
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo"
mkdir -p build/native build/module-cache
xcrun swiftc -O -swift-version 5 -parse-as-library Sources/Shared/WallpaperPresentation.swift Sources/Shared/WallpaperRequest.swift Tests/PresentationTests.swift -o build/native/test-presentation
build/native/test-presentation
xcrun swiftc -O -swift-version 5 -parse-as-library Sources/Shared/WallpaperPresentation.swift Sources/Shared/PatternSimulation.swift Tests/PatternTests.swift -o build/native/test-pattern
build/native/test-pattern
common=(-O -swift-version 5 -parse-as-library -module-cache-path build/module-cache)
xcrun swiftc "${common[@]}" Sources/Shared/MotionClock.swift Tests/MotionTests.swift \
  -o build/native/test-motion
build/native/test-motion
xcrun swiftc "${common[@]}" Sources/Shared/ShaderLibrary.swift Sources/Shared/WallpaperPresentation.swift Sources/App/WallpaperSelection.swift \
  Tests/SelectionTests.swift -o build/native/test-selection -framework AppKit
build/native/test-selection
xcrun swiftc "${common[@]}" Sources/Shared/*.swift Tests/ResolutionTests.swift \
  -o build/native/test-resolution -framework AppKit -framework Metal -framework AVFoundation
build/native/test-resolution Resources
xcrun swiftc "${common[@]}" Sources/Shared/*.swift Tests/RendererLifecycleTests.swift \
  -o build/native/test-lifecycle -framework AppKit -framework Metal -framework AVFoundation
build/native/test-lifecycle Resources
xcrun swiftc "${common[@]}" Sources/Shared/*.swift Tests/DaylightTests.swift \
  -o build/native/test-daylight -framework AppKit -framework Metal -framework AVFoundation
build/native/test-daylight Resources
xcrun swiftc "${common[@]}" Sources/Shared/*.swift Tests/PresentationRenderTests.swift \
  -o build/native/test-presentation-render -framework AppKit -framework Metal -framework AVFoundation
build/native/test-presentation-render Resources
