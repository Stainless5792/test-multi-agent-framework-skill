#!/usr/bin/env bash
# 校验脚手架的结构与就绪度。
#
#   validate.sh [--project DIR] [--strict]
#
# 结构错误（缺文件、状态非法、合法路径重叠、契约引用悬空）永远失败。
# 未填的门禁命令（TBD）默认只告警，--strict 时判失败（用于 CI）。

set -u

PROJECT="$PWD"
STRICT=0
FAIL=0
WARN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --project) PROJECT="${2:-}"; shift 2 ;;
    --strict) STRICT=1; shift ;;
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
    *) printf '未知参数: %s\n' "$1" >&2; exit 2 ;;
  esac
done

[ -d "$PROJECT" ] || { printf '错误: 目录不存在 %s\n' "$PROJECT" >&2; exit 2; }
cd "$PROJECT" || exit 2

fail() { printf 'FAIL  %s\n' "$1"; FAIL=$((FAIL + 1)); }
warn() { printf 'WARN  %s\n' "$1"; WARN=$((WARN + 1)); }
ok()   { printf 'ok    %s\n' "$1"; }

# ---- 必需文件 ----------------------------------------------------------------
required="
AGENTS.md
.agent/project-profile.yaml
.agent/project-dependencies.yaml
.agent/file-ownership.md
.agent/task-dag.yaml
.agent/quality-gates.yaml
docs/protocol/agent-protocol.md
docs/contracts/contract-format.md
docs/architecture/contract-ownership.md
.opencode/agents/orchestrator.md
.opencode/agents/reviewer.md
docs/agents/worker-template.md
scripts/contract-check.sh
scripts/ownership-check.sh
scripts/integration-check.sh
"
for f in $required; do
  [ -e "$f" ] && continue
  case "$f" in
    .agent/project-dependencies.yaml|.agent/task-dag.yaml)
      warn "缺少 $f（单模块项目可接受）" ;;
    *) fail "缺少 $f" ;;
  esac
done

grep -q 'maf:begin' AGENTS.md 2>/dev/null && ok "AGENTS.md 含协作规则段" || fail "AGENTS.md 没有 maf:begin 标记"

# ---- Agent 布局 --------------------------------------------------------------
if [ -d .opencode/agents ]; then
  nested="$(find .opencode/agents -mindepth 2 -name '*.md' 2>/dev/null)"
  [ -z "$nested" ] || fail "agent 文件被放进子目录（ID 会变成 子目录/名字）: $nested"
  for a in orchestrator reviewer; do
    [ -f ".opencode/agents/$a.md" ] || fail "缺少 agent: .opencode/agents/$a.md"
  done
  n_workers="$(ls .opencode/agents/worker-*.md 2>/dev/null | grep -v 'worker-template' | wc -l | tr -d ' ')"
  [ "$n_workers" -ge 1 ] && ok "worker agent: $n_workers 个" || warn "还没有 worker-<module>.md（第 4 步生成）"
fi

# ---- 结构与就绪（python3 + PyYAML）------------------------------------------
if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' 2>/dev/null; then
  pyout="$(python3 - "$STRICT" <<'PY'
import sys, os, glob, re
strict = sys.argv[1] == "1"
fails, warns = [], []

def load(p):
    import yaml
    with open(p, encoding="utf-8") as f:
        return yaml.safe_load(f) or {}

# ---- file-ownership 重复路径 ----
own = open(".agent/file-ownership.md", encoding="utf-8").read()
rows = re.findall(r"^\|\s*`([^`]+)`\s*\|\s*([^|]+?)\s*\|", own, re.M)
seen = {}
for glob_pat, owner in rows:
    owner = owner.strip()
    if glob_pat in seen and seen[glob_pat] != owner:
        fails.append(f"file-ownership 中 {glob_pat} 有多个所有者: {seen[glob_pat]} / {owner}")
    seen[glob_pat] = owner
if not rows:
    fails.append("file-ownership.md 没有解析到任何路径行")

# ---- task-dag ----
LEGAL = {"backlog","analyzing","ready","in_progress","review","integration","done","blocked"}
dag_p = ".agent/task-dag.yaml"
tasks = load(dag_p).get("tasks", []) if os.path.exists(dag_p) else []
ids = {t.get("id") for t in tasks}
for t in tasks:
    tid = t.get("id", "?")
    st = t.get("state")
    if st not in LEGAL:
        fails.append(f"{tid}: 非法状态 {st}")
    for d in t.get("deps") or []:
        if d not in ids:
            fails.append(f"{tid}: deps 引用了不存在的任务 {d}")
    if not t.get("verify_cmds") or t.get("verify_cmds") in (["TBD"],):
        if st in ("ready","in_progress"):
            fails.append(f"{tid}: 状态 {st} 但没有可执行的 verify_cmds")
    for c in t.get("contracts") or []:
        if not os.path.exists(c):
            if st in ("ready", "in_progress"):
                fails.append(f"{tid}: {st} 但契约文件不存在 {c}")
            else:
                warns.append(f"{tid}: 契约待创建 {c}（状态 {st}，暂不算失败）")
        else:
            ct = load(c).get("contract", {})
            if st in ("ready","in_progress") and ct.get("status") != "approved":
                fails.append(f"{tid}: {st} 但契约 {c} 状态是 {ct.get('status')}")
    if st == "blocked" and not t.get("blocked_by"):
        fails.append(f"{tid}: blocked 但没有写 blocked_by")

# ---- 并行任务路径重叠 ----
def norm(p):
    return p.rstrip("/")
active = [t for t in tasks if t.get("state") == "in_progress"]
for i, a in enumerate(active):
    for b in active[i+1:]:
        pa = {norm(x) for x in (a.get("allowed_paths") or [])}
        pb = {norm(x) for x in (b.get("allowed_paths") or [])}
        for x in pa:
            for y in pb:
                if x == y or x.startswith(y + "/") or y.startswith(x + "/"):
                    fails.append(f"路径重叠: {a['id']} 与 {b['id']} 都写 {x} / {y}")

# ---- 契约 ----
conts = [p for p in glob.glob("contracts/*/v*.yaml")]
for p in conts:
    c = load(p).get("contract", {})
    if c.get("status") not in ("draft","approved","deprecated"):
        fails.append(f"{p}: 非法 status {c.get('status')}")
    if not c.get("owner"):
        fails.append(f"{p}: 缺 owner")
if not conts:
    warns.append("还没有任何契约文件（contracts/<module>/v1.yaml）")

# ---- 门禁 TBD ----
qg_p = ".agent/quality-gates.yaml"
if os.path.exists(qg_p):
    qg = load(qg_p)
    tbd = [g.get("id") for g in qg.get("gates", []) if str(g.get("command","")).strip() in ("TBD","")]
    if tbd:
        msg = f"{len(tbd)} 道门禁仍是 TBD（{', '.join(tbd)}）"
        (fails if strict else warns).append(msg)

for m in fails: print("FAIL  " + m)
for m in warns: print("WARN  " + m)
sys.exit(1 if fails else 0)
PY
)"
  rc=$?
  printf '%s\n' "$pyout" | grep -E '^(FAIL|WARN)' || true
  n_f=$(printf '%s\n' "$pyout" | grep -c '^FAIL' || true)
  n_w=$(printf '%s\n' "$pyout" | grep -c '^WARN' || true)
  FAIL=$((FAIL + n_f))
  WARN=$((WARN + n_w))
  [ "$rc" -eq 0 ] && ok "结构与就绪检查通过"
else
  warn "没有 python3+PyYAML，跳过结构与就绪检查"
fi

# ---- OpenCode 是否真的加载了 agent ------------------------------------------
if command -v opencode >/dev/null 2>&1; then
  ids="$(opencode debug agents 2>/dev/null | grep -o '"id": *"[^"]*"' | sed 's/.*"\([^"]*\)"$/\1/')"
  if [ -n "$ids" ]; then
    for a in orchestrator reviewer; do
      echo "$ids" | grep -qx "$a" && ok "opencode 已加载 agent: $a" || fail "opencode 未加载 agent: $a"
    done
  else
    warn "opencode 没有返回 agent 列表，跳过实时检查"
  fi
else
  warn "未安装 opencode，跳过实时检查"
fi

printf '\n结果: %d 个失败, %d 个警告\n' "$FAIL" "$WARN"
[ "$FAIL" -eq 0 ] || exit 1