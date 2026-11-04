class_name SimDff
extends RefCounted

## D16 D 触发器（行为级原语，语义对齐 docs/simulation/ref/simcore/logic.py::Circuit.dff）：
##  - 上升沿（clk 0/X→1）采样 D，clk→Q = 2 tick；
##  - setup 违例：D 在边沿前 setup tick 内变过 → Q=X + METASTABLE("setup")；
##  - hold 违例：边沿后 hold tick 内 D 又变 → Q=X + METASTABLE("hold")；
##  - RESET 异步高有效，在上升沿时优先于采样，Q 在 clk→Q 后为 0；
##  - D 本身为 X → 采样后 Q=X（不记 METASTABLE，与参考实现一致）。
## 这是行为级原语而非门级展开：门级主从触发器在教学里只会引入 20+ 门噪声。

const SETUP := 2
const HOLD := 1
const CLK_TO_Q := 2

var sim: SimCircuit
var name := ""
var d_name := ""
var clk_name := ""
var reset_name := ""
var setup := SETUP
var hold := HOLD
var clk_to_q := CLK_TO_Q
var edge_t := -1073741824

static func attach(p_sim: SimCircuit, p_name: String, p_d: String, p_clk: String,
		p_reset: String = "", p_setup: int = SETUP, p_hold: int = HOLD,
		p_clk_to_q: int = CLK_TO_Q, p_init: String = SimValue.X) -> SimDff:
	var d := SimDff.new()
	d.sim = p_sim
	d.name = p_name
	d.d_name = p_d
	d.clk_name = p_clk
	d.reset_name = p_reset
	d.setup = p_setup
	d.hold = p_hold
	d.clk_to_q = p_clk_to_q
	p_sim.add_wire(p_name, p_init)
	if not p_reset.is_empty():
		p_sim.add_wire(p_reset, SimValue.ZERO)
	p_sim.wires[p_clk]["listeners"].append(Callable(d, "_on_clk"))
	p_sim.wires[p_d]["listeners"].append(Callable(d, "_on_d"))
	return d

func _on_clk(old: String, t: int) -> void:
	var rising := sim.probe(clk_name) == SimValue.ONE
	if sim.sink != null:
		sim.sink.record(t, "L3", "EDGE", clk_name, {"edge": "rise" if rising else "fall", "from": old})
	if not rising:
		return
	edge_t = t
	var d_now := sim.probe(d_name)
	if not reset_name.is_empty() and sim.probe(reset_name) == SimValue.ONE:
		if sim.sink != null:
			sim.sink.record(t, "L3", "SAMPLE", name, {"d": d_now, "q": SimValue.ZERO, "reset": true})
		sim.eng.schedule_after(clk_to_q, Callable(sim, "_write"), [name, SimValue.ZERO])
		return
	var dw: Dictionary = sim.wires[d_name]
	var setup_bad: bool = (t - int(dw["last_change"])) < setup
	var val := SimValue.X if (setup_bad or str(dw["bits"]) == SimValue.X) else str(dw["bits"])
	if sim.sink != null:
		sim.sink.record(t, "L3", "SAMPLE", name, {"d": d_now, "q": val, "meta": setup_bad})
	if setup_bad:
		sim.note_metastable(t, name, "setup")
	sim.eng.schedule_after(clk_to_q, Callable(sim, "_write"), [name, val])

func _on_d(_old: String, t: int) -> void:
	if sim.probe(clk_name) != SimValue.ONE:
		return
	if (t - edge_t) < hold:
		sim.note_metastable(t, name, "hold")
		sim.eng.schedule_after(clk_to_q, Callable(sim, "_write"), [name, SimValue.X])
