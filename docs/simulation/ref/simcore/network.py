"""网络层参考实现：帧 / ARP / 链路状态路由 / 分组转发 / 简化 TCP。

诚实声明（与 04_network.md 对应）
--------------------------------
* 链路是**点对点**的（不是共享介质），所以 ARP 退化成"一问一答 + 缓存"；
  真实以太网是广播域 + 交换机，这里没有模拟冲突域与 CSMA/CD。
* 帧校验用 **CRC-8**（真实以太网 FCS 是 CRC-32）；教学目的是"能抓到坏帧"，
  CRC-8 对单字节突发错误的检出率够用，但**不能**外推到真实网络强度。
* IP 用完整 32 位表示（不缩减位宽），但场景限制在 10.0.0.0/24 的小网络；
  子网掩码只实现 /24，不做 VLSM。
* 路由只实现**链路状态（Dijkstra）**与**距离矢量（RIP 式，用于演示计数到无穷）**，
  不做 BGP、策略路由、ECMP。ECMP 会让"确定性"变复杂，明确不做。
* 可靠传输是 TCP 的**简化状态机**：段编号（不是字节编号）、固定窗口、
  不支持乱序缓存、不支持 SACK。见 04_network.md 的简化影响表。
"""

from __future__ import annotations

import hashlib
import heapq
import random
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Tuple

INF = 16  # RIP 的"无穷"= 16 跳；真实 IPv4 是 255，这里取教学值并显式写死。


def crc8(data: bytes, poly: int = 0x07) -> int:
    crc = 0
    for b in data:
        crc ^= b
        for _ in range(8):
            crc = ((crc << 1) ^ poly) & 0xFF if (crc & 0x80) else (crc << 1) & 0xFF
    return crc


@dataclass(frozen=True)
class Frame:
    dst_mac: int
    src_mac: int
    ethertype: str
    payload: bytes
    fcs: int = -1

    @staticmethod
    def build(dst_mac: int, src_mac: int, ethertype: str, payload: bytes) -> "Frame":
        raw = f"{dst_mac:02x}{src_mac:02x}{ethertype}".encode() + payload
        return Frame(dst_mac, src_mac, ethertype, payload, crc8(raw))

    def check(self) -> bool:
        raw = f"{self.dst_mac:02x}{self.src_mac:02x}{self.ethertype}".encode() + self.payload
        return crc8(raw) == self.fcs


@dataclass
class Packet:
    src: int
    dst: int
    ttl: int
    proto: str
    seq: int = 0
    ack: int = 0
    flags: int = 0
    payload: bytes = b""


@dataclass
class Node:
    ip: int
    mac: int
    arp: Dict[int, int] = field(default_factory=dict)
    routes: Dict[int, int] = field(default_factory=dict)


@dataclass
class Link:
    a: int
    b: int
    delay: int
    loss: float = 0.0
    corrupt: float = 0.0


class Network:
    """确定性网络仿真器。所有随机性来自 per-link 的 seed，且只在发送点消耗。"""

    def __init__(self, seed: int = 1):
        self.seed = seed
        self.nodes: Dict[int, Node] = {}
        self.links: List[Link] = []
        self._adj: Dict[int, List[Tuple[int, int, float]]] = {}
        self.events: List[Tuple[int, str, str]] = []
        self.rngs: Dict[Tuple[int, int], random.Random] = {}
        self.now = 0
        self.arp_delay = 2

    # -- 拓扑 --
    def add_node(self, ip: int, mac: int) -> None:
        self.nodes[ip] = Node(ip, mac)

    def add_link(self, ip_a: int, ip_b: int, delay: int = 1, loss: float = 0.0, corrupt: float = 0.0) -> None:
        self.links.append(Link(ip_a, ip_b, delay, loss, corrupt))
        key = (min(ip_a, ip_b), max(ip_a, ip_b))
        self.rngs[key] = random.Random(f"{self.seed}:{key[0]}:{key[1]}")
        self._adj.setdefault(ip_a, []).append((ip_b, delay, loss))
        self._adj.setdefault(ip_b, []).append((ip_a, delay, loss))

    def _log(self, tag: str, detail: str) -> None:
        self.events.append((self.now, tag, detail))

    # -- 路由：链路状态 + Dijkstra（平局按 IP 升序，保证确定性） --
    def compute_routes(self) -> Dict[int, Dict[int, int]]:
        tables: Dict[int, Dict[int, int]] = {}
        for src in sorted(self.nodes):
            dist: Dict[int, int] = {src: 0}
            prev: Dict[int, int] = {}
            unvisited = set(self.nodes)
            # 朴素 Dijkstra；节点数 ≤ 256，O(V^2) 足够，且不引入堆的平局不确定性
            while unvisited:
                u = min((n for n in unvisited if n in dist), key=lambda x: (dist[x], x), default=None)
                if u is None:
                    break
                unvisited.discard(u)
                for v, d, _loss in self._adj.get(u, []):
                    if v in unvisited and dist.get(v, 1 << 30) > dist[u] + d:
                        dist[v] = dist[u] + d
                        prev[v] = u
            table: Dict[int, int] = {}
            for dst in self.nodes:
                if dst == src:
                    continue
                hop = dst
                seen = 0
                while prev.get(hop, src) != src and seen < len(self.nodes):
                    hop = prev[hop]
                    seen += 1
                table[dst] = hop
            tables[src] = table
        for ip, t in tables.items():
            self.nodes[ip].routes = t
        return tables

    # -- ARP --
    def resolve(self, src: int, dst: int) -> int:
        node = self.nodes[src]
        if dst in node.arp:
            return node.arp[dst]
        # 点到点链路：ARP 只发生在同一链路上；跨网段由路由器解析下一跳
        nbr_mac = self.nodes[dst].mac
        self._log("ARP_REQ", f"{self.ipstr(src)} ? {self.ipstr(dst)}")
        self.now += self.arp_delay
        self._log("ARP_REP", f"{self.ipstr(dst)} -> {nbr_mac:02x}")
        node.arp[dst] = nbr_mac
        return nbr_mac

    @staticmethod
    def ipstr(ip: int) -> str:
        return ".".join(str((ip >> s) & 0xFF) for s in (24, 16, 8, 0))

    # -- 发送 --
    def _transmit(self, a: int, b: int, frame: Frame) -> Tuple[bool, str]:
        link = next((l for l in self.links if {l.a, l.b} == {a, b}), None)
        if link is None:
            return False, "NO_ROUTE"
        key = (min(a, b), max(a, b))
        rng = self.rngs[key]
        if rng.random() < link.loss:
            self._log("DROP_LOSS", f"{self.ipstr(a)}->{self.ipstr(b)}")
            return False, "LOSS"
        if link.corrupt > 0.0 and rng.random() < link.corrupt:
            # 真实链路噪声：翻转载荷中一位，FCS 仍保留原值 → 收端检出
            if frame.payload:
                i = int(rng.random() * len(frame.payload))
                bad = bytearray(frame.payload)
                bad[i] ^= 1 << int(rng.random() * 8)
                frame = Frame(frame.dst_mac, frame.src_mac, frame.ethertype, bytes(bad), frame.fcs)
        if not frame.check():
            self._log("DROP_CRC", f"{self.ipstr(a)}->{self.ipstr(b)}")
            return False, "CRC"
        self.now += link.delay
        self._log("TX", f"{self.ipstr(a)}->{self.ipstr(b)} {frame.ethertype} {len(frame.payload)}B")
        return True, "OK"

    def send(self, src: int, dst: int, payload: bytes, proto: str = "DATA",
             ttl: int = 8, seq: int = 0, ack: int = 0, flags: int = 0) -> bool:
        """主机到主机的一次 IP 投递（含 ARP、逐跳转发、TTL、CRC、丢包）。"""
        if src not in self.nodes or dst not in self.nodes:
            raise ValueError("未知主机")
        pkt = Packet(src, dst, ttl, proto, seq, ack, flags, payload)
        cur = src
        for _ in range(ttl + 1):
            if pkt.ttl <= 0:
                self._log("DROP_TTL", f"{self.ipstr(cur)}->{self.ipstr(dst)}")
                return False
            nxt = self.nodes[cur].routes.get(dst)
            if nxt is None:
                self._log("DROP_NO_ROUTE", self.ipstr(cur))
                return False
            mac = self.resolve(cur, nxt)
            frame = Frame.build(mac, self.nodes[cur].mac, "IPv4", payload)
            ok, _why = self._transmit(cur, nxt, frame)
            if not ok:
                return False
            if nxt == dst:
                self._log("DELIVER", f"{self.ipstr(dst)} {pkt.proto} seq={pkt.seq}")
                return True
            cur = nxt
            pkt.ttl -= 1
            self._log("FWD", f"{self.ipstr(cur)} ttl={pkt.ttl}")
        self._log("DROP_LOOP", self.ipstr(cur))
        return False

    def replay_hash(self) -> str:
        raw = "\n".join(f"{t}|{tag}|{d}" for t, tag, d in self.events)
        return hashlib.sha256(raw.encode()).hexdigest()[:16]


# ---- 距离矢量（用于演示计数到无穷） -----------------------------------------


def distance_vector(edges: List[Tuple[int, int]], nodes: List[int], rounds: int = 12,
                    split_horizon: bool = False, broken: Optional[List[Tuple[int, int]]] = None):
    """事件驱动的距离矢量（RIP 式）仿真，返回每一 tick 的路由表快照。

    为什么不用"同步轮次"：同步轮次里 A 会在同一轮内被告知 B 失效，计数到无穷根本不会发生。
    真实网络里"好消息传得快、坏消息传得慢"，是因为**断链瞬间 A 的旧通告已经在飞**。
    这里显式把初始通告放在飞行队列里（t=0 发出，t=1 送到），才能复现这一现象。

    RIP 语义：
      * metric = 跳数，16 = 无穷；
      * **同一下一跳**（same path）收到更差通告也必须替换 —— 这是计数到无穷的根因；
      * split_horizon 时把"从该邻居学到的路由"以 16 回传（毒性逆转）。
    """
    orig: Dict[int, Dict[int, int]] = {n: {} for n in nodes}
    for a, b in edges:
        orig[a][b] = 1
        orig[b][a] = 1
    adj: Dict[int, Dict[int, int]] = {n: dict(orig[n]) for n in nodes}
    if broken:
        for a, b in broken:
            adj[a].pop(b, None)
            adj[b].pop(a, None)

    dist: Dict[int, Dict[int, int]] = {}
    nh: Dict[int, Dict[int, Optional[int]]] = {}
    # 断链**之前**全网已收敛的跳数表（BFS），断链瞬间它仍在飞
    pre: Dict[int, Dict[int, int]] = {}
    for n in nodes:
        d = {x: INF for x in nodes}
        d[n] = 0
        frontier = [n]
        while frontier:
            nxt = []
            for u in frontier:
                for v in orig[u]:
                    if d[v] == INF:
                        d[v] = d[u] + 1
                        nxt.append(v)
            frontier = nxt
        pre[n] = d

    for n in nodes:
        dist[n] = dict(pre[n])
        h: Dict[int, Optional[int]] = {x: None for x in nodes}
        for x in nodes:
            if x == n or dist[n][x] == INF:
                continue
            h[x] = min(
                (k for k in orig[n] if pre[n][k] + 1 == pre[n][x]),
                key=lambda k: (pre[n][k], k),
                default=None,
            )
        nh[n] = h

    # 断链：两端的接口都立刻失效（这就是"坏消息"的起点）
    for a, b in broken or []:
        dist[a][b] = INF
        dist[b][a] = INF
        nh[a][b] = None
        nh[b][a] = None

    seq = 0
    q: List[Tuple[int, int, int, int, Dict[int, int]]] = []
    hist: Dict[int, Dict[int, Dict[int, int]]] = {}

    def advertise(n: int, t: int) -> None:
        nonlocal seq
        for nb in adj[n]:
            snap = dict(dist[n])
            if split_horizon:
                for dst in list(snap):
                    if nh[n].get(dst) == nb:
                        snap[dst] = INF
            seq += 1
            heapq.heappush(q, (t + 1, seq, n, nb, snap))

    # 初始：所有邻居对互发断链前的表（t=0 发出）
    for a, b in edges:
        seq += 1
        q.append((1, seq, a, b, dict(pre[a])))
        seq += 1
        q.append((1, seq, b, a, dict(pre[b])))

    for t in range(rounds + 1):
        hist[t] = {n: dict(dist[n]) for n in nodes}
        while q and q[0][0] == t:
            _, _, src, dst_node, snap = heapq.heappop(q)
            if dst_node not in adj.get(src, {}):
                continue
            changed = False
            for d in nodes:
                if d == src or d == dst_node:
                    continue
                cand = min(INF, snap.get(d, INF) + 1)
                same_path = nh[dst_node].get(d) == src
                if (same_path or cand < dist[dst_node][d]) and cand != dist[dst_node][d]:
                    dist[dst_node][d] = cand
                    nh[dst_node][d] = src if cand < INF else None
                    changed = True
            if changed:
                advertise(dst_node, t)
    return [hist[t] for t in sorted(hist)], dist


# ---- 简化 TCP ----------------------------------------------------------------


class TcpState:
    CLOSED = "CLOSED"
    SYN_SENT = "SYN_SENT"
    ESTABLISHED = "ESTABLISHED"
    FIN_WAIT = "FIN_WAIT"
    TIME_WAIT = "TIME_WAIT"


@dataclass
class TcpConfig:
    rto: int = 10            # 初始重传超时（tick）
    max_retries: int = 5
    window: int = 4          # 固定窗口（段），不做拥塞控制
    mss: int = 8             # 段大小（字节），仅用于教学展示


class TcpLite:
    """简化 TCP：三次握手 + 累积确认 + 超时重传 + 指数退避。

    明确**不做**：拥塞控制、快速重传、SACK、乱序缓存、延迟 ACK、窗口缩放。
    """

    def __init__(self, net: Network, local: int, remote: int, cfg: TcpConfig | None = None, name: str = "tcp"):
        self.net, self.local, self.remote = net, local, remote
        self.cfg = cfg or TcpConfig()
        self.state = TcpState.CLOSED
        self.next_seq = 0
        self.acked = -1
        self.log: List[Tuple[int, str, str]] = []
        self.retries = 0
        self.rto = self.cfg.rto
        self.delivered: List[int] = []

    def _ev(self, tag: str, detail: str) -> None:
        self.log.append((self.net.now, tag, detail))

    def _seg(self, payload: bytes = b"", seq: int = 0, ack: int = 0, flags: int = 0, proto: str = "TCP") -> bool:
        return self.net.send(self.local, self.remote, payload, proto=proto, seq=seq, ack=ack, flags=flags)

    def connect(self) -> bool:
        """三次握手：SYN → SYN-ACK → ACK。任一步丢包则按 RTO 重试。"""
        if self.state != TcpState.CLOSED:
            raise RuntimeError(f"状态非法: {self.state}")
        self.state = TcpState.SYN_SENT
        self._ev("SYN", "connect")
        for attempt in range(self.cfg.max_retries):
            if self._seg(flags=0x02):
                self._ev("SYN_OK", f"attempt={attempt}")
                self.state = TcpState.ESTABLISHED
                self.acked = -1
                self.next_seq = 1
                return True
            self._ev("RTO", f"SYN retry {attempt + 1}/{self.cfg.max_retries} rto={self.rto}")
            self.net.now += self.rto
            self.rto *= 2
        self.state = TcpState.CLOSED
        self._ev("ABORT", "handshake failed")
        return False

    def send(self, data: bytes) -> bool:
        """按段发送；每段独立计时重传（教学简化：没有真正的批量窗口调度）。"""
        if self.state != TcpState.ESTABLISHED:
            raise RuntimeError("未建立连接，禁止发送数据")
        seg_size = self.cfg.mss
        segs = [data[i:i + seg_size] for i in range(0, len(data), seg_size)] or [b""]
        base_rto = self.cfg.rto
        for s in segs:
            seq = self.next_seq
            for attempt in range(self.cfg.max_retries):
                if self._seg(s, seq=seq):
                    self._ev("DATA_OK", f"seq={seq}")
                    self.delivered.append(seq)
                    self.acked = seq
                    self.next_seq += 1
                    break
                self._ev("RTO", f"data seq={seq} retry {attempt + 1}/{self.cfg.max_retries} rto={self.rto}")
                self.net.now += self.rto
                self.rto = min(self.rto * 2, self.cfg.rto * 2 ** self.cfg.max_retries)
            else:
                self._ev("ABORT", f"data seq={seq} lost")
                self.state = TcpState.CLOSED
                return False
            self.rto = base_rto  # Karn 简化：收到确认后回到初始 RTO（真实 TCP 用平滑估计）
        return True

    def close(self) -> None:
        self.state = TcpState.FIN_WAIT
        self._ev("FIN", "close")
