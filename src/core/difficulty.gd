class_name Difficulty
extends RefCounted

## M4 · 冒险三档预留（`docs/simulation/02_determinism.md` §5）。
## M4 只保留"名字 + 校验 + 默认值"；`SYNC` 采样吸收、`MASK` 脉冲过滤属 M5，
## 本轮不改 `SimCircuit` 的任何求值/采样行为。

const EXPLAIN := "EXPLAIN"
const SYNC := "SYNC"
const MASK := "MASK"

static func names() -> Array:
	return [EXPLAIN, SYNC, MASK]

static func is_valid(v: String) -> bool:
	return names().has(v)

static func normalize(v: String) -> String:
	## 合法值原样返回；缺失/未知值一律回 `EXPLAIN`（默认档）。
	return v if is_valid(v) else EXPLAIN
