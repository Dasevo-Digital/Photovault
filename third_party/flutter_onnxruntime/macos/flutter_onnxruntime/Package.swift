// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "flutter_onnxruntime",
  platforms: [
    .macOS("14.0")
  ],
  products: [
    // The Flutter tooling requires the library product name to be the
    // dasherized plugin name (it generates a dependency on "flutter-onnxruntime").
    .library(name: "flutter-onnxruntime", targets: ["flutter_onnxruntime"])
  ],
  // No package dependency: the ONNX Runtime Objective-C bindings and the binary
  // live in this package (see ONNXRUNTIME-BINDINGS.md). The onnxruntime SPM
  // package (masicai fork, tag 1.28.0) also declares an onnxruntime_extensions
  // binary on download.onnxruntime.ai, which is no longer reachable; SwiftPM
  // downloads every binary target of a dependency, so resolving failed on any
  // machine without a cached copy.
  dependencies: [],
  targets: [
    // Swift target. `import FlutterMacOS` resolves implicitly through the
    // Flutter tooling; do NOT declare a Flutter framework dependency here
    // (the FlutterFramework local package only exists on Flutter master).
    .target(
      name: "flutter_onnxruntime",
      dependencies: [
        "flutter_onnxruntime_objc",
        "OnnxRuntimeBindings"
      ],
      resources: [
        .process("PrivacyInfo.xcprivacy")
      ]
    ),
    // ObjC++ target: SwiftPM does not support mixed-language targets, so the
    // float16 C++ bridge and the messenger workaround live in their own module.
    .target(
      name: "flutter_onnxruntime_objc",
      dependencies: [
        "OnnxRuntimeBindings"
      ],
      cxxSettings: [
        // Make the vendored cxx_api.h resolve the ORT C/C++ API headers from
        // the binary xcframework ("onnxruntime/..." prefixed paths).
        .define("SPM_BUILD"),
        .headerSearchPath("vendor")
      ]
    ),
    // ONNX Runtime Objective-C bindings, copied unchanged from the masicai fork
    // of onnxruntime-swift-package-manager, tag 1.28.0 (objectivec/, without
    // tests, docs and training). Module name and settings as in its manifest,
    // so `import OnnxRuntimeBindings` and the vendored headers stay valid.
    .target(
      name: "OnnxRuntimeBindings",
      dependencies: ["onnxruntime"],
      cxxSettings: [
        .define("SPM_BUILD")
      ]
    ),
    // The same binary the fork pins: Microsoft's pod archive 1.28.0 repackaged
    // as a library-format xcframework (App Store accepts it, issue #71).
    // SwiftPM verifies the checksum.
    .binaryTarget(
      name: "onnxruntime",
      url: "https://github.com/masicai/onnxruntime-swift-package-manager/releases/download/1.28.0/onnxruntime-libs-1.28.0.zip",
      checksum: "7e031979787f2da0f3ff45d18431db93c4443033020b210413b287a855870c3c"
    )
  ],
  cxxLanguageStandard: .cxx17
)
