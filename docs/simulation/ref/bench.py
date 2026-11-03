"""性能基准：用 Python 参考实现测"事件吞吐"，作为 06_performance.md 的实测锚点。

注意：Python 的数字**不能**直接当作 Godot/GDScript 或 GDExtension 的性能，
它只是"同一算法结构下"的参考。文档里会给出换算假设与保守余量。
"""

from __future__ import annotations

import time

from simcore.logic import Circuit, int_to_bits


def build_chain(n_gates: int) -> Circuit:
    c = Circuit("bench")
    c.add_wire("a", 1, "0")
    prev = "a"
    for i in range(n_gates):
        c.gate(f"g{i}", "xor", [prev, "a"])
        prev = f"g{i}"
    return c


def bench(n_gates: int = 512, toggles: int = 8) -> dict:
    c = build_chain(n_gates)
    c.eng.run_events()
    events = c.eng.event_count
    t0 = time.perf_counter()
    for k in range(toggles):
        c.set_input("a", str(k % 2))
        c.eng.run_events()
    elapsed = time.perf_counter() - t0
    total_events = c.eng.event_count - events
    ev_per_s = total_events / elapsed if elapsed else 0
    return {
        "gates": n_gates,
        "toggles": toggles,
        "events": total_events,
        "elapsed_ms": round(elapsed * 1000, 2),
        "events_per_sec": int(ev_per_s),
        "events_per_ms": int(ev_per_s / 1000),
    }


if __name__ == "__main__":
    for gates in (64, 256, 1024):
        print(bench(gates))
