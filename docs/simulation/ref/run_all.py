"""一键运行全部验证，并生成 verify_report.md。

用法（在 ref/ 目录）：python run_all.py
"""

from __future__ import annotations

import json
import platform
import sys
import time
from pathlib import Path

import bench
from tests import test_adder, test_crypto, test_network, test_sequential

SUITES = [
    ("组合器件 / 时序 / 冒险", test_adder.ALL),
    ("时序器件 / 存档", test_sequential.ALL),
    ("网络 / 路由 / 重传", test_network.ALL),
    ("加密强度边界", test_crypto.ALL),
]


def main() -> int:
    rows = []
    failed = []
    t_start = time.perf_counter()
    for suite, cases in SUITES:
        for name, fn in cases:
            t0 = time.perf_counter()
            try:
                result = fn()
                rows.append((suite, name, "PASS", result, round((time.perf_counter() - t0) * 1000, 1)))
            except AssertionError as e:
                rows.append((suite, name, "FAIL", str(e), round((time.perf_counter() - t0) * 1000, 1)))
                failed.append((suite, name, str(e)))
    bm = [bench.bench(g, toggles=6) for g in (64, 256, 1024)]

    out = Path(__file__).with_name("verify_report.md")
    lines = [
        "# 参考实现验证报告（自动生成）",
        "",
        f"- 生成时间：{time.strftime('%Y-%m-%d %H:%M:%S')}",
        f"- 运行环境：Python {platform.python_version()} / {platform.system()}",
        f"- 总耗时：{round(time.perf_counter() - t_start, 2)} s",
        f"- 用例：{len(rows)} 个，通过 {sum(1 for r in rows if r[2] == 'PASS')}，失败 {len(failed)}",
        "",
        "## 用例明细",
        "",
        "| 套件 | 用例 | 结果 | 关键输出 | 耗时(ms) |",
        "|---|---|---|---|---|",
    ]
    for suite, name, status, result, ms in rows:
        text = json.dumps(result, ensure_ascii=False, default=str)
        if len(text) > 220:
            text = text[:217] + "..."
        lines.append(f"| {suite} | {name} | {status} | `{text}` | {ms} |")

    lines += ["", "## 性能锚点（Python 参考实现，不是 Godot 性能）", "",
              "| 门数 | 事件数 | 耗时(ms) | 事件/秒 | 事件/毫秒 |", "|---|---|---|---|---|"]
    for b in bm:
        lines.append(f"| {b['gates']} | {b['events']} | {b['elapsed_ms']} | {b['events_per_sec']} | {b['events_per_ms']} |")

    lines += ["", "## 说明", "",
              "* 本报告由 `run_all.py` 自动生成，数字来自本机实测，不同机器会有差异。",
              "* Python 参考实现用于**验证语义正确性**，不能用来推算 Godot 主线程预算；",
              "  性能预算见 `../06_performance.md`，其中 GDScript / GDExtension 的系数是估算并明确标注。"]
    out.write_text("\n".join(lines), encoding="utf-8")

    for suite, name, status, result, ms in rows:
        mark = "PASS" if status == "PASS" else "FAIL"
        print(f"[{mark}] {suite} / {name}  ({ms} ms)")
    print(f"\n通过 {sum(1 for r in rows if r[2] == 'PASS')}/{len(rows)}；报告写入 {out}")
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
