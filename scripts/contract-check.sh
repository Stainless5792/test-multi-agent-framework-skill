#!/usr/bin/env bash
# 契约校验：结构、状态、版本连续性、错误码覆盖、breaking 变更是否走了提案。
#
#   contract-check.sh [--base REV] [--dag] [--gen] [--project DIR]
#     --base  与哪个版本比较（默认 origin/main，没有则 HEAD）
#     --dag   同时校验 project-dependencies.yaml 的 publish/consume 指向
#     --gen   从契约生成 shared/contracts/<module>.py（唯一类型来源）

set -u
PROJECT="$PWD"
BASE=""
DAG=0
GEN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --base) BASE="${2:-}"; shift 2 ;;
    --dag) DAG=1; shift ;;
    --gen) GEN=1; shift ;;
    --project) PROJECT="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
    *) printf '未知参数: %s\n' "$1" >&2; exit 2 ;;
  esac
done

cd "$PROJECT" 2>/dev/null || { printf '错误: 目录不存在 %s\n' "$PROJECT" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { printf '需要 python3\n' >&2; exit 2; }
python3 -c 'import yaml' 2>/dev/null || { printf '需要 PyYAML: python3 -m pip install pyyaml\n' >&2; exit 2; }

if [ -z "$BASE" ]; then
  if git rev-parse --verify -q origin/main >/dev/null 2>&1; then BASE="origin/main"
  elif git rev-parse --verify -q HEAD >/dev/null 2>&1; then BASE="HEAD"
  fi
fi

python3 - "$BASE" "$DAG" "$GEN" <<'PY'
import sys, os, glob, json, subprocess, re
base, do_dag, do_gen = sys.argv[1], sys.argv[2] == "1", sys.argv[3] == "1"
import yaml

fails, warns, notes = [], [], []

def load(p):
    with open(p, encoding="utf-8") as f:
        return yaml.safe_load(f) or {}

def git_show(rev, path):
    if not rev:
        return None
    try:
        out = subprocess.run(["git", "show", f"{rev}:{path}"],
                             capture_output=True, text=True)
        return yaml.safe_load(out.stdout) if out.returncode == 0 and out.stdout.strip() else None
    except Exception:
        return None

paths = sorted(glob.glob("contracts/*/v*.yaml"))
if not paths:
    notes.append("没有契约文件，跳过（第 4 步会创建）")

for p in paths:
    d = load(p)
    c = d.get("contract") or {}
    mod_dir = p.split("/")[1]

    # 1. 必填
    for k in ("name", "module", "version", "status", "owner"):
        if not c.get(k):
            fails.append(f"{p}: 缺 contract.{k}")
    if c.get("module") and c["module"] != mod_dir:
        fails.append(f"{p}: contract.module={c['module']} 与目录 {mod_dir} 不一致")
    fn_ver = os.path.basename(p)[:-5]
    if c.get("version") and c["version"] != fn_ver:
        fails.append(f"{p}: 文件名版本 {fn_ver} 与 contract.version {c['version']} 不一致")
    if c.get("status") not in ("draft", "approved", "deprecated"):
        fails.append(f"{p}: 非法 status {c.get('status')}")

    # 2. 方法
    methods = d.get("methods") or []
    if not methods:
        fails.append(f"{p}: 没有任何 method")
    names = set()
    for m in methods:
        n = m.get("name")
        if not n:
            fails.append(f"{p}: 有 method 缺 name")
            continue
        if n in names:
            fails.append(f"{p}: 重复方法 {n}")
        names.add(n)
        for k in ("input", "output", "errors"):
            if k not in m:
                fails.append(f"{p}: {n} 缺 {k}")

    # 3. 错误码覆盖
    codes = set((d.get("error_codes") or {}).keys())
    for m in methods:
        for e in (m.get("errors") or []):
            if e not in codes:
                fails.append(f"{p}: {m.get('name')} 用了未声明的错误码 {e}")

    # 4. type 引用
    types = d.get("types") or {}
    def walk(node, where):
        if isinstance(node, dict):
            ref = node.get("ref")
            if ref and ref not in types:
                fails.append(f"{p}: {where} 引用未定义类型 {ref}")
            for v in node.values():
                walk(v, where)
        elif isinstance(node, list):
            for v in node:
                walk(v, where)
    walk(types, "types")
    for m in methods:
        walk(m.get("input"), m.get("name"))
        walk(m.get("output"), m.get("name"))

    # 5. breaking 变更需要提案
    old = git_show(base, p) if base else None
    if old:
        oc = old.get("contract") or {}
        old_m = {m.get("name"): m for m in (old.get("methods") or [])}
        new_m = {m.get("name"): m for m in methods}
        breaking = []
        for n in old_m:
            if n not in new_m:
                breaking.append(f"删除方法 {n}")
        old_types = old.get("types") or {}
        for t, fields in old_types.items():
            if t not in types:
                breaking.append(f"删除类型 {t}")
                continue
            for f, spec in (fields or {}).items():
                if f not in (types.get(t) or {}):
                    breaking.append(f"{t}.{f} 被删除")
                elif (spec or {}).get("type") != ((types.get(t) or {}).get(f) or {}).get("type"):
                    breaking.append(f"{t}.{f} 类型变更")
        for code in (old.get("error_codes") or {}):
            if code not in codes:
                breaking.append(f"删除错误码 {code}")
        if breaking:
            proposal_dir = os.path.join(os.path.dirname(p), "proposals")
            accepted = False
            if os.path.isdir(proposal_dir):
                for f in glob.glob(proposal_dir + "/*.md"):
                    txt = open(f, encoding="utf-8").read()
                    if re.search(r"(判定|status)\s*[:：].*accepted", txt, re.I) and os.path.basename(p) in txt:
                        accepted = True
            msg = f"{p}: 相对 {base} 存在 breaking 变更: {', '.join(breaking[:4])}"
            if accepted:
                notes.append("OK（已有 accepted 提案）: " + msg)
            else:
                fails.append(msg)

# 6. --dag：发布/消费的契约必须存在
if do_dag and os.path.exists(".agent/project-dependencies.yaml"):
    deps = load(".agent/project-dependencies.yaml")
    for m in (deps.get("modules") or []):
        for c in (m.get("publishes") or []) + (m.get("consumes") or []):
            if not os.path.exists(c):
                fails.append(f"project-dependencies: {m.get('id')} 指向不存在的契约 {c}")
        for dep in (m.get("deps") or []):
            ids = {x.get("id") for x in (deps.get("modules") or [])} | {"shared"}
            if dep not in ids:
                fails.append(f"project-dependencies: {m.get('id')} 依赖了未知模块 {dep}")

# 7. --gen：生成 shared/contracts/<module>.py
if do_gen:
    os.makedirs("shared/contracts", exist_ok=True)
    tmap = {"string": "str", "integer": "int", "number": "float",
            "boolean": "bool", "object": "dict", "array": "list"}
    for p in paths:
        d = load(p)
        c = (d.get("contract") or {})
        mod = c.get("module") or p.split("/")[1]
        lines = [
            "# 由 scripts/contract-check.sh --gen 生成，不要手工修改。",
            f"# source: {p}  version: {c.get('version')}",
            "from __future__ import annotations",
            "from typing import Literal, Optional",
            "from pydantic import BaseModel",
            "",
        ]
        for tname, fields in (d.get("types") or {}).items():
            lines.append(f"class {tname}(BaseModel):")
            if not fields:
                lines.append("    pass")
            for fname, spec in fields.items():
                spec = spec or {}
                t = spec.get("type")
                if spec.get("enum"):
                    ann = "Literal[" + ", ".join(repr(e) for e in spec["enum"]) + "]"
                else:
                    ann = tmap.get(t, "object")
                if not spec.get("required", False):
                    ann = f"Optional[{ann}] = None"
                lines.append(f"    {fname}: {ann}")
            lines.append("")
        out = f"shared/contracts/{mod}.py"
        with open(out, "w", encoding="utf-8") as f:
            f.write("\n".join(lines))
        notes.append(f"生成 {out}")

# 8. 可选扩展字段：字段存在才校验，老契约不受影响
def check_implementation(p, d, status):
    impl = d.get("implementation")
    if impl is None:
        return
    if not isinstance(impl, dict):
        fails.append(f"{p}: implementation 必须是映射")
        return
    mp = impl.get("module_path")
    if not mp:
        fails.append(f"{p}: implementation 缺 module_path")
    elif not os.path.isdir(mp):
        (fails if status == "approved" else warns).append(
            f"{p}: implementation.module_path 不存在: {mp}")
    fac = impl.get("factory")
    if not fac or ":" not in str(fac):
        fails.append(f"{p}: implementation.factory 必须写成 <import 名>:<类名>")
    if impl.get("bootstrap") not in ("package", "sys_path"):
        fails.append(f"{p}: implementation.bootstrap 只能是 package 或 sys_path")
    req = impl.get("requires")
    if req is None:
        return
    if not isinstance(req, list):
        fails.append(f"{p}: implementation.requires 必须是列表")
        return
    for r in req:
        if not isinstance(r, dict) or not r.get("name"):
            fails.append(f"{p}: implementation.requires 的每一项都要有 name")
            continue
        src = r.get("from")
        if src and not os.path.exists(src):
            fails.append(f"{p}: implementation.requires.{r['name']} 指向不存在的契约 {src}")

def check_error_surface(p, d):
    es = d.get("error_surface")
    if es is None:
        return
    if not isinstance(es, dict):
        fails.append(f"{p}: error_surface 必须是映射")
        return
    if es.get("mechanism") not in ("exception", "return_value"):
        fails.append(f"{p}: error_surface.mechanism 只能是 exception 或 return_value")
    attrs = es.get("attributes")
    if not isinstance(attrs, list) or not attrs:
        fails.append(f"{p}: error_surface.attributes 必须是非空列表")
    dom = es.get("code_domain")
    if dom and dom not in d:
        fails.append(f"{p}: error_surface.code_domain 指向契约内不存在的表 {dom}")

for p in paths:
    d = load(p)
    check_implementation(p, d, (d.get("contract") or {}).get("status"))
    check_error_surface(p, d)

for n in notes: print("note  " + n)
for w in warns: print("WARN  " + w)
for f in fails: print("FAIL  " + f)
print()
print(f"契约: {len(paths)} 份，失败 {len(fails)}")
sys.exit(1 if fails else 0)
PY