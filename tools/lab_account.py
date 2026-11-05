# -*- coding: utf-8 -*-
"""全书 lab 总账：一次扫 20 个 data/labs/*_labs.json + 19 个 data/chapters/*_levels.json。

口径（与 docs/PROGRESS.md §10 同文，改口径必须同时改这两处）：
  进分母 = required==true 且 gate 自身 status/content_status=="ready"
           且所在 lab 的 content_status=="ready"（lab 未写则取 levels 文件）的 gate 数。
  恒等式 = 总 gate 数 == 进分母 + pending（required 且 gate 非 ready）
                          + 节级 deferred（required、gate ready，但所在 lab 非 ready）
                          + required=false（可选 gate）
  注意：四桶恒等式按定义结构上恒真（任一侧怎么扫都相等），它只作展示，不当判据。
  真正能红的判据是下面两类逐条完整性比对：
    a) 账目自身：空 id / 重复 id / required 非布尔 / status 取值未知；
    b) 与 levels 逐 lab 比对：gate_ids 是内容侧声明（集合相等）；segs 是**冻结快照**
       （来源＝提交 ac1c428 时刻各 lab 的 sections 数），用途＝漂移提醒，**不是内容侧
       应有值**。两者不同：改了数据却没同步锁值会红（提醒），但"数据本身对不对"仍由
       课件「校验口径」表与各章 test 的 section_count 断言负责（74/84 lab 已核对课件
       逐行段数且完全一致，其余 10 个课件表无逐 lab 行）。
       内容侧若有意改段数，**必须同时改 levels 声明**，否则这条会一直红——这是预期
       行为，不许当成误报关掉。只比 gate 会漏掉「某段被删但 gate 数没变」，所以 segs
       必须单独比。
  任一项不成立，脚本以退出码 1 结束，不许把数字抄进文档。
  没有 levels 文件的章（如 final_labs.json）不静默跳过，打印「该章无声明、跳过」。
  调用方（scripts/run_tests.ps1）据此映射：有 TOTAL 且“验算：闭合”才放行；
  正常退出码 0，账目不闭合 1（入口映射为 8），脚本没跑起来/无 TOTAL 行为 9。

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


def load_level_decls():
    """章节级声明，按 chapter -> data_key -> {gate_ids, segs}。

    gate_ids 是内容侧声明；segs 是 ac1c428 时刻 sections 数的**冻结快照**，只作漂移提醒，
    不是内容侧应有值（应有值见课件「校验口径」表与 test_chNN 的 section_count 断言）。
    只改 lab 的 gate 数或段数、不改这里，账目就会红。
    """
    out = {}
    for path in glob.glob(os.path.join(LEVELS_DIR, "*_levels.json")):
        chapter = os.path.basename(path).replace("_levels.json", "")
        with open(path, encoding="utf-8") as fh:
            doc = json.load(fh)
        per = {}
        for lab in doc.get("labs", []):
            per[str(lab.get("data_key", ""))] = {
                "gate_ids": [str(x) for x in lab.get("gate_ids", [])],
                "segs": lab.get("segs"),
            }
        out[chapter] = per
    return out


def scan():
    level_status = load_level_status()
    decls = load_level_decls()
    problems = []
    skipped = []
    seen_ids = {}
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
               "section_deferred": 0, "optional": 0,
               "decl_gates": 0, "decl_segs": 0, "declared_labs": 0}
        declared = decls.get(chapter)
        if declared is None:
            skipped.append(chapter)
            declared = {}
        for lab_id, cfg in (doc.get("labs") or {}).items():
            row["labs"] += 1
            data_segs = len(cfg.get("sections") or [])
            row["segs"] += data_segs
            got_ids = [str(g.get("id", "")) for g in cfg.get("gate_cases") or []]
            decl = declared.get(lab_id)
            if decl is not None:
                row["declared_labs"] += 1
                row["decl_gates"] += len(decl["gate_ids"])
                if sorted(got_ids) != sorted(decl["gate_ids"]):
                    problems.append("%s/%s: gate 与 levels 声明不符（数据 %s / levels %s）"
                                    % (chapter, lab_id, sorted(got_ids), sorted(decl["gate_ids"])))
                if decl["segs"] is None:
                    problems.append("%s/%s: levels 缺 segs 声明（无法比对段数）" % (chapter, lab_id))
                else:
                    row["decl_segs"] += int(decl["segs"])
                    if int(decl["segs"]) != data_segs:
                        problems.append("%s/%s: 段数与 levels 声明不符（数据 %d / levels %d）"
                                        % (chapter, lab_id, data_segs, int(decl["segs"])))
            elif declared:
                problems.append("%s/%s: 数据有该 lab，但 levels 未声明" % (chapter, lab_id))
            st = lab_status(cfg, level_status)
            if st not in ("ready", "deferred"):
                problems.append("%s/%s: lab content_status=%r 未知" % (chapter, lab_id, st))
            ready_lab = st == "ready"
            for g in cfg.get("gate_cases") or []:
                row["gates"] += 1
                gid = str(g.get("id", ""))
                if not gid:
                    problems.append("%s/%s: 有 gate 缺 id" % (chapter, lab_id))
                else:
                    key = (chapter, lab_id, gid)
                    if key in seen_ids:
                        problems.append("%s/%s/%s: gate id 重复" % key)
                    seen_ids[key] = True
                if "required" in g and not isinstance(g["required"], bool):
                    problems.append("%s/%s/%s: required 非布尔（%r）" % (chapter, lab_id, gid, g["required"]))
                for k in ("content_status", "status"):
                    if k in g and str(g[k]) not in ("ready", "pending"):
                        problems.append("%s/%s/%s: %s=%r 未知" % (chapter, lab_id, gid, k, g[k]))
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
            if lab_id in declared:
                declared.pop(lab_id)
        for missing in sorted(declared):
            problems.append("%s/%s: levels 声明了该 lab，但数据文件里没有" % (chapter, missing))
        per_chapter[chapter] = row
    return per_chapter, pending_list, section_deferred_list, optional_list, problems, skipped


def main():
    per_chapter, pending, section_deferred, optional, problems, skipped = scan()
    print("file                     labs  data_gates  level_gates  data_segs  level_segs  "
          "pending  section_def  optional  counted")
    for chapter, r in per_chapter.items():
        print("%-24s %4d  %10d  %11d  %9d  %10d  %7d  %11d  %8d  %7d"
              % (chapter, r["labs"], r["gates"], r["decl_gates"], r["segs"], r["decl_segs"],
                 r["pending"], r["section_deferred"], r["optional"], r["counted"]))
    total = {k: sum(r[k] for r in per_chapter.values())
             for k in ("labs", "segs", "gates", "pending", "section_deferred",
                       "optional", "counted", "decl_gates", "decl_segs", "declared_labs")}
    print("TOTAL                    %4d  %10d  %11d  %9d  %10d  %7d  %11d  %8d  %7d"
          % (total["labs"], total["gates"], total["decl_gates"], total["segs"],
             total["decl_segs"], total["pending"], total["section_deferred"],
             total["optional"], total["counted"]))
    for chapter in skipped:
        print()
        print("章节 %s：无 levels 声明（data/chapters/%s_levels.json 不存在），"
              "该章无声明、跳过（不参与 gates/segs 比对）" % (chapter, chapter))
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
    print("（恒等式结构上恒真，只作展示，不作判据；判据是下面的逐条完整性比对）")
    print()
    print("完整性：gate 数据 %d / levels 声明 %d（已声明 lab %d/%d）；"
          "segs 数据 %d / levels 声明 %d"
          % (total["gates"], total["decl_gates"], total["declared_labs"], total["labs"],
             total["segs"], total["decl_segs"]))
    print("segs 声明性质：冻结快照（来源：ac1c428 时刻的 sections 数），用途＝漂移提醒；"
          "不是内容侧应有值。内容侧有意改段数时必须同步改 levels 声明，否则本条会一直红"
          "（预期行为，不许当误报关掉）。")
    if problems:
        print()
        print("账目完整性问题（%d 条）：" % len(problems))
        for p in problems:
            print("  %s" % p)
    ok = total["gates"] == total["counted"] + total["pending"] + excluded and not problems
    print("验算：%s" % ("闭合" if ok else "不闭合"))
    if not ok:
        sys.exit(1)


if __name__ == "__main__":
    main()
