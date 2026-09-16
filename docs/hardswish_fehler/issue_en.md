# Fertige Meldung für https://github.com/masicai/flutter_onnxruntime/issues/new

Titel:

    HardSwish returns all zeros on Linux (correct in a plain process with the same libonnxruntime.so)

Text ab hier:

---

## Summary

An ONNX model containing a single `HardSwish` node returns **all zeros**
when run from a Flutter Linux application. The same model file, executed by
the **same `libonnxruntime.so`** in an ordinary C++ program on the same
machine, returns the correct values.

```
input   -4       -3       -1       -0.5      0        0.5      1        3
want    -0       -0       -0.3333  -0.2083   0        0.2917   0.6667   3
got      0        0        0        0        0        0        0        0
```

Only `HardSwish` is affected. In the very same process, `HardSigmoid`,
`Sigmoid`, `Relu`, `Elu`, `Softplus`, `Celu` and `Mish` all return correct
results — including `Celu` and `Mish`, which are, like `HardSwish`,
defined through a function body in ONNX.

The practical impact is that any model with a MobileNetV3 backbone is
unusable. In our case it is PP-OCR text recognition: the model has 27
`HardSwish` nodes, and from the first one onwards the whole computation is
worthless. The final output then depends neither on the input data nor on
the input shape — a failure mode that is easy to misread as "the input
never reaches the model".

## Reproduction

```bash
flutter create probe && cd probe
flutter pub add flutter_onnxruntime
flutter pub add dev:integration_test --sdk flutter
```

Build the one-node models (needs the `onnx` python package):

```python
import os
import onnx
from onnx import TensorProto, helper

target = os.path.expanduser("~/ocr_modelle")
os.makedirs(target, exist_ok=True)
for op in ["HardSwish", "HardSigmoid", "Sigmoid", "Relu",
           "Elu", "Softplus", "Celu", "Mish"]:
    node = helper.make_node(op, ["x"], ["y"])
    graph = helper.make_graph(
        [node], f"only_{op}",
        [helper.make_tensor_value_info("x", TensorProto.FLOAT, [1, 8])],
        [helper.make_tensor_value_info("y", TensorProto.FLOAT, [1, 8])],
    )
    model = helper.make_model(graph, opset_imports=[helper.make_opsetid("", 18)])
    model.ir_version = 8
    onnx.checker.check_model(model)
    onnx.save(model, os.path.join(target, f"nur_{op.lower()}.onnx"))
```

`integration_test/hardswish_test.dart`:

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('one operator per model', () async {
    final dir = '${Platform.environment['HOME']}/ocr_modelle';
    final x =
        Float32List.fromList([-4.0, -3.0, -1.0, -0.5, 0.0, 0.5, 1.0, 3.0]);

    for (final op in [
      'hardswish', 'hardsigmoid', 'sigmoid', 'relu',
      'elu', 'softplus', 'celu', 'mish',
    ]) {
      final s = await OnnxRuntime().createSession('$dir/nur_$op.onnx');
      final t = await OrtValue.fromList(x, [1, 8]);
      final out = await s.run({s.inputNames.first: t});
      final raw = (await out.values.first.asFlattenedList()).cast<num>();
      // ignore: avoid_print
      print('${op.padRight(12)} '
          '${raw.map((v) => v.toDouble().toStringAsFixed(4)).join(' ')}');
      for (final v in out.values) {
        await v.dispose();
      }
      await t.dispose();
      await s.close();
    }
  });
}
```

```bash
flutter test integration_test/hardswish_test.dart -d linux
```

Observed:

```
hardswish    -0.0000 -0.0000 -0.0000 -0.0000 0.0000 0.0000 0.0000 0.0000   <-- wrong
hardsigmoid   0.0000  0.0000  0.3000  0.4000 0.5000 0.6000 0.7000 1.0000
sigmoid       0.0180  0.0474  0.2689  0.3775 0.5000 0.6225 0.7311 0.9526
relu          0.0000  0.0000  0.0000  0.0000 0.0000 0.5000 1.0000 3.0000
elu          -0.9817 -0.9502 -0.6321 -0.3935 0.0000 0.5000 1.0000 3.0000
softplus      0.0181  0.0486  0.3133  0.4741 0.6931 0.9741 1.3133 3.0486
celu         -0.9817 -0.9502 -0.6321 -0.3935 0.0000 0.5000 1.0000 3.0000
mish         -0.0726 -0.1456 -0.3034 -0.2207 0.0000 0.3752 0.8651 2.9865
```

On macOS every line is correct, `hardswish` included.

## Why this is probably not the marshalling code

I instrumented the plugin's Linux sources to find out where the data is
lost, and it is not lost:

* `createFloat32Tensor` receives the correct values, and reading the tensor
  back through `getTensorData` returns them unchanged (46080 of 46080
  elements, max deviation 0.0).
* Right before `session->Run`, the input tensor holds the correct shape and
  the correct element sums.
* Right after `session->Run`, the output is already wrong.

A **fully standalone C++ inference inside the Flutter process** — own
`Ort::Env`, own session, own tensor, no plugin code at all — reproduces the
failure. A **child process spawned from that same app** computes correctly.
So it is bound to the address space, not to the plugin's data path, not to
the environment.

I am reporting it here rather than upstream because it only reproduces
through Flutter, and because this package ships the ONNX Runtime binary. If
you would rather have it filed against onnxruntime, I am happy to do that
too.

## Ruled out

| Suspicion | How it was tested | Result |
|---|---|---|
| Plugin data path | standalone C++ inference inside the Flutter process | same failure |
| Environment, rlimits, cwd | child process of the same app | correct |
| Our own app / its dependencies | bare `flutter create` app, only this plugin | same failure |
| Symbol interposition | all 272 libraries of the app process `dlopen`ed into a plain probe, incl. loading ORT last | no effect |
| Threading | `SetIntraOpNumThreads(1)`, `ORT_SEQUENTIAL`, and a freshly spawned thread | same failure |
| Memory pattern / arena / prepacking | `DisableMemPattern`, `DisableCpuMemArena`, `session.disable_prepacking` | same failure |
| Graph optimization | `ORT_DISABLE_ALL` | same failure |
| ONNX Runtime version | 1.22.0 and 1.23.0 | both affected |
| Tensor size | 1 … 1024 elements | wrong even for a single element |
| Floating point state | MXCSR read in-process | `0x1fa0`, nothing unusual |

## Environment

* Ubuntu 25.10 (kernel 7.0), x86-64
* Flutter 3.44.8 (stable, revision `058e0af2c2`), Dart 3.12.2,
  engine `13ffd72b2f9a5ca4db2a74ea52d5353ec2e8f939`
* `flutter_onnxruntime` 1.8.3
* ONNX Runtime 1.22.0 — the Linux x64 package this plugin downloads
* models at opset 14 and 18, both affected

Worth noting: the **working** platform runs the newer runtime. macOS pulls
`onnxruntime-objc` 1.23.0 and is correct; Linux is wrong with 1.22.0 **and**
with 1.23.0 (I swapped the shared library and rebuilt). So the same ORT
version behaves differently on the two platforms, which rules the version
out as the cause.

## There are no error logs

This is part of the finding, not a gap in the investigation. With ORT
logging at severity 0 (and `dup2` on fd 2, because `flutter test` swallows
the app's stderr):

| log | lines | warnings | errors |
|---|---|---|---|
| inside the Flutter process (wrong) | 335 | 0 | 0 |
| standalone (correct) | 372 | 0 | 0 |

Both sessions initialise identically — same graph transformers with the same
results, `All nodes placed on [CPUExecutionProvider]. Number of nodes: 236`,
`Session successfully initialized`. No missing kernel, no fallback, no
warning. The model loads cleanly and then silently computes the wrong
thing.

## Workaround (for anyone who lands here)

`HardSwish(x)` is by definition `x * HardSigmoid(x, alpha=1/6, beta=0.5)`,
and both of those operators compute correctly. Rewriting the model — one
`HardSwish` node becomes a `HardSigmoid` plus a `Mul` — restores correct
results. Verified against `onnxruntime` on random inputs at three widths:
maximum deviation 0.000, i.e. bit-identical, not an approximation.
