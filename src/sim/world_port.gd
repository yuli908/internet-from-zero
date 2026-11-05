extends RefCounted

## F1 出网（19 §2.10）：本机 loopback 真 TCP 桥。
##
## 真值只来自真实 socket：listen(127.0.0.1:0) → connect → put_data → take_connection
## → get_data。数据只声明输入串与上限，不写死任何字节；每行同时记两个读取点：
##   `sent_hex`    —— 发送侧写进 socket 的字节（客户端 put_data 前的那份 buffer）
##   `local_bytes` —— 本机终端（服务端）从 socket 读到的字节
## 两者必须是同一份流，且 `input` 的 UTF-8 字节数与之相符；不是「打印两次」。
##
## 运行前提：只监听 127.0.0.1（数据里固定 7777，纯回环；端口 0 则系统分配），不碰公网
## 网卡，不需要管理员，不需要防火墙放行（Windows 防火墙不拦 loopback）。若 7777 被别的
## 进程占用，listen 返回 3 并在 detail 里说明——那是环境问题，需用户侧让端口，不改系统设置。

const E_UNCONNECTED := 3
const E_TABLE_CELL := 7

const HOST := "127.0.0.1"
const MAX_RUNS := 8
const TIMEOUT_MS := 3000

## 跑一组真实收发。返回 {ok, rows, meta, detail}。
static func deliver(cfg: Dictionary) -> Dictionary:
	var runs: Array = cfg.get("runs", [])
	if runs.is_empty() or runs.size() > MAX_RUNS:
		return {"ok": false, "code": E_TABLE_CELL,
			"detail": "runs 必须 1..%d 条（当前 %d）" % [MAX_RUNS, runs.size()]}
	var port_cfg := int(cfg.get("port", 0))
	var srv := TCPServer.new()
	var err := srv.listen(port_cfg, HOST)
	if err != OK:
		return {"ok": false, "code": E_UNCONNECTED,
			"detail": "listen %s:%d 失败 err=%d（端口被占用或权限问题，需用户侧处理）"
				% [HOST, port_cfg, err]}
	var port := srv.get_local_port()
	var rows: Array = []
	for raw in runs:
		var one: Dictionary = raw
		var text := str(one.get("input", ""))
		var payload := text.to_utf8_buffer()
		var t0 := Time.get_ticks_usec()
		var cli := StreamPeerTCP.new()
		var cerr := cli.connect_to_host(HOST, port)
		if cerr != OK:
			srv.stop()
			return {"ok": false, "code": E_UNCONNECTED,
				"detail": "connect %s:%d 失败 err=%d" % [HOST, port, cerr]}
		var acc: StreamPeerTCP = null
		var got := PackedByteArray()
		var sent := false
		var deadline := Time.get_ticks_msec() + TIMEOUT_MS
		while Time.get_ticks_msec() < deadline:
			cli.poll()
			if not sent and cli.get_status() == StreamPeerTCP.STATUS_CONNECTED:
				cli.set_no_delay(true)
				if cli.put_data(payload) != OK:
					srv.stop()
					return {"ok": false, "code": E_UNCONNECTED, "detail": "put_data 失败"}
				sent = true
			if acc == null and srv.is_connection_available():
				acc = srv.take_connection()
			if acc != null and acc.get_available_bytes() > 0:
				var res: Array = acc.get_data(acc.get_available_bytes())
				got.append_array(res[1] as PackedByteArray)
			if acc != null and got.size() >= payload.size():
				break
			OS.delay_msec(1)
		var us := int(Time.get_ticks_usec() - t0)
		cli.disconnect_from_host()
		if acc != null:
			acc.disconnect_from_host()
		if got.size() < payload.size():
			srv.stop()
			return {"ok": false, "code": E_UNCONNECTED,
				"detail": "第 %d 次 loopback 超时：本机只读到 %d B，发出 %d B"
					% [rows.size() + 1, got.size(), payload.size()]}
		rows.append({
			"run": str(one.get("run", "r%d" % (rows.size() + 1))),
			"input": text,
			"sent_hex": payload.hex_encode(),
			"local_bytes": got.slice(0, payload.size()).hex_encode(),
			"deliver_us": us,
		})
	srv.stop()
	return {
		"ok": true,
		"rows": rows,
		"meta": {
			"transport": "tcp-loopback",
			"host": HOST,
			"port": port,
			"pid": OS.get_process_id(),
			"captured_at": Time.get_datetime_string_from_system(),
		},
		"detail": "本机 loopback 真 TCP：%d 次收发已闭环（端口 %d）" % [rows.size(), port],
	}
