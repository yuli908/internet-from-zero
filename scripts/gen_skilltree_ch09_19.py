"""Append CH09~CH19 nodes to skilltree.json.

Nodes: per lab (milestone + knowledge + skill) + chapter milestone + badge milestone.
References follow ch08 pattern:
  - milestone[i]: requires gate T{ch}.{lab}-4 (first)  OR  node prev + gate T{ch}.{lab}-4
  - chapter milestone: requires last lab milestone
  - badge: requires chapter milestone
  - knowledge[i]: requires gate T{ch}.{lab}-1
  - skill[i]: requires knowledge[i] (first)  OR  node prev_skill + knowledge[i]
"""
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SKILLTREE = os.path.join(ROOT, "data", "skilltree.json")

# chapter -> list of (lab_id, gate_prefix) where gate_prefix is e.g. "T9.1"
CHAPTER_LABS = {
    9:  [("addressing", "T9.1"), ("arp", "T9.1a"), ("switch", "T9.2"), ("router", "T9.3"), ("loop_recovery", "T9.4")],
    10: [("seq_reorder", "T10.1"), ("ack_retransmit", "T10.2"), ("sliding_window", "T10.3"), ("reliable_channel", "T10.4")],
    11: [("assembler", "T11.1"), ("branch_loop", "T11.2"), ("stack_call", "T11.3"), ("debug_locate", "T11.4")],
    12: [("expr_compile", "T12.1"), ("pointer_array", "T12.2"), ("stack_frame", "T12.3"), ("recursion_baseline", "T12.4"), ("string_reverse", "T12.5")],
    13: [("bytecode_vm", "T13.1"), ("object_ref", "T13.2"), ("gc_reclaim", "T13.3")],
    14: [("interpreter_eval", "T14.1"), ("dynamic_type", "T14.2"), ("script_automation", "T14.3")],
    15: [("library_abi", "T15.1"), ("socket_api", "T15.2"), ("version_compat", "T15.3"), ("dns_resolve", "T15.4")],
    16: [("server_listen", "T16.1"), ("concurrency", "T16.2"), ("load_test", "T16.3"), ("resident_cleanup", "T16.4")],
    17: [("msg_format", "T17.1"), ("presence_offline", "T17.2"), ("two_client_chat", "T17.3")],
    18: [("xor_cipher", "T18.1"), ("key_exchange", "T18.2"), ("hash_cert", "T18.3"), ("mitm_lab", "T18.4")],
    19: [("shared_medium", "T19.1"), ("embedded_budget", "T19.2"), ("sensor_loop", "T19.3"), ("firmware_rollback", "T19.4"), ("multi_terminal_alarm", "T19.5")],
}

# Same as levels generation: (knowledge_id, milestone_id, skill_node_id)
LAB_NODES = {
    9:  {"addressing":("KN-ADDR-09","CH09-1","SK-ADDRESSING"), "arp":("KN-ARP-01","CH09-2","SK-ARP"),
         "switch":("KN-SWITCH-01","CH09-3","SK-SWITCH"), "router":("KN-ROUTE-01","CH09-4","SK-ROUTER"),
         "loop_recovery":("KN-LOOP-01","CH09-5","SK-LOOP")},
    10: {"seq_reorder":("KN-SEQ-01","CH10-1","SK-SEQ"), "ack_retransmit":("KN-ACK-01","CH10-2","SK-ACK"),
         "sliding_window":("KN-WIN-01","CH10-3","SK-WINDOW"), "reliable_channel":("KN-REL-01","CH10-4","SK-RELIABLE")},
    11: {"assembler":("KN-ASM-01","CH11-1","SK-ASM"), "branch_loop":("KN-BRANCH-01","CH11-2","SK-BRANCH"),
         "stack_call":("KN-STACK-01","CH11-3","SK-STACK"), "debug_locate":("KN-DEBUG-01","CH11-4","SK-DEBUG")},
    12: {"expr_compile":("KN-EXPR-01","CH12-1","SK-COMPILE"), "pointer_array":("KN-PTR-01","CH12-2","SK-POINTER"),
         "stack_frame":("KN-FRAME-01","CH12-3","SK-FRAME-12"), "recursion_baseline":("KN-RECUR-01","CH12-4","SK-RECUR"),
         "string_reverse":("KN-STR-01","CH12-5","SK-STRING")},
    13: {"bytecode_vm":("KN-BC-01","CH13-1","SK-BYTECODE"), "object_ref":("KN-OBJ-01","CH13-2","SK-OBJECT"),
         "gc_reclaim":("KN-GC-01","CH13-3","SK-GC")},
    14: {"interpreter_eval":("KN-INTERP-01","CH14-1","SK-INTERP"), "dynamic_type":("KN-DYNTYPE-01","CH14-2","SK-DYNTYPE"),
         "script_automation":("KN-SCRIPT-01","CH14-3","SK-SCRIPT")},
    15: {"library_abi":("KN-ABI-01","CH15-1","SK-ABI"), "socket_api":("KN-SOCK-01","CH15-2","SK-SOCKET"),
         "version_compat":("KN-VER-01","CH15-3","SK-VERSION"), "dns_resolve":("KN-DNS-01","CH15-4","SK-DNS")},
    16: {"server_listen":("KN-LISTEN-01","CH16-1","SK-LISTEN"), "concurrency":("KN-CONCUR-01","CH16-2","SK-CONCUR"),
         "load_test":("KN-LOAD-16","CH16-3","SK-LOAD"), "resident_cleanup":("KN-CLEANUP-01","CH16-4","SK-CLEANUP")},
    17: {"msg_format":("KN-MSG-01","CH17-1","SK-MSG"), "presence_offline":("KN-PRES-01","CH17-2","SK-PRESENCE"),
         "two_client_chat":("KN-CHAT-01","CH17-3","SK-CHAT")},
    18: {"xor_cipher":("KN-XOR-01","CH18-1","SK-XOR"), "key_exchange":("KN-KEYEX-01","CH18-2","SK-KEYEX"),
         "hash_cert":("KN-HASH-01","CH18-3","SK-HASH"), "mitm_lab":("KN-MITM-01","CH18-4","SK-MITM")},
    19: {"shared_medium":("KN-MEDIUM-01","CH19-1","SK-MEDIUM"), "embedded_budget":("KN-EMBED-01","CH19-2","SK-EMBED"),
         "sensor_loop":("KN-SENSOR-01","CH19-3","SK-SENSOR"), "firmware_rollback":("KN-FW-01","CH19-4","SK-FIRMWARE"),
         "multi_terminal_alarm":("KN-ALARM-01","CH19-5","SK-ALARM")},
}

CHAPTER_BADGE = {
    9:"CH09-ROUTE", 10:"CH10-RELIABLE", 11:"CH11-ASM", 12:"CH12-C", 13:"CH13-JAVA",
    14:"CH14-PY", 15:"CH15-API", 16:"CH16-SERVER", 17:"CH17-CHAT", 18:"CH18-CRYPTO", 19:"CH19-IOT",
}

# Short descriptions for nodes
def ms_desc(ch, lab_idx, lab_id):
    # reuse lab title from labs file? keep generic
    return f"第{ch}章第{lab_idx+1}节验收。"

def kn_desc(ch, lab_id):
    return f"CH{ch:02d} {lab_id} 核心概念。"

def sk_desc(ch, lab_id):
    return f"CH{ch:02d} {lab_id} 可复用做法。"


def main():
    with open(SKILLTREE, "r", encoding="utf-8") as f:
        tree = json.load(f)

    # 先剔掉上一次生成的 ch09~ch19 节点，保证重复运行产出同一份数据（幂等）
    nodes = [n for n in tree["nodes"] if int(n.get("level", 0)) < 9]
    # find insertion point: before legacy "voltage" node
    insert_at = len(nodes)
    for i, n in enumerate(nodes):
        if n.get("id") == "voltage":
            insert_at = i
            break

    new_nodes = []
    for ch in range(9, 20):
        labs = CHAPTER_LABS[ch]
        node_map = LAB_NODES[ch]
        badge = CHAPTER_BADGE[ch]
        prev_ms = None
        prev_sk = None
        for i, (lab_id, gate_prefix) in enumerate(labs):
            kn_id, ms_id, sk_id = node_map[lab_id]
            # milestone
            if i == 0:
                ms_req = {"all": [{"type": "gate", "id": f"{gate_prefix}-4"}]}
            else:
                ms_req = {"all": [{"type": "node", "id": prev_ms}, {"type": "gate", "id": f"{gate_prefix}-4"}]}
            new_nodes.append({
                "id": ms_id, "kind": "milestone", "tree": "progress",
                "title": f"CH{ch:02d}-{i+1}", "level": ch, "prereq": [], "auto": True,
                "requires": ms_req,
                "pos": {"col": i + 1, "row": ch - 2},
                "desc": ms_desc(ch, i, lab_id),
            })
            prev_ms = ms_id
            # knowledge
            new_nodes.append({
                "id": kn_id, "kind": "knowledge", "tree": "knowledge",
                "title": f"CH{ch:02d} {lab_id}", "level": ch, "prereq": [], "auto": True,
                "requires": {"all": [{"type": "gate", "id": f"{gate_prefix}-1"}]},
                "pos": {"col": i + 1, "row": ch + 3},
                "desc": kn_desc(ch, lab_id),
            })
            # skill
            if i == 0:
                sk_req = {"all": [{"type": "node", "id": kn_id}]}
            else:
                sk_req = {"all": [{"type": "node", "id": prev_sk}, {"type": "node", "id": kn_id}]}
            new_nodes.append({
                "id": sk_id, "kind": "skill", "tree": "skill",
                "title": f"CH{ch:02d} {lab_id}", "level": ch, "prereq": [], "auto": True,
                "requires": sk_req,
                "pos": {"col": i + 1, "row": ch + 7},
                "desc": sk_desc(ch, lab_id),
            })
            prev_sk = sk_id
        # chapter milestone
        ch_id = f"CH{ch:02d}"
        new_nodes.append({
            "id": ch_id, "kind": "milestone", "tree": "progress",
            "title": f"第{ch}章完成", "level": ch, "prereq": [], "auto": True,
            "requires": {"all": [{"type": "node", "id": prev_ms}]},
            "pos": {"col": len(labs) + 1, "row": ch - 2},
            "gold_award": 25, "xp_award": 50,
            "desc": f"第{ch}章全部实验通过。",
        })
        # badge milestone
        new_nodes.append({
            "id": badge, "kind": "milestone", "tree": "progress",
            "title": f"第{ch}章徽章", "level": ch, "prereq": [], "auto": True,
            "requires": {"all": [{"type": "node", "id": ch_id}]},
            "pos": {"col": len(labs) + 2, "row": ch - 2},
            "gold_award": 25, "xp_award": 50,
            "desc": f"第{ch}章章末徽章。",
        })

    # insert before legacy nodes
    tree["nodes"] = nodes[:insert_at] + new_nodes + nodes[insert_at:]

    with open(SKILLTREE, "w", encoding="utf-8") as f:
        json.dump(tree, f, ensure_ascii=False, indent=2)
        f.write("\n")

    # print summary
    total = len(new_nodes)
    ms = sum(1 for n in new_nodes if n["kind"] == "milestone")
    kn = sum(1 for n in new_nodes if n["kind"] == "knowledge")
    sk = sum(1 for n in new_nodes if n["kind"] == "skill")
    print(f"Inserted {total} nodes: {ms} milestones, {kn} knowledge, {sk} skill")
    print(f"Total nodes now: {len(tree['nodes'])}")


if __name__ == "__main__":
    main()
