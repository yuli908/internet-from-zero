"""核心器件参考实现：从半加器到 ALU / 存储器。

设计原则
--------
* **组合器件全部用门搭建**（加法器、选择器、ALU 的运算与选择通路），
  延迟与冒险是"算出来的"，不是"填表填出来的"。
* **时序原语是行为级**（D 触发器、存储器阵列），原因写在 03_components.md：
  它们的物理细节（亚稳态概率、灵敏放大器）用门级搭建只会得到"看起来很真"的假模型。
* 控制单元见 cpu.py，微码表与 03_components.md 中的状态转移表同源。

位序约定：向量统一用"位线列表"，下标 0 = 最低位；对外显示时拼成 MSB 在前字符串。
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Dict, List, Optional, Sequence, Tuple

from .logic import Circuit, Wire, bits_to_int, int_to_bits, X


# ---- 小工具 ------------------------------------------------------------------


def bit_vec(c: Circuit, prefix: str, width: int, init: Optional[str] = None) -> List[Wire]:
    """创建一组位线，返回 [bit0 ... bit(width-1)]。"""
    s = init if init is not None else "0" * width
    if len(s) != width:
        raise ValueError("初始值位宽不匹配")
    return [c.add_wire(f"{prefix}[{i}]", 1, s[width - 1 - i]) for i in range(width)]


def join(vec: Sequence[Wire]) -> str:
    """[bit0..bitN-1] → MSB 在前字符串。"""
    return "".join(w.bits for w in reversed(vec))


def split(bits: str) -> List[str]:
    """MSB 在前字符串 → [bit0..bitN-1]。"""
    return list(reversed(bits))


def mux2(c: Circuit, name: str, d0: Wire, d1: Wire, sel: Wire) -> Wire:
    """2:1 选择器 = (d0 & ~s) | (d1 & s)。延时 7 tick（not1 + and3 + or3）。"""
    ns = c.gate(f"{name}.nsel", "not", [sel.name])
    a = c.gate(f"{name}.a", "and", [d0.name, ns.name])
    b = c.gate(f"{name}.b", "and", [d1.name, sel.name])
    return c.gate(f"{name}.y", "or", [a.name, b.name])


def mux_vec(c: Circuit, name: str, d0: Sequence[Wire], d1: Sequence[Wire], sel: Wire) -> List[Wire]:
    return [mux2(c, f"{name}.b{i}", d0[i], d1[i], sel) for i in range(len(d0))]


# ---- 加法器 ------------------------------------------------------------------


def half_adder(c: Circuit, name: str, a: Wire, b: Wire) -> Tuple[Wire, Wire]:
    """S = A xor B (@4)，C = A and B (@3)。"""
    s = c.gate(f"{name}.s", "xor", [a.name, b.name])
    co = c.gate(f"{name}.co", "and", [a.name, b.name])
    return s, co


def full_adder(c: Circuit, name: str, a: Wire, b: Wire, cin: Wire) -> Tuple[Wire, Wire]:
    """全加器 = 2 个半加器 + 1 个或门（标准结构）。

    路径延迟（相对输入变化）：
      s1 @4（xor 4），c1 @3（and 3），两者并行
      s  @8（s1 再 xor，+4）
      c2 @8（s1 & cin，+4）
      cout @11（c1 | c2，+3；但 c1 早已在 3 到达，所以实际由 c2 决定）
    从 **cin 到 cout 的关键路径 = and(3) + or(3) = 6 tick**，
    从 **cin 到 sum = xor(4)**；这也是行波加法器每级进位 6 tick 的依据。
    """
    s1, c1 = half_adder(c, f"{name}.ha1", a, b)
    s, c2 = half_adder(c, f"{name}.ha2", s1, cin)
    cout = c.gate(f"{name}.cout", "or", [c1.name, c2.name])
    return s, cout


def ripple_adder(
    c: Circuit, name: str, a: Sequence[Wire], b: Sequence[Wire], cin: Wire
) -> Tuple[List[Wire], Wire]:
    """行波进位加法器：n 位的 cout 延迟 = 6n（n=8 → 48）；sum 最坏 = 6(n-1)+4。"""
    if len(a) != len(b):
        raise ValueError("加法器位宽不匹配")
    s: List[Wire] = []
    carry = cin
    for i in range(len(a)):
        si, carry = full_adder(c, f"{name}.fa{i}", a[i], b[i], carry)
        s.append(si)
    return s, carry


# ---- 寄存器 / 计数器 ---------------------------------------------------------


class Register:
    """n 位寄存器：使能端 = "保持 q / 采纳 d" 的 2:1 选择器 + DFF（真实寄存器文件做法）。"""

    def __init__(
        self,
        c: Circuit,
        name: str,
        width: int,
        clk: str,
        enable: Optional[str] = None,
        reset: Optional[str] = None,
        init: str = "0" * 8,
    ):
        self.c, self.name, self.width = c, name, width
        self.d = bit_vec(c, f"{name}.d", width)
        self.q = bit_vec(c, f"{name}.q", width, init[:width])
        for i in range(width):
            src: Wire = self.d[i]
            if enable is not None:
                src = mux2(c, f"{name}.en{i}", self.q[i], self.d[i], c.wires[enable])
            c.dff(f"{name}.q[{i}]", src.name, clk, reset)

    def read(self) -> str:
        return join(self.q)

    def drive(self, bits: str) -> None:
        """把外部值接到 d 端（例如常量或上一级总线）。"""
        if len(bits) != self.width or X in bits:
            raise ValueError("drive 只接受确定的等宽值")
        for i in range(self.width):
            self.c.set_input(self.d[i].name, bits[self.width - 1 - i])

    def bind_d(self, src: Sequence[Wire]) -> None:
        for i in range(self.width):
            self.c.bind(src[i].name, self.d[i].name)


class Counter:
    """模 2^n 计数器：寄存器 + 加一器 + 并行加载选择器。"""

    def __init__(self, c: Circuit, name: str, width: int, clk: str, enable: str, load: str):
        self.c, self.name, self.width = c, name, width
        self.reg = Register(c, name, width, clk, enable=enable)
        one = c.add_wire(f"{name}.one", 1, "1")
        zero = c.add_wire(f"{name}.zero", 1, "0")
        inc, _ = ripple_adder(c, f"{name}.inc", self.reg.q, [one] + [zero] * (width - 1), zero)
        self.load_data = bit_vec(c, f"{name}.ld", width)
        sel = mux_vec(c, f"{name}.load", inc, self.load_data, c.wires[load])
        self.reg.bind_d(sel)

    def read(self) -> str:
        return self.reg.read()


# ---- ALU ---------------------------------------------------------------------


ALU_OPS = {0b000: "ADD", 0b001: "SUB", 0b010: "SHL", 0b011: "SHR",
           0b100: "AND", 0b101: "OR", 0b110: "XOR", 0b111: "NOT"}


class ALU:
    """4 位 ALU，结构级实现。

    操作码（3 位，**8 个码全部占用，没有保留码** → 无法做非法指令检测，
    这是刻意的教学取舍，写在 03_components.md 的"错误输入行为"里）：

        op2 op1 op0
        000 ADD   001 SUB   010 SHL   011 SHR
        100 AND   101 OR    110 XOR   111 NOT

    即：op2=0 为算术组，op2=1 为逻辑组；组内先由 op1 分组、再由 op0 选具体操作。
    选择树 3 级 mux（单级 7 tick）：
        stage1(op0): 算术组 (SUM, SHIFT)、逻辑组 (AND/OR, XOR/NOT)
        stage2(op1): 算术组 (加减 / 移位)、逻辑组 (与或 / 异或非)
        stage3(op2): 算术组 vs 逻辑组
    """

    def __init__(self, c: Circuit, name: str, width: int = 4):
        self.c, self.name, self.width = c, name, width
        self.a = bit_vec(c, f"{name}.a", width)
        self.b = bit_vec(c, f"{name}.b", width)
        self.op = bit_vec(c, f"{name}.op", 3)
        self._build()

    def _build(self):
        c, n, w = self.c, self.name, self.width
        op0, op1, op2 = (x.name for x in self.op)

        n_op1 = c.gate(f"{n}.nop1", "not", [op1])
        n_op2 = c.gate(f"{n}.nop2", "not", [op2])
        n_op0 = c.gate(f"{n}.nop0", "not", [op0])
        sub = c.gate(f"{n}.sub", "and", [n_op2.name, n_op1.name, op0])
        is_add = c.gate(f"{n}.isadd", "and", [n_op2.name, n_op1.name, n_op0.name])
        arith = n_op2  # op2=0 → 算术组

        b_neg = [c.gate(f"{n}.bneg{i}", "not", [bit.name]) for i, bit in enumerate(self.b)]
        b_sel = mux_vec(c, f"{n}.bsel", self.b, b_neg, sub)

        sum_bits, carry_out = ripple_adder(c, f"{n}.add", self.a, b_sel, sub)

        logic = {
            "and": [c.gate(f"{n}.and{i}", "and", [x.name, y.name]) for i, (x, y) in enumerate(zip(self.a, self.b))],
            "or": [c.gate(f"{n}.or{i}", "or", [x.name, y.name]) for i, (x, y) in enumerate(zip(self.a, self.b))],
            "xor": [c.gate(f"{n}.xor{i}", "xor", [x.name, y.name]) for i, (x, y) in enumerate(zip(self.a, self.b))],
            "not": [c.gate(f"{n}.not{i}", "not", [x.name]) for i, x in enumerate(self.a)],
        }

        # 移位：本模块只做"左/右移 1 位"，在硬件里就是重新接线、补 0，**没有门、没有延迟**。
        # 这一点必须明说，否则会变成"给移位假装一个延迟"。
        zero = c.add_wire(f"{n}.zero0", 1, "0")
        shl = [zero] + self.a[:-1]
        shr = self.a[1:] + [zero]

        self.group_a: List[Wire] = []
        self.group_b: List[Wire] = []
        for i in range(w):
            # 算术组：op0 选左/右移（ADD/SUB 共用同一条 sum 线，因为 sub 已由 op0 决定）
            shift = mux2(c, f"{n}.gs.{i}", shl[i], shr[i], self.op[0])
            group_a = mux2(c, f"{n}.ga.{i}", sum_bits[i], shift, self.op[1])

            # 逻辑组：op0 选与/或、异或/非；op1 在两组之间选
            g0 = mux2(c, f"{n}.gb0.{i}", logic["and"][i], logic["or"][i], self.op[0])
            g1 = mux2(c, f"{n}.gb1.{i}", logic["xor"][i], logic["not"][i], self.op[0])
            group_b = mux2(c, f"{n}.gb.{i}", g0, g1, self.op[1])

            self.group_a.append(group_a)
            self.group_b.append(group_b)

        self.result = [mux2(c, f"{n}.y{i}", self.group_a[i], self.group_b[i], self.op[2]) for i in range(w)]

        # 标志位：Z = NOR(result)，N = MSB，C = 进位出（仅算术），V = 同号相加得异号
        self.flag_z = c.gate(f"{n}.flagz", "nor", [x.name for x in self.result])
        self.flag_n = self.result[w - 1]
        amsb, bmsb, smsb = self.a[w - 1], b_sel[w - 1], self.result[w - 1]
        na = c.gate(f"{n}.v.na", "not", [amsb.name])
        nb = c.gate(f"{n}.v.nb", "not", [bmsb.name])
        ns = c.gate(f"{n}.v.ns", "not", [smsb.name])
        t1 = c.gate(f"{n}.v.t1", "and", [amsb.name, bmsb.name, ns.name])
        t2 = c.gate(f"{n}.v.t2", "and", [na.name, nb.name, smsb.name])
        v_raw = c.gate(f"{n}.v.or", "or", [t1.name, t2.name])
        self.flag_v = c.gate(f"{n}.flagv", "and", [v_raw.name, arith.name])
        self.carry = c.gate(f"{n}.flagc", "and", [carry_out.name, arith.name])

    def set(self, a: int, b: int, op: int) -> None:
        w = self.width
        for i in range(w):
            self.c.set_input(self.a[i].name, format(a & ((1 << w) - 1), f"0{w}b")[w - 1 - i])
            self.c.set_input(self.b[i].name, format(b & ((1 << w) - 1), f"0{w}b")[w - 1 - i])
        for i in range(3):
            self.c.set_input(self.op[i].name, format(op, "03b")[2 - i])

    def out(self) -> Tuple[Optional[int], Dict[str, str]]:
        return bits_to_int(join(self.result)), {
            "Z": self.flag_z.bits,
            "C": self.carry.bits,
            "V": self.flag_v.bits,
            "N": self.flag_n.bits,
        }


# ---- 存储器 ------------------------------------------------------------------


class Memory:
    """行为级存储器（RAM/ROM），**显式延迟参数**兑现时序承诺。

    为什么不做门级：真实 SRAM = 6T 位单元 + 灵敏放大器 + 行译码器，门级搭建
    只会得到"逻辑正确、时序虚假"的模型。这里如实说明它是宏单元（macro）。

    错误输入：
      * 地址越界 / 未初始化单元：输出 X，并记录 ERR_ADDR（绝不返回 0）。
      * 写 X：拒绝写入，记录 ERR_X_WRITE（真实 SRAM 会写入亚稳态，更糟）。
      * 写 ROM：记录 ERR_ROM_WRITE。
    """

    def __init__(self, c: Circuit, name: str, addr_width: int, data_width: int,
                 read_latency: int = 10, write_latency: int = 5, rom: bool = False):
        self.c, self.name = c, name
        self.addr_width, self.data_width = addr_width, data_width
        self.read_latency, self.write_latency = read_latency, write_latency
        self.rom = rom
        self.cells: Dict[int, str] = {}
        self.addr = bit_vec(c, f"{name}.addr", addr_width)
        self.din = bit_vec(c, f"{name}.din", data_width)
        self.we = c.add_wire(f"{name}.we", 1, "0")
        self.re = c.add_wire(f"{name}.re", 1, "0")
        self.dout = bit_vec(c, f"{name}.dout", data_width, "X" * data_width)

    def load(self, addr: int, value: int) -> None:
        self.cells[addr] = int_to_bits(value, self.data_width)

    def peek(self) -> str:
        return join(self.dout)

    def cycle(self) -> None:
        """每个 tick 调一次（模拟 SRAM 的同步接口）。"""
        now = self.c.eng.now
        addr = bits_to_int(join(self.addr))
        if addr is None:
            if self.re.bits == "1":
                self.c.eng.trace.append((now, "ERR_X_ADDR", self.name))
                self._read_out("X" * self.data_width)
            return
        if addr not in self.cells:
            if self.re.bits == "1":
                self.c.eng.trace.append((now, "ERR_ADDR", f"{self.name}@{addr}"))
                self._read_out("X" * self.data_width)
        elif self.re.bits == "1":
            self._read_out(self.cells[addr])
        if self.we.bits == "1":
            if self.rom:
                self.c.eng.trace.append((now, "ERR_ROM_WRITE", self.name))
            else:
                self.c.eng.schedule_after(self.write_latency, self._do_write, addr)

    def _read_out(self, bits: str) -> None:
        bits = bits
        self.c.eng.schedule_after(self.read_latency, self._drive_out, bits)

    def _drive_out(self, bits: str) -> None:
        for i, ch in enumerate(split(bits)):
            self.c.set_input(self.dout[i].name, ch)

    def _do_write(self, addr: int) -> None:
        bits = join(self.din)
        if bits_to_int(bits) is None:
            self.c.eng.trace.append((self.c.eng.now, "ERR_X_WRITE", f"{self.name}@{addr}"))
            return
        self.cells[addr] = bits
