#!/usr/bin/env bash
# 一次性登记一个新 Worker：所有权行 + 模块依赖 + agent 文件，然后跑校验。
#
#   add-worker.sh <worker-id> <module> [paths,comma] [--dry-run]
#
# 例：add-worker.sh worker-user user modules/user/**,tests/modules/user/**
#
# 幂等：已存在的行/文件会跳过；改动前备份为 <file>.bak-<时间戳>。

set -u
WORKER="${1:-}"
MODULE="${2:-}"
PATHS="${3:-}"
DRY=0
[ "${3:-}" = "--dry-run" ] && { DRY=1; PATHS=""; }

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1; shift ;;
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
    *) shift ;;
  esac
done

[ -n "$WORKER" ] && [ -n "$MODULE" ] || {
  printf '用法: add-worker.sh <worker-id> <module> [paths,comma] [--dry-run]\n' >&2; exit 2; }

[[ "$WORKER" =~ ^[a-z0-9][a-z0-9-]*$ ]] || { printf 'worker-id 只能用小写字母/数字/连字符\n' >&2; exit 2; }
[[ "$MODULE" =~ ^[a-z0-9][a-z0-9-]*$ ]] || { printf 'module 只能用小写字母/数字/连字符\n' >&2; exit 2; }

[ -d .agent ] || { printf '错误: 当前目录不是脚手架项目（缺少 .agent/）\n' >&2; exit 2; }
[ -f .agent/file-ownership.md ] || { printf '错误: 缺少 .agent/file-ownership.md\n' >&2; exit 2; }
[ -f .agent/project-dependencies.yaml ] || { printf '错误: 缺少 .agent/project-dependencies.yaml\n' >&2; exit 2; }
[ -f docs/agents/worker-template.md ] || { printf '错误: 缺少 docs/agents/worker-template.md\n' >&2; exit 2; }

[ -n "$PATHS" ] || PATHS="modules/$MODULE/**"
STAMP="$(date +%Y%m%d-%H%M%S)"

python3 - "$WORKER" "$MODULE" "$PATHS" "$DRY" "$STAMP" <<'PY'
import os, re, shutil, subprocess, sys

worker, module, paths_raw, dry, stamp = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4] == "1", sys.argv[5]
paths = [p.strip() for p in paths_raw.split(",") if p.strip()]
changed, skipped = [], []

def backup(p):
    if not dry and os.path.exists(p):
        shutil.copy2(p, p + ".bak-" + stamp)

def read(p):
    with open(p, encoding="utf-8") as f:
        return f.read()

def write(p, s):
    if dry:
        print("  [dry-run] 将写入 %s" % p)
        return
    backup(p)
    with open(p, "w", encoding="utf-8") as f:
        f.write(s)

def eprint(*a):
    print(*a, file=sys.stderr)

# ---- 1) 所有权 ----
own_p = ".agent/file-ownership.md"
own = read(own_p)
rows = []
seen = set()

def want(p):
    if p in seen:
        return
    seen.add(p)
    if re.search(r"^\|\s*`" + re.escape(p) + r"`\s*\|", own, re.M):
        skipped.append("ownership: " + p)
        return
    rows.append(p)

for p in paths:
    want(p)
for p in ("tests/modules/%s/**" % module, "contracts/%s/**" % module):
    want(p)

if rows:
    lines = own.rstrip("\n").split("\n")
    last = max(i for i, l in enumerate(lines) if l.strip().startswith("| `"))
    add = ["| `%s` | %s | %s |" % (p, worker,
            "模块实现" if p.startswith("modules/") else
            "模块测试" if p.startswith("tests/") else "模块契约")
           for p in rows]
    lines[last+1:last+1] = add
    write(own_p, "\n".join(lines) + "\n")
    changed.append("ownership +%d 行" % len(add))
else:
    eprint("  skip   ownership（已存在）")

# ---- 2) 模块依赖 ----
deps_p = ".agent/project-dependencies.yaml"
deps = read(deps_p)
if re.search(r"^\s*-\s*id:\s*" + re.escape(module) + r"\s*$", deps, re.M):
    eprint("  skip   project-dependencies（模块已存在）")
else:
    block = (
        "  - id: %s\n"
        "    owner: %s\n"
        "    paths: [%s]\n"
        "    deps: [shared]\n"
        "    publishes: [contracts/%s/v1.yaml]\n"
        "    consumes: []\n" % (module, worker, paths[0], module)
    )
    lines = deps.split("\n")
    anchor = None
    in_modules = False
    for i, l in enumerate(lines):
        if re.match(r"^modules:\s*$", l):
            in_modules = True
            continue
        if in_modules and re.match(r"^[a-zA-Z]", l) and not l.startswith(" "):
            anchor = i
            break
    if anchor is None:
        # 没有后续顶层键：追加到文件末尾
        deps = deps.rstrip("\n") + "\n" + block
    else:
        lines[anchor:anchor] = block.rstrip("\n").split("\n") + [""]
        deps = "\n".join(lines)
    # 语法校验，失败则不写
    try:
        import yaml
        yaml.safe_load(deps)
    except Exception as e:
        eprint("  错误: 插入后 YAML 解析失败，未写入：%s" % e)
        sys.exit(3)
    write(deps_p, deps)
    changed.append("project-dependencies +1 模块")

# ---- 3) agent 文件 ----
tpl = read("docs/agents/worker-template.md")
forbid = ["shared/**"]
try:
    import yaml
    d = yaml.safe_load(read(deps_p)) or {}
    for m in d.get("modules") or []:
        if m.get("id") and m["id"] != module:
            forbid.append("modules/%s/**" % m["id"])
except Exception:
    pass

agent = (tpl
         .replace("<worker-id>", worker)
         .replace("<module>", module)
         .replace("<allowed_paths>", ", ".join(paths))
         .replace("<forbidden_paths>", ", ".join(forbid))
         .replace("<consumed contracts>", "见 .agent/project-dependencies.yaml"))
out = ".opencode/agents/%s.md" % worker
if os.path.exists(out):
    eprint("  skip   %s（已存在）" % out)
else:
    if not dry:
        os.makedirs(".opencode/agents", exist_ok=True)
    write(out, agent)
    changed.append(out)

print()
if dry:
    print("dry-run：未写入任何文件。抽样预览：")
    print("  worker: %s\n  module: %s\n  paths:  %s\n  forbid: %s" %
          (worker, module, ", ".join(paths), ", ".join(forbid)))
else:
    print("已处理 %d 项：%s" % (len(changed), "; ".join(changed) if changed else "无改动"))
    if skipped:
        print("跳过 %d 项（已存在）" % len(skipped))
PY
rc=$?

if [ "$rc" -ne 0 ]; then exit "$rc"; fi
if [ "$DRY" -eq 0 ] && [ -x scripts/validate.sh ]; then
  echo
  echo "--- validate ---"
  bash scripts/validate.sh --project . | tail -6 || true
fi
cat <<'NEXT'

下一步：
1. 写 contracts/<module>/v1.yaml，status 改 approved
2. 在 .agent/task-dag.yaml 里加任务，owner 填 <worker-id>
3. 启动：git worktree add ../worktrees/<worker-id> -b feature/<module>-<task-id>
         cd ../worktrees/<worker-id> && opencode run --agent <worker-id> --title <task-id> "…"
NEXT