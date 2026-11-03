"""验证 3：时序器件（DFF / 寄存器 / 计数器 / 存储器）与存档回放。

运行：python -m tests.test_sequential（在 ref/ 目录下）
"""

from __future__ import annotations

from simcore.components import Counter, Memory, Register, bit_vec, join
from simcore.logic import Circuit, int_to_bits


def test_dff_samples_on_rising_edge() -> dict:
    c = Circuit("dff")
    c.add_wire("d", 1, "0")
    # phase=5：首次上升沿在 t=5，给输入留出建立时间
    c.clock("clk", period=10, phase=5, duty=5)
    q = c.dff("q", "d", "clk")
    c.set_input("d", "1", delay=2)
    c.run_until(8)
    assert q.bits == "1", q.bits  # 上升沿 t=5，clk→Q=2 → t=7
    c.set_input("d", "0", delay=0)
    c.run_until(14)
    assert q.bits == "1", "下降沿(t=10)不应改变输出"
    c.run_until(17)
    assert q.bits == "0", "下一个上升沿在 t=15，t+2 采到 0"
    return {"clock_to_q": 2, "period": 10}


def test_dff_setup_violation_metastable() -> dict:
    """D 在上升沿前 1 tick 才变化 → 输出 X，并记录 METASTABLE。"""
    c = Circuit("dff_setup")
    c.add_wire("d", 1, "0")
    c.clock("clk", period=10, phase=5, duty=5)
    q = c.dff("q", "d", "clk", setup=2)
    c.idle_to(14)
    c.set_input("d", "1")  # t=14 变化，下一个上升沿在 15 → 只差 1 tick
    c.run_until(20)  # 只在违例边沿之后观察；下一个正常边沿(25)会把 X 覆盖掉
    assert q.bits == "X", q.bits
    tags = [t for t in c.eng.trace if t[1] == "METASTABLE"]
    assert tags, c.eng.trace
    return {"q@17": "X", "trace": tags[:1]}


def test_register_load_enable() -> dict:
    c = Circuit("reg")
    c.clock("clk", period=10, phase=5, duty=5)
    c.add_wire("en", 1, "0")
    r = Register(c, "r", 4, "clk", enable="en")
    r.drive("1010")
    c.run_until(20)
    assert r.read() == "0000", r.read()   # 未使能，保持复位值
    c.set_input("en", "1", delay=2)       # t=22 使能，下一个沿 25
    c.run_until(40)
    assert r.read() == "1010", r.read()
    c.set_input("en", "0", delay=1)       # 下一个沿 35 前撤销
    c.run_until(38)
    r.drive("0101")
    c.run_until(60)
    assert r.read() == "1010", "使能撤掉后必须保持旧值"
    return {"loaded": "1010", "held": r.read()}


def test_counter_wrap() -> dict:
    c = Circuit("cnt")
    # 计数器的组合路径 = 4 位行波加法器(24) + 选择器(7) + 建立(2) = 33 tick
    # 时钟周期必须 ≥ 33，否则时序不收敛（见 test_clock_too_fast）
    c.clock("clk", period=100, phase=5, duty=50)
    c.add_wire("en", 1, "1")
    c.add_wire("load", 1, "0")
    cnt = Counter(c, "c", 4, "clk", "en", "load")
    vals = []
    for _ in range(18):
        c.run_until(c.eng.now + 100)
        vals.append(cnt.read())
    assert all("X" not in v for v in vals), vals
    assert "0000" in vals[1:], f"4 位计数器必须回绕，实际 {vals}"
    assert len(set(vals[:16])) == 16, "0..15 应各不相同"
    return {"first": vals[:8], "last": vals[-4:]}


def test_clock_too_fast() -> dict:
    """时钟周期 10 < 组合延迟 31：引擎必须暴露亚稳态（输出 X），而不是悄悄算错。"""
    c = Circuit("cnt_fast")
    c.clock("clk", period=10, phase=5, duty=5)
    c.add_wire("en", 1, "1")
    c.add_wire("load", 1, "0")
    cnt = Counter(c, "c", 4, "clk", "en", "load")
    seen = []
    for _ in range(14):
        c.run_until(c.eng.now + 10)
        seen.append(cnt.read())
    assert any("X" in v for v in seen), seen
    assert any(t[1] == "METASTABLE" for t in c.eng.trace)
    return {"observed": [v for v in seen if "X" in v][:3], "reason": "comb_delay 31 > period 10"}


def test_memory_latency_and_errors() -> dict:
    c = Circuit("mem")
    m = Memory(c, "m", addr_width=4, data_width=8, read_latency=10, write_latency=5)
    m.load(2, 0x5A)
    for i in range(4):
        c.set_input(m.addr[i].name, int_to_bits(2, 4)[3 - i])
    c.set_input(m.re.name, "1")
    c.settle()          # 让地址/控制信号真正落到位
    m.cycle()
    c.run_until(c.eng.now + 12)
    assert m.peek() == int_to_bits(0x5A, 8), m.peek()

    # 越界/未初始化 → X + ERR_ADDR
    c.set_input(m.addr[0].name, "1")
    c.set_input(m.addr[1].name, "1")  # addr=3，未写入
    c.settle()
    m.cycle()
    c.run_until(c.eng.now + 12)
    assert "X" in m.peek()
    assert any(t[1] == "ERR_ADDR" for t in c.eng.trace)
    return {"read": int_to_bits(0x5A, 8), "invalid": m.peek()}


def test_snapshot_roundtrip() -> dict:
    """组合电路在静止 tick 存档 → 恢复 → 结果一致。"""
    c = Circuit("snap")
    a = c.add_wire("a", 1, "0")
    b = c.add_wire("b", 1, "0")
    s = c.gate("s", "xor", ["a", "b"])
    c.set_input("a", "1")
    c.set_input("b", "0")
    c.settle()
    snap = c.snapshot()
    assert s.bits == "1"
    c2 = Circuit("snap2")
    c2.add_wire("a", 1, "0")
    c2.add_wire("b", 1, "0")
    c2.gate("s", "xor", ["a", "b"])
    c2.settle()
    c2.restore(snap)
    assert c2.probe("s") == "1" and c2.eng.now == snap["tick"]
    return {"tick": snap["tick"], "wires": len(snap["wires"])}


ALL = [
    ("DFF 上升沿采样", test_dff_samples_on_rising_edge),
    ("DFF 建立时间违例 → X", test_dff_setup_violation_metastable),
    ("寄存器使能/保持", test_register_load_enable),
    ("4 位计数器回绕", test_counter_wrap),
    ("时钟过快 → 亚稳态", test_clock_too_fast),
    ("存储器延迟与错误", test_memory_latency_and_errors),
    ("静止快照往返", test_snapshot_roundtrip),
]

if __name__ == "__main__":
    for name, fn in ALL:
        r = fn()
        print(f"[PASS] {name}: {r}")
