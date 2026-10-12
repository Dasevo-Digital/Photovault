// Copyright (c) MASIC AI
// All rights reserved.
//
// This source code is licensed under the license found in the
// LICENSE file in the root directory of this source tree.

/// The Flutter side of ONNX Runtime: the native code and the method channel
/// that implements [OnnxRuntimePlatform]. The API itself lives in
/// `package:onnxruntime_api` and is re-exported here.
library;

export 'package:onnxruntime_api/onnxruntime_api.dart';
export 'src/flutter_onnxruntime_method_channel.dart' show MethodChannelFlutterOnnxruntime;
