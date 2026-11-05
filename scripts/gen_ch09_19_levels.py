"""Generate ch09~ch19 levels.json from labs data + chapter metadata.

Run from project root: python scripts/gen_ch09_19_levels.py
"""
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LABS_DIR = os.path.join(ROOT, "data", "labs")
CHAPTERS_DIR = os.path.join(ROOT, "data", "chapters")

# Chapter metadata: title, subtitle, badge, next_chapter, source doc
CHAPTER_META = {
    9:  ("第九章 · 下一步交给谁", "编址、ARP、交换机、路由与环路", "CH09-ROUTE", "ch10",
         "docs/curriculum/20-ch09-lecture-copy.md"),
    10: ("第十章 · 花钱买可靠", "序号重排、ACK 重传、滑动窗口与可靠通道", "CH10-RELIABLE", "ch11",
         "docs/curriculum/21-ch10-lecture-copy.md"),
    11: ("第十一章 · 16 个比特", "汇编、跳转循环、栈调用与调试", "CH11-ASM", "ch12",
         "docs/curriculum/22-ch11-lecture-copy.md"),
    12: ("第十二章 · 地址算术", "表达式编译、指针数组、栈帧、递归与字符串", "CH12-C", "ch13",
         "docs/curriculum/23-ch12-lecture-copy.md"),
    13: ("第十三章 · 一次编写到处运行", "字节码 VM、对象引用与垃圾回收", "CH13-JAVA", "ch14",
         "docs/curriculum/24-ch13-lecture-copy.md"),
    14: ("第十四章 · 机器替你做", "解释器、动态类型与脚本自动化", "CH14-PY", "ch15",
         "docs/curriculum/25-ch14-lecture-copy.md"),
    15: ("第十五章 · 一半是别人写的", "库与 ABI、socket、版本兼容与 DNS", "CH15-API", "ch16",
         "docs/curriculum/26-ch15-lecture-copy.md"),
    16: ("第十六章 · 不肯关机", "监听连接、并发、压测与常驻清理", "CH16-SERVER", "ch17",
         "docs/curriculum/27-ch16-lecture-copy.md"),
    17: ("第十七章 · 三十年前的结构", "消息格式、在线离线与双客户端对发", "CH17-CHAT", "ch18",
         "docs/curriculum/28-ch17-lecture-copy.md"),
    18: ("第十八章 · 让篡改有代价", "对称密钥、非对称交换、哈希证书与中间人", "CH18-CRYPTO", "ch19",
         "docs/curriculum/29-ch18-lecture-copy.md"),
    19: ("第十九章 · 空气不属于你", "共享介质、嵌入式约束、传感闭环、固件升级与多终端告警", "CH19-IOT", "final",
         "docs/curriculum/30-ch19-lecture-copy.md"),
}

# Per-lab metadata: (knowledge_id, milestone_id, skill_node_id, subtitle)
LAB_META = {
    9: {
        "addressing":      ("KN-ADDR-09",   "CH09-1", "SK-ADDRESSING", "4+4 地址与子网划分"),
        "arp":             ("KN-ARP-01",    "CH09-2", "SK-ARP",        "广播问、单播答与缓存"),
        "switch":          ("KN-SWITCH-01", "CH09-3", "SK-SWITCH",     "源地址学习与泛洪"),
        "router":          ("KN-ROUTE-01",  "CH09-4", "SK-ROUTER",     "下一跳、TTL 与成圈"),
        "loop_recovery":   ("KN-LOOP-01",   "CH09-5", "SK-LOOP",       "风暴、阻断与备路恢复"),
    },
    10: {
        "seq_reorder":       ("KN-SEQ-01",  "CH10-1", "SK-SEQ",      "序号与乱序重排"),
        "ack_retransmit":    ("KN-ACK-01",  "CH10-2", "SK-ACK",      "确认、超时与同号重发"),
        "sliding_window":    ("KN-WIN-01",  "CH10-3", "SK-WINDOW",   "窗口、缓冲与吞吐"),
        "reliable_channel":  ("KN-REL-01",  "CH10-4", "SK-RELIABLE", "1 KB 全对送达"),
    },
    11: {
        "assembler":      ("KN-ASM-01",    "CH11-1", "SK-ASM",    "机器码与助记符"),
        "branch_loop":    ("KN-BRANCH-01", "CH11-2", "SK-BRANCH", "条件标志与循环"),
        "stack_call":     ("KN-STACK-01",  "CH11-3", "SK-STACK",  "压栈、调用与返回"),
        "debug_locate":   ("KN-DEBUG-01",  "CH11-4", "SK-DEBUG",  "把错缩到一行"),
    },
    12: {
        "expr_compile":       ("KN-EXPR-01",  "CH12-1", "SK-COMPILE", "AST 摊成指令"),
        "pointer_array":      ("KN-PTR-01",   "CH12-2", "SK-POINTER", "地址加偏移"),
        "stack_frame":        ("KN-FRAME-01", "CH12-3", "SK-FRAME-12", "调用压一层"),
        "recursion_baseline": ("KN-RECUR-01", "CH12-4", "SK-RECUR",   "阶乘与斐波那契"),
        "string_reverse":     ("KN-STR-01",   "CH12-5", "SK-STRING",  "按字节搬"),
    },
    13: {
        "bytecode_vm":  ("KN-BC-01",  "CH13-1", "SK-BYTECODE", "栈顶一步一指令"),
        "object_ref":   ("KN-OBJ-01", "CH13-2", "SK-OBJECT",   "起始地址即身份"),
        "gc_reclaim":   ("KN-GC-01",  "CH13-3", "SK-GC",       "没人指就回收"),
    },
    14: {
        "interpreter_eval":  ("KN-INTERP-01",  "CH14-1", "SK-INTERP",  "词法语法到求值"),
        "dynamic_type":      ("KN-DYNTYPE-01", "CH14-2", "SK-DYNTYPE", "类型跟着值走"),
        "script_automation": ("KN-SCRIPT-01",  "CH14-3", "SK-SCRIPT",  "只调已有接口"),
    },
    15: {
        "library_abi":     ("KN-ABI-01",   "CH15-1", "SK-ABI",     "调用先对齐约定"),
        "socket_api":      ("KN-SOCK-01",  "CH15-2", "SK-SOCKET",  "网络折成句柄"),
        "version_compat":  ("KN-VER-01",   "CH15-3", "SK-VERSION", "改接口不能悄悄坏"),
        "dns_resolve":     ("KN-DNS-01",   "CH15-4", "SK-DNS",     "名字换地址"),
    },
    16: {
        "server_listen":     ("KN-LISTEN-01",  "CH16-1", "SK-LISTEN",  "服务器不关机"),
        "concurrency":       ("KN-CONCUR-01",  "CH16-2", "SK-CONCUR",  "两连接不互踩"),
        "load_test":         ("KN-LOAD-16",    "CH16-3", "SK-LOAD",    "8 个请求真发"),
        "resident_cleanup":  ("KN-CLEANUP-01", "CH16-4", "SK-CLEANUP", "断开后自己收"),
    },
    17: {
        "msg_format":        ("KN-MSG-01",  "CH17-1", "SK-MSG",      "先定消息长什么样"),
        "presence_offline":  ("KN-PRES-01", "CH17-2", "SK-PRESENCE", "状态在表，消息在队列"),
        "two_client_chat":   ("KN-CHAT-01", "CH17-3", "SK-CHAT",     "双向 20 条一致"),
    },
    18: {
        "xor_cipher":    ("KN-XOR-01",   "CH18-1", "SK-XOR",    "一把钥匙加解同一把"),
        "key_exchange":  ("KN-KEYEX-01", "CH18-2", "SK-KEYEX",  "两把钥匙换会话密钥"),
        "hash_cert":     ("KN-HASH-01",  "CH18-3", "SK-HASH",   "改 1 bit 大改"),
        "mitm_lab":      ("KN-MITM-01",  "CH18-4", "SK-MITM",   "验不过就拒绝"),
    },
    19: {
        "shared_medium":       ("KN-MEDIUM-01", "CH19-1", "SK-MEDIUM",   "空气是一根共用的线"),
        "embedded_budget":     ("KN-EMBED-01",  "CH19-2", "SK-EMBED",    "内存功耗升级落表"),
        "sensor_loop":         ("KN-SENSOR-01", "CH19-3", "SK-SENSOR",   "五段少一段就断"),
        "firmware_rollback":   ("KN-FW-01",     "CH19-4", "SK-FIRMWARE", "失败要能回去"),
        "multi_terminal_alarm":("KN-ALARM-01",  "CH19-5", "SK-ALARM",    "全部入库只报一次"),
    },
}


def main():
    for ch in range(9, 20):
        labs_path = os.path.join(LABS_DIR, f"ch{ch:02d}_labs.json")
        with open(labs_path, "r", encoding="utf-8") as f:
            labs_doc = json.load(f)
        labs = labs_doc["labs"]

        title, subtitle, badge, nxt, source = CHAPTER_META[ch]
        meta = LAB_META[ch]

        # Determine lab order from lab dict insertion order (matches source order)
        lab_ids = list(labs.keys())

        out_labs = []
        objectives = []
        for idx, lid in enumerate(lab_ids):
            lab = labs[lid]
            kn_id, ms_id, sk_id, sub = meta[lid]
            gate_ids = [g["id"] for g in lab.get("gate_cases", [])]
            requires = [lab_ids[idx - 1]] if idx > 0 else []
            obj_id = f"obj_{lid}"
            # objective title from p1 field
            obj_title = lab.get("p1", "").strip()
            # reward: 30/16 for most, 35/18 for last lab
            is_last = idx == len(lab_ids) - 1
            gold = 35 if is_last else 30
            xp = 18 if is_last else 16
            out_labs.append({
                "id": lid,
                "order": idx + 1,
                "title": lab["title"],
                "subtitle": sub,
                "data_key": lid,
                "requires": requires,
                "objective": obj_id,
                "knowledge": kn_id,
                "milestone": ms_id,
                "knowledge_cards": [kn_id],
                "skill_node": sk_id,
                "gate_ids": gate_ids,
                "reward": {"gold": gold, "xp": xp},
            })
            objectives.append({
                "id": obj_id,
                "title": obj_title,
                "lab": lid,
                "knowledge": kn_id,
            })

        doc = {
            "version": 2,
            "id": f"ch{ch:02d}",
            "number": ch,
            "title": title,
            "subtitle": subtitle,
            "source": source,
            "start_gold_mode": "carry",
            "start_gold": 0,
            "start_items": {},
            "complete_reward": {"gold": 25, "xp": 50, "badge": badge},
            "next_chapter": nxt,
            "labs": out_labs,
            "objectives": objectives,
        }

        out_path = os.path.join(CHAPTERS_DIR, f"ch{ch:02d}_levels.json")
        with open(out_path, "w", encoding="utf-8") as f:
            json.dump(doc, f, ensure_ascii=False, indent=2)
            f.write("\n")
        print(f"wrote {out_path}  labs={len(out_labs)} gates={sum(len(l['gate_ids']) for l in out_labs)}")


if __name__ == "__main__":
    main()
