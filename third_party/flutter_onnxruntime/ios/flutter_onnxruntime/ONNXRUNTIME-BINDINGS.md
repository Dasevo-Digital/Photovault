# ONNX Runtime Objective-C bindings

`Sources/OnnxRuntimeBindings/` is a copy of `objectivec/` from
https://github.com/masicai/onnxruntime-swift-package-manager, tag `1.28.0`
(commit `3fb68950a5967c8c120f9f99a1a850a43985a4c9`). The files are unchanged;
left out are, as in that package's manifest, `ReadMe.md`, `format_objc.sh`,
`test/`, `docs/` and the training sources (`ort_checkpoint*`,
`ort_training_session*`, `include/onnxruntime_training.h`).
License: MIT, Microsoft Corporation (`LICENSE-OnnxRuntimeBindings.txt`).

Why a copy instead of the package: the package also declares the binary target
`onnxruntime_extensions` on download.onnxruntime.ai, which no longer answers
with a valid certificate (November 2026). SwiftPM downloads every binary target
of a dependency, so resolving failed on every machine without a cached copy.
The binary target `onnxruntime` points to the same release asset with the same
checksum as the package did.

When ONNX Runtime is bumped: replace the copy from the new tag, update URL and
checksum in `Package.swift`, and re-diff `flutter_onnxruntime_objc/vendor/`.
The same applies to `ios/flutter_onnxruntime/`.
