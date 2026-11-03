"""门级 / 信号层参考实现（三值逻辑 + 确定性事件调度）。

本模块只做两件事，并且把这件事做"真"：
1. 用**整数 tick** 推进时间，事件按 (时刻, 全局自增序号) 全序出队，因此同输入必然同输出。
2. 用**传输延迟（transport delay）**传播：输入每变化一次，就按该门自身的延迟产生一次求值，
   而不是"最后一次变化覆盖之前所有变化"。这样组合逻辑的冒险（hazard）会自然出现，
   而不是被引擎"抹平"。

约定
----
* 位串一律 **MSB 在前**，例如 "1010" 表示 4 位值 10；下标 0 是最低位。
* 三值：'0'、'1'、'X'。X 表示"未知/竞争/亚稳态"，不是第三路电平。
  高阻 Z 不在本层建模（总线竞争由总线仲裁层显式处理，见 04/03 文档）。
* 1 tick = 一个归一化反相器延迟（文档里约等于 50 ps 的"教学单位"，不是物理承诺）。
* 只用整数运算；禁止浮点进入仿真状态（浮点会破坏跨平台可复现）。

延迟表（归一化，非物理）
------------------------
not=1, nand2=2, nor2=2, and2=3, or2=3, xor2=4, xnor2=5, buf=1
这些数字来自"CMOS 里 AND 实际是 NAND+INV"的常识性比例，只用于教学与性能估算，
**不得**被当作真实工艺库时序。
"""

from __future__ import annotations

import heapq
import itertools
from dataclasses import dataclass, field
from typing import Callable, Dict, Iterable, List, Optional, Tuple

X = "X"
ZERO = "0"
ONE = "1"

# 归一化门延迟（tick）。文档 03_components.md 引用同一张表，改这里必须同步改文档。
GATE_DELAY: Dict[str, int] = {
    "buf": 1,
    "not": 1,
    "nand": 2,
    "nor": 2,
    "and": 3,
    "or": 3,
    "xor": 4,
    "xnor": 5,
}

# ---- 三值逻辑（Kleene 强完备逻辑） ------------------------------------------
# 说明：X AND 0 = 0、X OR 1 = 1 是"可确定的结论"，其余含 X 的组合结果为 X。
_KLEENE: Dict[str, Dict[Tuple[str, str], str]] = {
    "and": {
        ("0", "0"): "0", ("0", "1"): "0", ("0", "X"): "0",
        ("1", "0"): "0", ("1", "1"): "1", ("1", "X"): X,
        ("X", "0"): "0", ("X", "1"): X, ("X", "X"): X,
    },
    "or": {
        ("0", "0"): "0", ("0", "1"): "1", ("0", "X"): X,
        ("1", "0"): "1", ("1", "1"): "1", ("1", "X"): "1",
        ("X", "0"): X, ("X", "1"): "1", ("X", "X"): X,
    },
    "xor": {
        ("0", "0"): "0", ("0", "1"): "1", ("0", "X"): X,
        ("1", "0"): "1", ("1", "1"): "0", ("1", "X"): X,
        ("X", "0"): X, ("X", "1"): X, ("X", "X"): X,
    },
}

_NEG = {"0": "1", "1": "0", X: X}


def tri_not(bits: str) -> str:
    return "".join(_NEG[c] for c in bits)


def tri_bin(kind: str, a: str, b: str) -> str:
    """逐位二元三值运算。要求 a、b 等宽。"""
    if len(a) != len(b):
        raise ValueError(f"位宽不匹配: {len(a)} vs {len(b)}")
    table = _KLEENE[kind]
    return "".join(table[(x, y)] for x, y in zip(a, b))


def tri_reduce(kind: str, bits: str) -> str:
    """归约运算：AND/OR/XOR 全部位。"""
    acc = bits[0]
    for c in bits[1:]:
        acc = tri_bin(kind, acc, c)[0] if len(acc) == 1 else _KLEENE[kind][(acc, c)]
    return acc


def int_to_bits(value: int, width: int) -> str:
    if value < 0:
        value &= (1 << width) - 1
    if value >= (1 << width):
        raise ValueError(f"{value} 超出 {width} 位范围")
    return format(value, f"0{width}b")


def bits_to_int(bits: str) -> Optional[int]:
    """任一位为 X 则返回 None（调用方必须显式处理未知值，不得静默当 0）。"""
    if X in bits:
        return None
    return int(bits, 2)


def get_bit(bits: str, i: int) -> str:
    """i=0 为最低位。"""
    return bits[len(bits) - 1 - i]


def is_unknown(bits: str) -> bool:
    return X in bits


# ---- 事件引擎 ----------------------------------------------------------------


@dataclass(order=True)
class _Event:
    time: int
    seq: int
    fn: Callable = field(compare=False)
    args: tuple = field(compare=False, default=())


class SimLimitExceeded(RuntimeError):
    """单 tick 事件数超限：通常意味着组合环振荡或零延迟自激。"""


class Engine:
    """确定性离散事件引擎。

    关键约束（实现方必须遵守，见 02_determinism.md）：
    * 队列排序键 = (time, seq)，seq 在入队时自增，不允许按对象地址排序。
    * 一个 tick 内的事件数上限可配；超限即报错，绝不静默丢弃。
    * 状态只存在于整数字段与位串，序列化后逐字节可复现。
    """

    def __init__(self, max_events_per_tick: int = 20_000):
        self.now = 0
        self._heap: List[_Event] = []
        self._seq = itertools.count()
        self.max_events_per_tick = max_events_per_tick
        self._tick_event_count = 0
        self.event_count = 0
        # 可观测点：引擎级日志。生产实现应写入环形缓冲并可按 trace 级别开关。
        self.trace: List[Tuple[int, str, str]] = []

    def schedule(self, time: int, fn: Callable, *args) -> None:
        if time < self.now:
            raise ValueError(f"不允许调度到过去: {time} < {self.now}")
        heapq.heappush(self._heap, _Event(time, next(self._seq), fn, args))

    def schedule_after(self, delay: int, fn: Callable, *args) -> None:
        self.schedule(self.now + delay, fn, *args)

    def run_until(self, t_end: int) -> None:
        while self._heap and self._heap[0].time <= t_end:
            self._pop()

    def run_events(self) -> None:
        """清空队列（用于组合逻辑收敛）。带时钟的电路不要用这个。"""
        while self._heap:
            self._pop()

    def _pop(self) -> None:
        ev = heapq.heappop(self._heap)
        if ev.time < self.now:
            raise AssertionError("事件时间倒退，调度器损坏")
        if ev.time != self.now:
            self.now = ev.time
            self._tick_event_count = 0
        self._tick_event_count += 1
        self.event_count += 1
        if self._tick_event_count > self.max_events_per_tick:
            raise SimLimitExceeded(
                f"tick {self.now} 事件数超过 {self.max_events_per_tick}，疑似组合环/零延迟自激"
            )
        ev.fn(*ev.args)

    @property
    def pending(self) -> int:
        return len(self._heap)


# ---- 线网与门 ----------------------------------------------------------------


class Wire:
    __slots__ = ("name", "bits", "last_change", "prev", "listeners")

    def __init__(self, name: str, bits: str):
        self.name = name
        self.bits = bits
        self.prev = bits
        self.last_change = -(1 << 30)  # 远早于 0，保证首次不触发 setup 违例
        self.listeners: List[Callable[[str, int], None]] = []


class Circuit:
    """一个组合/时序电路容器。

    可观测点（给 UI/调试用）：
      * ``probe(name)`` 读当前位串；
      * ``history`` 记录每次变化 (tick, wire, 旧值, 新值)，可导出回放；
      * ``glitches`` 由 ``watch_glitch`` 显式开启统计，避免生产环境全网记录。
    """

    def __init__(self, name: str = "circuit", max_events_per_tick: int = 20_000):
        self.name = name
        self.eng = Engine(max_events_per_tick)
        self.wires: Dict[str, Wire] = {}
        self.history: List[Tuple[int, str, str, str]] = []
        self.glitches: List[Tuple[int, str, str]] = []
        self._watch: set = set()
        self._clock_handles: List[_Clock] = []

    # -- 构建 --
    def add_wire(self, name: str, width: int = 1, init: Optional[str] = None) -> Wire:
        if name in self.wires:
            raise ValueError(f"线网重复: {name}")
        bits = init if init is not None else X * width
        if len(bits) != width:
            raise ValueError(f"{name} 初始化位宽错误: {len(bits)} != {width}")
        w = Wire(name, bits)
        self.wires[name] = w
        return w

    def probe(self, name: str) -> str:
        return self.wires[name].bits

    def set_input(self, name: str, bits: str, delay: int = 0) -> None:
        """外部驱动（键盘/上级模块）。delay>0 表示信号源本身的建立时间。"""
        self.eng.schedule_after(delay, self._drive, name, bits)

    def _drive(self, name: str, bits: str) -> None:
        self._write(name, bits)

    def _write(self, name: str, bits: str) -> None:
        w = self.wires[name]
        if w.bits == bits:
            return
        old = w.bits
        w.prev = old
        w.bits = bits
        w.last_change = self.eng.now
        self.history.append((self.eng.now, name, old, bits))
        if name in self._watch:
            self.glitches.append((self.eng.now, name, bits))
        for cb in tuple(w.listeners):
            cb(old, self.eng.now)

    def watch_glitch(self, name: str) -> None:
        self._watch.add(name)

    def bind(self, src: str, dst: str, delay: int = 0) -> None:
        """把 src 的每次变化复制到 dst（等价于一段延迟为 delay 的连线）。"""
        def cb(old: str, t: int) -> None:
            self.eng.schedule(t + delay, self._write, dst, self.wires[src].bits)

        self.wires[src].listeners.append(cb)
        self.eng.schedule(self.eng.now, self._write, dst, self.wires[src].bits)

    def gate(self, name: str, kind: str, inputs: Iterable[str], delay: Optional[int] = None) -> Wire:
        """创建门。输出线网名 = name。"""
        ins = list(inputs)
        if kind not in GATE_DELAY:
            raise ValueError(f"未知门类型: {kind}")
        d = GATE_DELAY[kind] if delay is None else delay
        out_width = len(self.wires[ins[0]].bits)
        for i in ins:
            if len(self.wires[i].bits) != out_width:
                raise ValueError(f"门 {name} 输入位宽不一致")
        if kind == "not" and len(ins) != 1:
            raise ValueError("not 只接受 1 个输入")
        w = self.add_wire(name, out_width)

        def evaluate(old: str, t: int) -> None:
            # 传输延迟：每一次输入变化都在 t+d 时刻独立求值一次。
            self.eng.schedule(t + d, compute, t)

        def compute(t_arrive: int) -> None:
            vals = [self.wires[i].bits for i in ins]
            self._write(name, _eval(kind, vals))

        for i in ins:
            self.wires[i].listeners.append(evaluate)
        # 初始求值（当前 tick 的 delta 周期）
        self.eng.schedule(self.eng.now, compute, self.eng.now)
        return w

    # -- 时序原语 --
    def dff(
        self,
        name: str,
        d: str,
        clk: str,
        reset: Optional[str] = None,
        setup: int = 2,
        hold: int = 1,
        clk_to_q: int = 2,
        init: str = "0",
    ) -> Wire:
        """上升沿 D 触发器（原语级，非门级搭建）。

        真实实现必须承认：这是**行为级原语**。理由写在 03_components.md：
        用门级搭建主从触发器可以，但在教学里会引入 20+ 个门的噪声，
        且物理上的建立/保持窗口本来就不是"用门能干净表达"的东西。
        规则：
          * D 在时钟上升沿前 setup tick 内变化 → Q 输出 X（亚稳态），并记录 METASTABLE。
          * 时钟边沿后 hold tick 内变化 → 同样 X。
          * 异步复位高有效，优先级高于时钟。
        """
        q = self.add_wire(name, 1, init) if name not in self.wires else self.wires[name]
        if len(q.bits) != 1:
            raise ValueError(f"DFF 输出必须是 1 位: {name}")
        state = {"edge_t": -(1 << 30)}

        def on_clk(old: str, t: int) -> None:
            if self.wires[clk].bits != "1":
                return
            state["edge_t"] = t
            if reset is not None and self.wires[reset].bits == "1":
                self.eng.schedule_after(clk_to_q, self._write, name, "0")
                return
            dw = self.wires[d]
            # setup 违例：D 在边沿前 setup 窗口内变过
            setup_bad = (t - dw.last_change) < setup
            val = X if (setup_bad or dw.bits == X) else dw.bits
            if setup_bad:
                self.eng.trace.append((t, "METASTABLE", f"{name} setup"))
            self.eng.schedule_after(clk_to_q, self._write, name, val)

        def on_d(_old: str, t: int) -> None:
            # hold 违例：边沿后 hold 窗口内 D 又变。真实器件是概率性亚稳态，
            # 这里确定性地输出 X，并把事件写进 trace，绝不假装"采到了正确值"。
            if self.wires[clk].bits == "1" and (t - state["edge_t"]) < hold:
                self.eng.trace.append((t, "METASTABLE", f"{name} hold"))
                self.eng.schedule_after(clk_to_q, self._write, name, X)

        self.wires[clk].listeners.append(on_clk)
        self.wires[d].listeners.append(on_d)
        return q

    def clock(self, name: str, period: int = 10, phase: int = 0, duty: int = 5) -> "Clock":
        """周期时钟。period 必须为偶数（半周期是整数 tick，禁止浮点）。"""
        if period % 2 != 0:
            raise ValueError("period 必须是偶数，保证半周期为整数 tick")
        clk = _Clock(self, name, period, phase, duty)
        self._clock_handles.append(clk)
        clk.start()
        return clk

    # -- 推进 --
    def run(self, ticks: int) -> None:
        self.eng.run_until(self.eng.now + ticks)

    def run_until(self, t: int) -> None:
        self.eng.run_until(t)

    def idle_to(self, t: int) -> None:
        """把"当前时刻"精确推进到 t（插入一个空事件），便于安排边界用例。"""
        self.eng.schedule(t, lambda: None)
        self.eng.run_until(t)

    def settle(self, max_ticks: int = 1000) -> int:
        """跑到队列空（无时钟时应立即收敛）。返回消耗的 tick 数。"""
        start = self.eng.now
        self.eng.run_events()
        return self.eng.now - start

    # -- 存档 --
    def snapshot(self) -> dict:
        """仅在**队列为空**（静止 tick）时调用，否则存档不完整。

        这是刻意的限制：带时钟的电路永远有 pending 事件，全量序列化事件队列
        会把回放格式与引擎实现绑死。生产实现的做法见 02_determinism.md：
        存档 = 静止快照 + 从上一个静止点开始的操作日志（输入事件），回放时重跑。
        """
        if self.eng.pending:
            raise RuntimeError(f"队列非空（{self.eng.pending} 事件），拒绝存档")
        return {
            "format": "ifz-circuit/1",
            "name": self.name,
            "tick": self.eng.now,
            "wires": {n: self.wires[n].bits for n in sorted(self.wires)},
        }

    def restore(self, snap: dict) -> None:
        if snap["format"] != "ifz-circuit/1":
            raise ValueError("存档格式不兼容")
        if self.eng.pending:
            raise RuntimeError("恢复前必须清空队列")
        for n, bits in snap["wires"].items():
            if n in self.wires:
                self._write(n, bits)
        self.eng.now = snap["tick"]


def _eval(kind: str, vals: List[str]) -> str:
    if kind == "buf":
        return vals[0]
    if kind == "not":
        return tri_not(vals[0])
    if kind in ("and", "or", "xor"):
        acc = vals[0]
        for v in vals[1:]:
            acc = tri_bin(kind, acc, v)
        return acc
    if kind in ("nand", "nor", "xnor"):
        base = {"nand": "and", "nor": "or", "xnor": "xor"}[kind]
        acc = vals[0]
        for v in vals[1:]:
            acc = tri_bin(base, acc, v)
        return tri_not(acc)
    raise ValueError(kind)


class _Clock:
    def __init__(self, c: Circuit, name: str, period: int, phase: int, duty: int):
        self.c = c
        self.name = name
        self.period = period
        self.duty = duty
        self.high_time = duty
        self.low_time = period - duty
        self.c.add_wire(name, 1, "0")
        self.phase = phase
        self.periods = 0

    def start(self) -> None:
        self.c.eng.schedule(self.phase, self._rise)

    def _rise(self) -> None:
        self.c._write(self.name, "1")
        self.c.eng.schedule_after(self.high_time, self._fall)

    def _fall(self) -> None:
        self.c._write(self.name, "0")
        self.periods += 1
        self.c.eng.schedule_after(self.low_time, self._rise)


# ---- 冒险的可观测性 ----------------------------------------------------------


def measure_settle(c: Circuit, outputs: Iterable[str], from_tick: int) -> int:
    """组合电路：从 from_tick 的输入变化，到所有输出最后一次变化的 tick 数。

    这就是玩家在示波器上看到的"最坏路径延迟"。只对无时钟电路有效。
    """
    c.eng.run_events()
    return max(c.wires[o].last_change for o in outputs) - from_tick
