"""验证 1：组合器件真值表 + 进位链延迟 + 冒险（静态 1 冒险）。

运行：python -m tests.test_adder（在 ref/ 目录下）
"""

from __future__ import annotations

import itertools

from simcore.components import ALU, full_adder, half_adder, ripple_adder, bit_vec, join
from simcore.logic import Circuit, int_to_bits, bits_to_int, measure_settle


def make_fa():
    c = Circuit("fa")
    a = c.add_wire("a", 1, "0")
    b = c.add_wire("b", 1, "0")
    cin = c.add_wire("cin", 1, "0")
    s, cout = full_adder(c, "fa", a, b, cin)
    c.eng.run_events()
    return c, a, b, cin, s, cout


def test_full_adder_truth_table() -> int:
    rows = 0
    for a, b, cin in itertools.product((0, 1), repeat=3):
        c, wa, wb, wc, ws, wco = make_fa()
        c.set_input("a", str(a))
        c.set_input("b", str(b))
        c.set_input("cin", str(cin))
        c.eng.run_events()
        got_s, got_c = ws.bits, wco.bits
        exp_s = str(a ^ b ^ cin)
        exp_c = str((a + b + cin) // 2)
        assert got_s == exp_s and got_c == exp_c, (a, b, cin, got_s, got_c, exp_s, exp_c)
        rows += 1
    return rows


def test_half_adder_truth_table() -> int:
    rows = 0
    for a, b in itertools.product((0, 1), repeat=2):
        c = Circuit("ha")
        wa = c.add_wire("a", 1, "0")
        wb = c.add_wire("b", 1, "0")
        s, co = half_adder(c, "ha", wa, wb)
        c.eng.run_events()
        c.set_input("a", str(a))
        c.set_input("b", str(b))
        c.eng.run_events()
        assert s.bits == str(a ^ b) and co.bits == str(a & b)
        rows += 1
    return rows


def build_ripple(width: int):
    c = Circuit(f"add{width}")
    a = bit_vec(c, "a", width, "0" * width)
    b = bit_vec(c, "b", width, "0" * width)
    cin = c.add_wire("cin", 1, "0")
    s, cout = ripple_adder(c, "add", a, b, cin)
    c.eng.run_events()
    return c, a, b, cin, s, cout


def test_ripple_adder_exhaustive(width: int = 4) -> int:
    cases = 0
    c, a, b, cin, s, cout = build_ripple(width)
    for x in range(1 << width):
        for y in range(1 << width):
            for ci in (0, 1):
                for i in range(width):
                    c.set_input(a[i].name, int_to_bits(x, width)[width - 1 - i])
                    c.set_input(b[i].name, int_to_bits(y, width)[width - 1 - i])
                c.set_input(cin.name, str(ci))
                c.eng.run_events()
                got = bits_to_int(join(s))
                assert got == (x + y + ci) & ((1 << width) - 1), (x, y, ci, got)
                assert cout.bits == str((x + y + ci) >> width)
                cases += 1
    return cases


def test_carry_chain_delay(width: int = 8) -> int:
    """0xFF + 0x00 → 0xFF + 0x01：进位穿过全部 8 位，测最坏路径延迟。

    理论值：bit0 的 cout 由 a&b 在 +3 产生，OR 再 +3 → +6；
    其后每级 carry_in→cout = and(3)+or(3) = 6；故 cout 延迟 = 6n = 48（n=8）。
    """
    c, a, b, cin, s, cout = build_ripple(width)
    c.set_input(cin.name, "0")
    for i in range(width):
        c.set_input(a[i].name, "1")
        c.set_input(b[i].name, "0")
    c.eng.run_events()
    t0 = c.eng.now
    c.set_input(b[0].name, "1")
    delay = measure_settle(c, [cout.name] + [w.name for w in s], t0)
    assert bits_to_int(join(s)) == 0, "0xFF+0x01 低 8 位应为 0"
    assert cout.bits == "1"
    return delay


def _hazard_circuit(extra_skew: int):
    """F = A·C + B·C'，A=B=1；给第二条路径加 extra_skew 的缓冲延时。"""
    c = Circuit("hazard")
    c.add_wire("A", 1, "1")
    c.add_wire("B", 1, "1")
    c.add_wire("C", 1, "1")
    nc = c.gate("nC", "not", ["C"])
    p1 = c.gate("p1", "and", ["A", "C"])
    p2 = c.gate("p2", "and", ["B", "nC"])
    src = p2
    if extra_skew:
        src = c.gate("skew", "buf", [p2.name], delay=extra_skew)
    f = c.gate("F", "or", [p1.name, src.name])
    c.watch_glitch("F")
    c.eng.run_events()
    return c, f


def test_hazard_inertial_filtering() -> str:
    """路径偏斜(1 tick) < 或门延迟(3 tick)：毛刺被惯性延迟滤除，F 不出现 0。

    这是**真实 CMOS 行为**，不是引擎缺陷：门对窄于自身延迟的脉冲不响应。
    教学上必须讲清，否则玩家会以为"理论冒险 = 一定看得见"。
    """
    c, f = _hazard_circuit(extra_skew=0)
    t0 = c.eng.now
    c.set_input("C", "0")
    c.eng.run_events()
    changes = [(t - t0, v) for (t, name, _o, v) in c.history if name == "F" and t >= t0]
    assert changes == [], f"偏斜 1 tick 时不应有毛刺，实际 {changes}"
    assert f.bits == "1"
    return "无毛刺（被滤除），F 保持 1"


def test_static_hazard() -> tuple:
    """路径偏斜 4 tick > 或门延迟 3 tick：静态 1 冒险可见（1→0→1）。

    说明：现实中的毛刺宽度由偏斜与门延迟之差决定；这里偏斜来自一段显式缓冲延时。
    """
    c, f = _hazard_circuit(extra_skew=4)
    t0 = c.eng.now
    c.set_input("C", "0")
    c.eng.run_events()
    seq = [(t - t0, v) for (t, name, _o, v) in c.history if name == "F" and t >= t0]
    assert [v for _, v in seq] == ["0", "1"], f"应出现 1→0→1 毛刺，实际 {seq}"
    width = seq[1][0] - seq[0][0]
    assert f.bits == "1"
    return seq, width


def test_alu() -> int:
    """ALU 8 种操作 + 标志位。"""
    c = Circuit("alu")
    alu = ALU(c, "alu", 4)
    c.eng.run_events()
    cases = 0
    checks = [
        (3, 5, 0b000, 8, "Z0 C0 V1 N1"),
        (9, 6, 0b001, 3, "Z0"),
        # 3 - 9：9 在 4 位有符号里是 -7，3-(-7)=10 超出 [-8,7] → 无进位出、有溢出
        (3, 9, 0b001, 10, "C0 V1 N1"),
        (7, 7, 0b000, 14, "V1 N1"),
        (0b1010, 0b1100, 0b100, 0b1000, ""),
        (0b1010, 0b1100, 0b101, 0b1110, ""),
        (0b1010, 0b1100, 0b110, 0b0110, ""),
        (0b1010, 0b0000, 0b111, 0b0101, ""),
        (0b1010, 0, 0b010, 0b0100, ""),
        (0b1010, 0, 0b011, 0b0101, ""),
    ]
    for a, b, op, exp, flags in checks:
        alu.set(a, b, op)
        c.eng.run_events()
        got, f = alu.out()
        assert got == exp, (a, b, op, got, exp)
        for token in flags.split():
            name, val = token[0], token[1]
            assert f[name] == val, (a, b, op, name, f)
        cases += 1
    # 零标志
    alu.set(5, 5, 0b001)
    c.eng.run_events()
    got, f = alu.out()
    assert got == 0 and f["Z"] == "1"
    return cases + 1


def test_alu_delay() -> int:
    c = Circuit("alu_delay")
    alu = ALU(c, "alu", 4)
    c.eng.run_events()
    alu.set(0, 0, 0b000)
    c.eng.run_events()
    t0 = c.eng.now
    alu.set(0xF, 0xF, 0b000)
    c.eng.run_events()
    last = max(w.last_change for w in alu.result)
    return last - t0, bits_to_int(join(alu.result))


ALL = [
    ("半加器真值表", test_half_adder_truth_table),
    ("全加器真值表", test_full_adder_truth_table),
    ("4 位行波加法器穷举", test_ripple_adder_exhaustive),
    ("8 位进位链延迟", test_carry_chain_delay),
    ("惯性延迟滤除窄毛刺", test_hazard_inertial_filtering),
    ("静态 1 冒险（可见）", test_static_hazard),
    ("ALU 运算与标志", test_alu),
    ("ALU 延迟", test_alu_delay),
]

if __name__ == "__main__":
    for name, fn in ALL:
        r = fn()
        print(f"[PASS] {name}: {r}")
