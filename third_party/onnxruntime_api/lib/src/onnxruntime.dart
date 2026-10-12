// Copyright (c) MASIC AI
// All rights reserved.
//
// This source code is licensed under the license found in the
// LICENSE file in the root directory of this source tree.

import 'onnxruntime_platform.dart';
import 'ort_provider.dart';
import 'ort_session.dart';

class OnnxRuntime {
  Future<String?> getPlatformVersion() {
    return OnnxRuntimePlatform.instance.getPlatformVersion();
  }

  /// Create an ONNX Runtime session with the given model path
  Future<OrtSession> createSession(
    String modelPath, {
    OrtSessionOptions? options,
  }) async {
    final result = await OnnxRuntimePlatform.instance.createSession(
      modelPath,
      sessionOptions: options?.toMap() ?? {},
    );
    return OrtSession.fromMap(result);
  }

  /// Get the available providers
  ///
  /// Returns a list of the available providers. Provider names reported by the native runtime that match no
  /// [OrtProvider] value (e.g. `WEBGPU` from the ONNX Runtime 1.28 Android package, which the plugin cannot create
  /// sessions with yet) are left out, so a provider added by a newer ONNX Runtime cannot break the call.
  Future<List<OrtProvider>> getAvailableProviders() async {
    final providers =
        await OnnxRuntimePlatform.instance.getAvailableProviders();
    final providersByName = OrtProvider.values.asNameMap();
    return providers
        .map((p) => providersByName[p])
        .whereType<OrtProvider>()
        .toList();
  }
}
