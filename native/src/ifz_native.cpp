// ifz_native.cpp —— GDExtension 脚手架（M1 不编译、不接入 project.godot）
//
// 目的：给 ADR 0002 的"原生边界"一个可落地的骨架，证明以下三件事可行：
//   1. 纯 C++ 核心（ifz::）不 include 任何 Godot 头文件，可独立编译与单测；
//   2. 事件队列排序键是 (tick, seq)，与 docs/simulation/02 一致；
//   3. 门延迟表与 data/sim/delays.json 一一对应（改一处必须改三处）。
//
// 构建方式见 native/README.md：
//   - 核心自检：cmake -B build -DIFZ_BUILD_EXTENSION=OFF && ctest --test-dir build
//   - GDExtension：-DIFZ_BUILD_EXTENSION=ON -DGODOT_CPP_DIR=<godot-cpp>
//
// 状态：脚手架。未编译、未验证、未接入；M1 全部走 GDScript（src/sim/）。

#include <cstdint>
#include <cstdio>
#include <memory>
#include <queue>
#include <string>
#include <unordered_map>
#include <vector>

namespace ifz {

// ---------------------------------------------------------------- 三值
// 与 GDScript 侧 SimValue 的三值语义一致：X 表示未知/竞争/亚稳态，不是第三路电平。
enum class Trit : uint8_t { Zero = 0, One = 1, X = 2 };

inline Trit trit_from_char(char c) {
	switch (c) {
		case '0': return Trit::Zero;
		case '1': return Trit::One;
		default: return Trit::X;
	}
}

inline char trit_to_char(Trit t) {
	switch (t) {
		case Trit::Zero: return '0';
		case Trit::One: return '1';
		default: return 'X';
	}
}

// Kleene 三值逻辑：X AND 0 = 0，X OR 1 = 1，其余含 X 均传播 X。
inline Trit kleene_not(Trit a) {
	if (a == Trit::X) return Trit::X;
	return a == Trit::Zero ? Trit::One : Trit::Zero;
}

inline Trit kleene_and(Trit a, Trit b) {
	if (a == Trit::Zero || b == Trit::Zero) return Trit::Zero;
	if (a == Trit::One && b == Trit::One) return Trit::One;
	return Trit::X;
}

inline Trit kleene_or(Trit a, Trit b) {
	if (a == Trit::One || b == Trit::One) return Trit::One;
	if (a == Trit::Zero && b == Trit::Zero) return Trit::Zero;
	return Trit::X;
}

inline Trit gate_xor(Trit a, Trit b) {
	if (a == Trit::X || b == Trit::X) return Trit::X;
	return a != b ? Trit::One : Trit::Zero;
}

// ---------------------------------------------------------------- 延迟表
// 唯一来源：data/sim/delays.json 的 gate_delay 段（1 tick = 1 个反相器延迟）。
// 这里是"编译期镜像"，不是第二份真相；CI 应比对 JSON 与本表（ADR 0002 §2.2 第 5 条）。
inline int gate_delay(const std::string &kind) {
	if (kind == "buf") return 1;
	if (kind == "not") return 1;
	if (kind == "nand") return 2;
	if (kind == "nor") return 2;
	if (kind == "and") return 3;
	if (kind == "or") return 3;
	if (kind == "xor") return 4;
	if (kind == "xnor") return 5;
	return 3; // 与 GDScript 的 fallback 一致；未知门应在构建期被拒绝
}

inline Trit eval_gate(const std::string &kind, Trit a, Trit b = Trit::X) {
	if (kind == "buf") return a;
	if (kind == "not") return kleene_not(a);
	if (kind == "and") return kleene_and(a, b);
	if (kind == "or") return kleene_or(a, b);
	if (kind == "xor") return gate_xor(a, b);
	if (kind == "nand") return kleene_not(kleene_and(a, b));
	if (kind == "nor") return kleene_not(kleene_or(a, b));
	if (kind == "xnor") {
		Trit x = gate_xor(a, b);
		return x == Trit::X ? Trit::X : kleene_not(x);
	}
	return Trit::X;
}

// ---------------------------------------------------------------- 事件引擎
struct Event {
	int64_t tick = 0;
	uint64_t seq = 0;
	// 闭包不能进存档；用"句柄 + 参数"表达（见 docs/simulation/07 Snapshot.timers）。
	int handler = 0;
	std::string arg_a;
	std::string arg_b;
};

// priority_queue 是最大堆，这里把比较反向，得到按 (tick, seq) 升序的最小堆。
struct EventLess {
	bool operator()(const Event &l, const Event &r) const {
		if (l.tick != r.tick) return l.tick > r.tick;
		return l.seq > r.seq;
	}
};

class SimEngine {
public:
	explicit SimEngine(int64_t max_events_per_tick = 20000) : max_events_per_tick_(max_events_per_tick) {}

	int64_t now() const { return now_; }
	int64_t pending() const { return static_cast<int64_t>(queue_.size()); }
	const std::string &last_error() const { return last_error_; }

	void schedule_after(int64_t delay, int handler, const std::string &a = "", const std::string &b = "") {
		Event ev;
		ev.tick = now_ + (delay < 0 ? 0 : delay);
		ev.seq = next_seq_++;
		ev.handler = handler;
		ev.arg_a = a;
		ev.arg_b = b;
		queue_.push(ev);
	}

	// 返回 false 表示失败：last_error_ 给出原因（对应 IFZ_E_LIMIT / 自激环）。
	bool step(int64_t ticks) {
		const int64_t end = now_ + (ticks < 0 ? 0 : ticks);
		int64_t tick_events = 0;
		while (!queue_.empty() && queue_.top().tick <= end) {
			Event ev = queue_.top();
			queue_.pop();
			if (ev.tick < now_) {
				last_error_ = "event time moved backwards (seq/tick ordering violated)";
				return false;
			}
			if (ev.tick != now_) {
				now_ = ev.tick;
				tick_events = 0;
			}
			++tick_events;
			if (tick_events > max_events_per_tick_) {
				last_error_ = "max events per tick exceeded (possible combinational loop)";
				return false;
			}
			if (!dispatch(ev)) return false;
		}
		now_ = end;
		return true;
	}

	// 求值回调，由电路实现覆盖（脚手架留空）。
	virtual bool dispatch(const Event &ev) {
		(void)ev;
		return true;
	}

	// 生产实现需为纯虚；脚手架保留虚函数以便自检。
	virtual ~SimEngine() = default;

private:
	std::priority_queue<Event, std::vector<Event>, EventLess> queue_;
	int64_t now_ = 0;
	uint64_t next_seq_ = 0;
	int64_t max_events_per_tick_;
	std::string last_error_;
};

} // namespace ifz

// ---------------------------------------------------------------- 独立自检（不链接 Godot）
#ifdef IFZ_SELFTEST
static int ifz_run_selftest() {
	using namespace ifz;
	struct Case {
		const char *kind;
		char a;
		char b;
		char want;
	};
	const Case cases[] = {
		{"and", '0', '0', '0'}, {"and", '0', 'X', '0'}, {"and", '1', '1', '1'}, {"and", '1', 'X', 'X'},
		{"or", '0', '0', '0'},  {"or", '1', 'X', '1'},  {"or", 'X', '0', 'X'},
		{"xor", '0', '1', '1'}, {"xor", '1', '1', '0'}, {"xor", 'X', '0', 'X'},
		{"not", '0', 'X', '1'}, {"not", 'X', 'X', 'X'},
	};
	int failures = 0;
	for (const Case &c : cases) {
		Trit got = eval_gate(c.kind, trit_from_char(c.a), trit_from_char(c.b));
		if (trit_to_char(got) != c.want) {
			std::fprintf(stderr, "FAIL %s(%c,%c) want %c got %c\n", c.kind, c.a, c.b, c.want, trit_to_char(got));
			++failures;
		}
	}

	// 延迟表抽查：必须与 data/sim/delays.json 一致
	if (gate_delay("not") != 1 || gate_delay("nand") != 2 || gate_delay("and") != 3 ||
		gate_delay("xor") != 4 || gate_delay("xnor") != 5) {
		std::fprintf(stderr, "FAIL gate delay table does not match data/sim/delays.json\n");
		++failures;
	}

	// (tick, seq) 全序：同 tick 内先入先出，且不丢事件
	SimEngine eng;
	eng.schedule_after(2, 1);
	eng.schedule_after(1, 2);
	eng.schedule_after(2, 3);
	if (!eng.step(2)) {
		std::fprintf(stderr, "FAIL engine step: %s\n", eng.last_error().c_str());
		++failures;
	}
	if (eng.now() != 2 || eng.pending() != 0) {
		std::fprintf(stderr, "FAIL engine state: now=%lld pending=%lld\n",
				static_cast<long long>(eng.now()), static_cast<long long>(eng.pending()));
		++failures;
	}

	std::printf("ifz_native selftest: %s (%d failures)\n", failures == 0 ? "PASS" : "FAIL", failures);
	return failures == 0 ? 0 : 1;
}
#endif

// ---------------------------------------------------------------- Godot 侧（仅在 IFZ_WITH_GODOT_CPP 下编译）
#ifdef IFZ_WITH_GODOT_CPP
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/string.hpp>

#define IFZ_ERR_NOT_IMPLEMENTED 6 // 编号沿用 docs/simulation/07 §5 的错误码表

namespace ifz_godot {

using namespace godot;

// 边界铁律（docs/simulation/07 §3）：本类只做类型转换与调用，不含算法。
class IfzSim : public RefCounted {
	GDCLASS(IfzSim, RefCounted)

private:
	std::unique_ptr<ifz::SimEngine> engine_;
	std::unordered_map<std::string, ifz::Trit> wires_;

protected:
	static void _bind_methods() {
		ClassDB::bind_method(D_METHOD("reset", "world_seed"), &IfzSim::reset);
		ClassDB::bind_method(D_METHOD("step_ticks", "ticks"), &IfzSim::step_ticks);
		ClassDB::bind_method(D_METHOD("probe", "wire"), &IfzSim::probe);
		ClassDB::bind_method(D_METHOD("pending"), &IfzSim::pending);
		ClassDB::bind_method(D_METHOD("last_error"), &IfzSim::last_error);
	}

public:
	void reset(int64_t world_seed) {
		(void)world_seed;
		engine_ = std::make_unique<ifz::SimEngine>();
		wires_.clear();
	}

	// 返回实际推进到的 tick；本脚手架未实现 budget_us（生产实现见 07 §3）。
	int64_t step_ticks(int64_t ticks) {
		engine_->step(ticks);
		return engine_->now();
	}

	String probe(const String &wire) {
		auto it = wires_.find(std::string(wire.utf8().get_data()));
		if (it == wires_.end()) return String("X");
		return String::utf8(it->second == ifz::Trit::Zero ? "0" : (it->second == ifz::Trit::One ? "1" : "X"));
	}

	int64_t pending() { return engine_->pending(); }

	String last_error() { return String::utf8(engine_->last_error().c_str()); }

	int64_t not_implemented_code() { return IFZ_ERR_NOT_IMPLEMENTED; }
};

static void ifz_register_types() {
	ClassDB::register_class<IfzSim>();
}

} // namespace ifz_godot

extern "C" GDE_EXPORT void ifz_library_init(godot::ModuleInitializationLevel p_level) {
	if (p_level == godot::MODULE_INITIALIZATION_LEVEL_SCENE) {
		ifz_godot::ifz_register_types();
	}
}

extern "C" GDE_EXPORT void ifz_library_deinit(godot::ModuleInitializationLevel p_level) {
	(void)p_level;
}
#endif

// ---------------------------------------------------------------- 独立入口
#ifdef IFZ_SELFTEST
int main() { return ifz_run_selftest(); }
#endif
