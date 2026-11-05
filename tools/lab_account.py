# -*- coding: utf-8 -*-
"""全书 lab 总账：一次扫 20 个 data/labs/*_labs.json + 20 个 data/chapters/*_levels.json。

口径（与 docs/PROGRESS.md §10 同文，改口径必须同时改这两处）：
  进分母 = required==true 且 gate 自身 status/content_status=="ready"
           且所在 lab 的 content_status=="ready"（lab 未写则取 levels 文件）的 gate 数。
  恒等式 = 总 gate 数 == 进分母 + pending（required 且 gate 非 ready）
                          + 节级 deferred（required、gate ready，但所在 lab 非 ready）
                          + required=false（可选 gate）
  任一项不成立，脚本以退出码 1 结束，不许把数字抄进文档。

用法：python tools/lab_account.py
"""

import glob
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LABS_DIR = os.path.join(ROOT, "data", "labs")
LEVELS_DIR = os.path.join(ROOT, "data", "chapters")


def gate_status(c):
    if "content_status" in c:
        return str(c["content_status"])
    if "status" in c:
        return "ready" if str(c["status"]) == "ready" else str(c["status"])
    return "ready"


def load_level_status():
    out = {}
    for path in glob.glob(os.path.join(LEVELS_DIR, "*_levels.json")):
        with open(path, encoding="utf-8") as fh:
            doc = json.load(fh)
        for lab in doc.get("labs", []):
            out[str(lab.get("id", ""))] = str(lab.get("content_status", "ready"))
    return out


def lab_status(cfg, level_status):
    if "content_status" in cfg:
        return str(cfg["content_status"])
    return level_status.get(str(cfg.get("id", "")), "ready")


def scan():
    level_status = load_level_status()
    per_chapter = {}
    counted_list = []
    pending_list = []
    section_deferred_list = []
    optional_list = []
    for path in sorted(glob.glob(os.path.join(LABS_DIR, "*_labs.json"))):
        chapter = os.path.basename(path).replace("_labs.json", "")
        with open(path, encoding="utf-8") as fh:
            doc = json.load(fh)
        row = {"labs": 0, "segs": 0, "gates": 0, "pending": 0, "counted": 0,
               "section_deferred": 0, "optional": 0}
        for lab_id, cfg in (doc.get("labs") or {}).items():
            row["labs"] += 1
            row["segs"] += len(cfg.get("sections") or [])
            ready_lab = lab_status(cfg, level_status) == "ready"
            for g in cfg.get("gate_cases") or []:
                row["gates"] += 1
                gid = str(g.get("id", ""))
                required = bool(g.get("required", True))
                if not required:
                    row["optional"] += 1
                    optional_list.append((chapter, lab_id, gid))
                    continue
                if gate_status(g) != "ready":
                    row["pending"] += 1
                    pending_list.append((chapter, lab_id, gid))
                    continue
                if not ready_lab:
                    row["section_deferred"] += 1
                    section_deferred_list.append((chapter, lab_id, gid))
                    continue
                row["counted"] += 1
                counted_list.append((chapter, lab_id, gid))
        per_chapter[chapter] = row
    return per_chapter, pending_list, section_deferred_list, optional_list


def main():
    per_chapter, pending, section_deferred, optional = scan()
    print("file                     labs  segs  gates  pending  section_def  optional  counted")
    for chapter, r in per_chapter.items():
        print("%-24s %4d  %4d  %5d  %7d  %11d  %8d  %7d"
              % (chapter, r["labs"], r["segs"], r["gates"], r["pending"],
                 r["section_deferred"], r["optional"], r["counted"]))
    total = {k: sum(r[k] for r in per_chapter.values())
             for k in ("labs", "segs", "gates", "pending", "section_deferred",
                       "optional", "counted")}
    print("TOTAL                    %4d  %4d  %5d  %7d  %11d  %8d  %7d"
          % (total["labs"], total["segs"], total["gates"], total["pending"],
             total["section_deferred"], total["optional"], total["counted"]))
    print()
    print("明列不计（既不进分母、也不算 pending）：")
    for item in section_deferred:
        print("  %s / %s / %s  原因=节级 deferred" % item)
    for item in optional:
        print("  %s / %s / %s  原因=required=false" % item)
    excluded = total["section_deferred"] + total["optional"]
    print()
    print("恒等式：%d = %d 进分母 + %d pending + %d 节级 deferred + %d required=false"
          % (total["gates"], total["counted"], total["pending"],
             total["section_deferred"], total["optional"]))
    ok = total["gates"] == total["counted"] + total["pending"] + excluded
    print("验算：%s" % ("闭合" if ok else "不闭合"))
    if not ok:
        sys.exit(1)


if __name__ == "__main__":
    main()
