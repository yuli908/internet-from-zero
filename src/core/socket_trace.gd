extends RefCounted

## CH15.2 句柄/帧编号模型：把 data 里的 socket 调用序列翻译成
## handles（fd→socket 句柄→调用编号）与 frames（frame_id→fd→call_n→方向）。
## 生产：`run(calls)`（本文件）。
## 消费：`tests/test_ch15.gd` 用它生成 T15.2-1 的接口产物；
## gate 侧比对仍走 `src/core/net_lab_kit.gd::_table`（:82-165）。
## 数据源：2026-11-05 本机 loopback 真实捕获（Python socket，客户端 fd=332、12 B 原样
## 回环），原始调用与字节冻结在 `data/labs/ch15_labs.json::socket_api.capture`；
## 本文件只做「捕获 → 四调用归一化 → handles/frames」的编号，不再是无源模型。

const INBOUND_OPS := ["recv"]

static func run(calls: Array) -> Dictionary:
	var handles: Array = []
	var index_by_fd: Dictionary = {}
	var frames: Array = []
	for raw in calls:
		if not (raw is Dictionary):
			return {"ok": false, "error": "call 不是对象"}
		var call: Dictionary = raw
		var n := int(call.get("n", 0))
		var fd := int(call.get("fd", -1))
		var op := str(call.get("op", ""))
		if n <= 0 or fd < 0 or op.is_empty():
			return {"ok": false, "error": "call 缺 n/fd/op：%s" % str(call)}
		if not index_by_fd.has(fd):
			index_by_fd[fd] = handles.size()
			handles.append({"fd": fd, "socket_id": "s%d" % (handles.size() + 1), "calls": []})
		(handles[int(index_by_fd[fd])]["calls"] as Array).append({"n": n, "op": op})
		frames.append({
			"frame_id": frames.size() + 1,
			"fd": fd,
			"call_n": n,
			"dir": "in" if INBOUND_OPS.has(op) else "out",
		})
	var unmatched: Array = []
	for f in frames:
		var fd := int((f as Dictionary).get("fd", -1))
		var found := false
		if index_by_fd.has(fd):
			for c in (handles[int(index_by_fd[fd])]["calls"] as Array):
				if int((c as Dictionary).get("n", -1)) == int((f as Dictionary).get("call_n", -2)):
					found = true
					break
		if not found:
			unmatched.append(f)
	return {
		"ok": true,
		"handles": handles,
		"frames": frames,
		"unmatched_frames": unmatched,
	}
