"""Legt Modelle mit je einem Rechenschritt an - zum Nachstellen des
HardSwish-Fehlers und zum Gegenprüfen mit unverdaechtigen Schritten."""
import os

import onnx
from onnx import TensorProto, helper

ZIEL = os.path.expanduser("~/ocr_modelle")
SCHRITTE = ["HardSwish", "HardSigmoid", "Sigmoid", "Relu", "Elu", "Softplus", "Celu", "Mish"]

os.makedirs(ZIEL, exist_ok=True)
for op in SCHRITTE:
    knoten = helper.make_node(op, ["x"], ["y"])
    graph = helper.make_graph(
        [knoten],
        f"nur_{op}",
        [helper.make_tensor_value_info("x", TensorProto.FLOAT, [1, 8])],
        [helper.make_tensor_value_info("y", TensorProto.FLOAT, [1, 8])],
    )
    modell = helper.make_model(graph, opset_imports=[helper.make_opsetid("", 18)])
    modell.ir_version = 8
    onnx.checker.check_model(modell)
    pfad = os.path.join(ZIEL, f"nur_{op.lower()}.onnx")
    onnx.save(modell, pfad)
    print("gebaut:", pfad)
