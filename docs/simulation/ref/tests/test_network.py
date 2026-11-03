"""验证 2：路由收敛 / 转发 / 校验 / 重传（网络层）。

运行：python -m tests.test_network（在 ref/ 目录下）
"""

from __future__ import annotations

import hashlib
import itertools
from typing import Dict, List, Tuple

from simcore.network import (
    INF, Network, TcpConfig, TcpLite, crc8, distance_vector,
)

IP = lambda n: (10 << 24) | n  # 10.0.0.n


def ground_truth_dist(nodes: List[int], edges: List[Tuple[int, int, int]]) -> Dict[int, Dict[int, int]]:
    """独立实现的 Floyd 最短路，用来校验 Dijkstra 的实现。"""
    d = {n: {m: (0 if n == m else 1 << 30) for m in nodes} for n in nodes}
    for a, b, w in edges:
        d[a][b] = min(d[a][b], w)
        d[b][a] = min(d[b][a], w)
    for k in nodes:
        for i in nodes:
            for j in nodes:
                if d[i][k] + d[k][j] < d[i][j]:
                    d[i][j] = d[i][k] + d[k][j]
    return d


def build_net(seed: int = 7) -> Network:
    """拓扑：
        1 --1-- 2 --3-- 3 --1-- 4
        |               |
        +------5--------+
    最短：1→3 走 1-2-3（4），不是直连 5。
    """
    net = Network(seed)
    for n in range(1, 5):
        net.add_node(IP(n), 0x10 + n)
    net.add_link(IP(1), IP(2), delay=1)
    net.add_link(IP(2), IP(3), delay=3)
    net.add_link(IP(1), IP(3), delay=5)
    net.add_link(IP(3), IP(4), delay=1)
    net.compute_routes()
    return net


def route_cost(net: Network, src: int, dst: int) -> int:
    """按路由表逐跳累加链路延迟；路由环或断链返回无穷。"""
    cur, cost, hops = src, 0, 0
    while cur != dst:
        nxt = net.nodes[cur].routes.get(dst)
        if nxt is None:
            return INF
        link = next((l for l in net.links if {l.a, l.b} == {cur, nxt}), None)
        if link is None:
            return INF
        cost += link.delay
        cur = nxt
        hops += 1
        if hops > len(net.nodes):
            return INF
    return cost


def test_link_state_matches_ground_truth() -> dict:
    net = build_net()
    nodes = [IP(n) for n in range(1, 5)]
    gt = ground_truth_dist(nodes, [(IP(1), IP(2), 1), (IP(2), IP(3), 3), (IP(1), IP(3), 5), (IP(3), IP(4), 1)])
    for s in nodes:
        for d in nodes:
            if s == d:
                continue
            got = route_cost(net, s, d)
            assert got == gt[s][d], (s, d, got, gt[s][d])
    return {"routes": len(nodes) * (len(nodes) - 1), "A->C": route_cost(net, IP(1), IP(3))}


def test_reconverge_after_link_failure() -> dict:
    net = build_net()
    before = route_cost(net, IP(1), IP(3))
    net.links = [l for l in net.links if {l.a, l.b} != {IP(2), IP(3)}]
    net._adj = {}
    for l in net.links:
        net._adj.setdefault(l.a, []).append((l.b, l.delay, l.loss))
        net._adj.setdefault(l.b, []).append((l.a, l.delay, l.loss))
    net.compute_routes()
    after = route_cost(net, IP(1), IP(3))
    assert before == 4 and after == 5, (before, after)
    return {"before": before, "after": after}


def test_count_to_infinity() -> dict:
    """A(1)—B(2)—C(3) 直线；断开 B—C 后，无水平分割会一路数到 16。"""
    h_no, final_no = distance_vector([(1, 2), (2, 3)], [1, 2, 3], rounds=30,
                                     split_horizon=False, broken=[(2, 3)])
    h_sh, final_sh = distance_vector([(1, 2), (2, 3)], [1, 2, 3], rounds=30,
                                     split_horizon=True, broken=[(2, 3)])
    series_no = [snap[1][3] for snap in h_no]
    series_sh = [snap[1][3] for snap in h_sh]
    # 无水平分割：B 对 C 的距离逐轮上升，直到无穷（16）——这就是"计数到无穷"
    assert series_no[-1] == INF and max(series_no) == INF, series_no
    assert series_no[-1] > 2 and len(series_no) > 5, series_no
    # 有水平分割：B 不再接受经 A 的假路由，保持 16；A 最终也失效
    assert final_sh[1][3] == INF and final_sh[2][3] == INF, final_sh
    return {"no_sh_series": series_no, "sh_series": series_sh,
            "no_sh_rounds": len(h_no) - 1, "sh_rounds": len(h_sh) - 1}


def test_forwarding_and_drops() -> dict:
    net = build_net()
    ok = net.send(IP(1), IP(4), b"hello", seq=1)
    assert ok
    hops = [e for e in net.events if e[1] == "FWD"]
    # TTL 用尽：1→4 需要 2 次转发（经过 2、3），ttl=1 会在第一跳后丢弃
    net2 = build_net()
    net2.send(IP(1), IP(4), b"x", ttl=1)
    assert any(e[1] == "DROP_TTL" for e in net2.events)
    # CRC：100% 损坏链路必须被检出
    net3 = build_net()
    net3.links = [l for l in net3.links if {l.a, l.b} != {IP(1), IP(2)}]
    net3.links.append(type(net3.links[0])(IP(1), IP(2), 1, 0.0, 1.0))
    net3._adj = {}
    for l in net3.links:
        net3._adj.setdefault(l.a, []).append((l.b, l.delay, l.loss))
        net3._adj.setdefault(l.b, []).append((l.a, l.delay, l.loss))
    net3.compute_routes()
    assert net3.send(IP(1), IP(4), b"payload") is False
    assert any(e[1] == "DROP_CRC" for e in net3.events)
    return {"forward_hops": len(hops), "ttl_drop": True, "crc_drop": True}


def test_crc8_single_bit() -> dict:
    """CRC-8 对单比特翻转 100% 检出（256 个位置 × 长度 8）。"""
    seen = 0
    for length in (1, 4, 8):
        data = bytes(range(0x30, 0x30 + length))
        base = crc8(data)
        for byte_i in range(length):
            for bit in range(8):
                bad = bytearray(data)
                bad[byte_i] ^= 1 << bit
                assert crc8(bytes(bad)) != base, (byte_i, bit)
                seen += 1
    return {"cases": seen, "detected": seen}


def run_tcp(seed: int, loss: float = 0.2, payload: bytes = b"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ") -> dict:
    net = Network(seed)
    net.add_node(IP(1), 0x11)
    net.add_node(IP(2), 0x22)
    net.add_link(IP(1), IP(2), delay=1, loss=loss)
    net.compute_routes()
    conn = TcpLite(net, IP(1), IP(2), TcpConfig(rto=10, max_retries=5, mss=8))
    connected = conn.connect()
    ok = conn.send(payload) if connected else False
    digest = hashlib.sha256(
        ("\n".join(f"{t}|{k}|{d}" for t, k, d in net.events) + "\n" + conn.state).encode()
    ).hexdigest()[:16]
    return {"connected": connected, "delivered": len(conn.delivered), "sent": ok,
            "state": conn.state, "rto_events": [e for e in conn.log if e[1] == "RTO"],
            "hash": digest, "events": net.events}


def test_tcp_retransmit() -> dict:
    r = run_tcp(seed=11, loss=0.45)
    assert r["connected"] and r["sent"], r
    assert r["delivered"] >= 1, r
    assert len(r["rto_events"]) >= 1, "丢包下应至少发生一次重传"
    # 指数退避：同一段连续失败时，相邻重传的 rto 必须严格上升（10 → 20 → 40 ...）
    chains: Dict[str, List[int]] = {}
    for _t, tag, detail in r["rto_events"]:
        key = detail.split(" retry")[0]
        chains.setdefault(key, []).append(int(detail.split("rto=")[1]))
    grown = {k: v for k, v in chains.items() if len(v) > 1}
    assert grown, chains
    for k, v in grown.items():
        assert all(b > a for a, b in zip(v, v[1:])), (k, v)
    return {"segments_delivered": r["delivered"], "retransmissions": len(r["rto_events"]),
            "backoff_chains": grown, "state": r["state"], "hash": r["hash"]}


def test_tcp_abort_after_max_retries() -> dict:
    """100% 丢包：握手 5 次重试后必须 ABORT，而不是永远等。"""
    r = run_tcp(seed=3, loss=1.0, payload=b"abc")
    assert r["connected"] is False and r["state"] == "CLOSED"
    return {"retries": len(r["rto_events"]), "state": r["state"]}


def test_scenario_determinism() -> dict:
    a = run_tcp(seed=11)
    b = run_tcp(seed=11)
    c = run_tcp(seed=12)
    assert a["hash"] == b["hash"], (a["hash"], b["hash"])
    return {"same_seed_hash": a["hash"], "other_seed_hash": c["hash"],
            "differs": a["hash"] != c["hash"]}


ALL = [
    ("链路状态路由 = 独立最短路", test_link_state_matches_ground_truth),
    ("断链后重收敛", test_reconverge_after_link_failure),
    ("距离矢量计数到无穷", test_count_to_infinity),
    ("逐跳转发 / TTL / CRC 丢弃", test_forwarding_and_drops),
    ("CRC-8 单比特检出", test_crc8_single_bit),
    ("TCP 重传与指数退避", test_tcp_retransmit),
    ("TCP 重试耗尽后中止", test_tcp_abort_after_max_retries),
    ("同种子场景可复现", test_scenario_determinism),
]

if __name__ == "__main__":
    for name, fn in ALL:
        r = fn()
        print(f"[PASS] {name}: {r}")
