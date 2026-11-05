#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""CH15.2 句柄映射的真实捕获脚本（本机 loopback）。

运行前提
--------
- Python 3（标准库即可，无第三方依赖）。
- **只需本机回环**：服务端 bind 在 127.0.0.1:0（系统分配端口），不监听公网网卡。
- **不需要管理员权限**，**不需要 Npcap / WinPcap**，也不会触发防火墙放行弹窗
  （Windows 防火墙不拦 loopback；若某些安全软件仍弹窗，拒绝即可，不影响回环）。
- 记录的是 socket API 级的真实事实：fd、调用顺序、收发字节；不是 pcap 报文头。

重跑规则（重要）
----------------
fd（句柄号）、端口、pid、时间戳每次运行都会变。**重跑后必须重新冻结**，不允许拿旧
fd 当新证据：
    1. 在本目录运行 `python -X utf8 capture_loopback.py`，生成 `loopback_capture.json`；
    2. 把该文件的 `source/port/captured_at/pid/payload_hex/calls` 原样抄进
       `data/labs/ch15_labs.json::labs.socket_api.capture`（只做逻辑调用归一化，
       不改字节、不改 fd）；
    3. `tests/test_ch15.gd` 的 `socket_calls` 与 `expect_meta` 里的 fd 必须与该次捕获一致；
       转正判据会核对「捕获字节 == 收发字节」且「fd 与 socket_calls 一致」。

数据流：客户端 socket → connect → sendall(payload) → recv(echo) → close；
服务端 accept → recv → sendall(同一份字节原样回声) → close。回声保证客户端读回的是
同一份真实字节，可用于「同一份字节在两个读取点被读到」的比对。
"""

import json
import os
import socket
import threading
import time

REC = []


def log(who, n, fd, op, direction="", data=b"", note=""):
    REC.append({
        "who": who,
        "n": n,
        "fd": int(fd),
        "op": op,
        "dir": direction,
        "bytes_hex": data.hex(),
        "bytes_len": len(data),
        "mono_ns": time.perf_counter_ns(),
        "note": note,
    })


def main():
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", 0))
    port = srv.getsockname()[1]
    srv.listen(1)
    log("server", 1, srv.fileno(), "socket", note="listen socket")

    result = {}

    def server():
        conn, addr = srv.accept()
        log("server", 2, conn.fileno(), "accept", direction="in",
            note="accepted from %s" % (addr,))
        data = conn.recv(4096)
        log("server", 3, conn.fileno(), "recv", direction="in", data=data)
        # 回声：把收到的同一行原样发回，保证客户端 recv 能原样读回。
        conn.sendall(data)
        log("server", 4, conn.fileno(), "send", direction="out", data=data)
        fd = conn.fileno()
        conn.close()
        log("server", 5, fd, "close", note="conn closed")
        result["server_done"] = True

    th = threading.Thread(target=server, daemon=True)
    th.start()

    cli = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    log("client", 1, cli.fileno(), "socket")
    cli.connect(("127.0.0.1", port))
    log("client", 2, cli.fileno(), "connect", note="to 127.0.0.1:%d" % port)
    payload = b"hello, world"
    cli.sendall(payload)
    log("client", 3, cli.fileno(), "send", direction="out", data=payload)
    echo = cli.recv(4096)
    log("client", 4, cli.fileno(), "recv", direction="in", data=echo)
    fd = cli.fileno()
    cli.close()
    log("client", 5, fd, "close")
    th.join(timeout=2)
    srv.close()

    out = {
        "source": "python-loopback",
        "platform": os.name,
        "host": "127.0.0.1",
        "port": port,
        "captured_at": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "pid": os.getpid(),
        "payload_hex": payload.hex(),
        "calls": REC,
        "server_done": result.get("server_done", False),
    }
    with open("loopback_capture.json", "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=2)
    print(json.dumps({k: out[k] for k in ("source", "platform", "port",
                                          "payload_hex", "server_done")},
                     ensure_ascii=False))
    for c in REC:
        print("%-6s n=%d fd=%d %-7s %s %s" % (c["who"], c["n"], c["fd"],
                                              c["op"], c["dir"],
                                              c["bytes_hex"] or "-"))


main()
