"""从 docs/simulation/ref 参考实现导出 M1 测试向量。

生成 tests/data/ref_vectors.json，供 tests/test_sim.gd 逐条比对，
确保游戏内 L0b/L1 实现与参考模型在同一组向量下一致。

用法：python tools/gen_ref_vectors.py
"""
from __future__ import annotations

import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "docs", "simulation", "ref"))

from simcore import logic  # noqa: E402

TRI = ["0", "1", "X"]


def main() -> None:
    gates = {}
    for kind in ("and", "or", "xor"):
        rows = []
        for a in TRI:
            for b in TRI:
                rows.append([a, b, logic.tri_bin(kind, a, b)])
        gates[kind] = rows
    gates["not"] = [[a, logic.tri_not(a)] for a in TRI]

    half_adder = []
    for a in TRI:
        for b in TRI:
            half_adder.append(
                [a, b, logic.tri_bin("xor", a, b), logic.tri_bin("and", a, b)]
            )

    doc = {
        "source": "docs/simulation/ref/simcore/logic.py",
        "generated_by": "tools/gen_ref_vectors.py",
        "note": "三值 Kleene 逻辑真值向量；游戏内 SimValue 必须逐条一致。",
        "gates": gates,
        "half_adder": half_adder,
        "gate_delay": logic.GATE_DELAY,
    }
    out_dir = os.path.join(ROOT, "tests", "data")
    os.makedirs(out_dir, exist_ok=True)
    out_path = os.path.join(out_dir, "ref_vectors.json")
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(doc, f, ensure_ascii=False, indent=2)
    print(f"wrote {out_path}: {sum(len(v) for v in gates.values())} gate rows, {len(half_adder)} half-adder rows")


if __name__ == "__main__":
    main()
