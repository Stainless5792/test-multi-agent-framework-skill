#!/usr/bin/env bash
# 在 iTerm2 新标签页启动一个 Worker：校验任务、生成派发包、建 worktree、写入启动命令。
#
#   dispatch-worker.sh --worker <id> --task <task-id> [选项]
#
#   --worker ID        worker agent id，必须存在 .opencode/agents/<id>.md
#   --task ID          .agent/task-dag.yaml 里的任务 id
#   --branch NAME      分支名，默认 feature/<module>-<task-id>
#   --worktree DIR     worktree 路径，默认 ../worktrees/<worker-id>
#   --base REF         worktree 起点，默认 HEAD
#   --no-worktree      不建 worktree，直接在项目根启动
#   --allow-unready    任务状态不是 ready 也放行（应急用）
#   --run              真正执行：建 worktree 并打开 iTerm2 标签页
#   --print-script F   把 AppleScript 另存为 F，便于检查
#   -h, --help         显示本帮助
#
# 默认只打印计划：不建 worktree、不开标签页、不写项目文件。确认无误再加 --run。
# --run 只在 macOS + iTerm2 下支持；首次执行会被系统询问「自动化」权限。

set -u

PROJECT="$PWD"
WORKER=""
TASK=""
BRANCH=""
WORKTREE=""
BASE="HEAD"
NO_WORKTREE=0
ALLOW_UNREADY=0
RUN=0
SCRIPT_OUT=""

die() { printf '错误: %s\n' "$*" >&2; exit 2; }
say() { printf '%s\n' "$*"; }
warn() { printf 'WARN  %s\n' "$*" >&2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --worker)         WORKER="${2:-}"; shift 2 ;;
    --task)           TASK="${2:-}"; shift 2 ;;
    --branch)         BRANCH="${2:-}"; shift 2 ;;
    --worktree)       WORKTREE="${2:-}"; shift 2 ;;
    --base)           BASE="${2:-}"; shift 2 ;;
    --no-worktree)    NO_WORKTREE=1; shift ;;
    --allow-unready)  ALLOW_UNREADY=1; shift ;;
    --run)            RUN=1; shift ;;
    --print-script)   SCRIPT_OUT="${2:-}"; shift 2 ;;
    -h|--help)        sed -n '2,18p' "$0"; exit 0 ;;
    *)                die "未知参数: $1（--help 看用法）" ;;
  esac
done

[ -n "$WORKER" ] || die "缺少 --worker"
[ -n "$TASK" ] || die "缺少 --task"
[ -d "$PROJECT/.agent" ] || die "当前目录不是框架项目根（缺 .agent/）"
[ -f "$PROJECT/.opencode/agents/$WORKER.md" ] || die "没有 agent: .opencode/agents/$WORKER.md"

DAG="$PROJECT/.agent/task-dag.yaml"
[ -f "$DAG" ] || die "缺少 .agent/task-dag.yaml"

command -v python3 >/dev/null 2>&1 || die "需要 python3"
python3 -c 'import yaml' 2>/dev/null || die "需要 PyYAML（python3 -c 'import yaml'）"

# ---- 读任务并生成派发包 ------------------------------------------------------
packet_final="$PROJECT/.agent/logs/packets/$WORKER-$TASK-$(date +%Y%m%d-%H%M%S).md"
packet_write="$(mktemp "${TMPDIR:-/tmp}/maf-packet.XXXXXX")" || die "无法创建临时文件"
trap 'rm -f "$packet_write"' EXIT

meta="$(python3 - "$TASK" "$DAG" "$packet_write" "$WORKER" <<'PY'
import os, sys
task_id, dag_path, out_path, worker = sys.argv[1:5]
import yaml

d = yaml.safe_load(open(dag_path, encoding="utf-8")) or {}
task = next((t for t in d.get("tasks", []) if t.get("id") == task_id), None)
if task is None:
    print("任务 %s 不在 %s" % (task_id, dag_path), file=sys.stderr)
    sys.exit(1)

problems = []
contracts = task.get("contracts") or []
for c in contracts:
    p = os.path.join(os.getcwd(), c)
    if not os.path.exists(p):
        problems.append("契约不存在: %s" % c)
        continue
    status = (yaml.safe_load(open(p, encoding="utf-8")) or {}).get("contract", {}).get("status")
    if status != "approved":
        problems.append("契约 %s 状态是 %s（ready 任务应为 approved）" % (c, status))

def lines(items):
    return "\n".join("- %s" % x for x in items) if items else "- 无"

packet = """# 派发包 {tid} → {worker}

## 目标
{tid}: {title}
模块: {module}

{acceptance}

## 依赖
{deps}

## 路径
允许:
{allowed}

禁止:
{forbidden}

## 契约
{contracts}

## 验证命令
{verify}

## 停止条件
契约要改 / 需要越界 / 需要动共享层 / 需要新依赖 / 验证命令无法执行 /
上游契约有歧义 → 停手，按 docs/protocol/agent-protocol.md 写提案或报告。

开工前先读 .agent/inbox/{worker}.md；回答末尾必须给「## 下一步」。
""".format(
    tid=task_id,
    worker=worker,
    title=task.get("title", ""),
    module=task.get("module", ""),
    acceptance=lines(task.get("acceptance") or []),
    deps=lines(task.get("deps") or []),
    allowed=lines(task.get("allowed_paths") or []),
    forbidden=lines(task.get("forbidden_paths") or []),
    contracts=lines(contracts),
    verify=lines(task.get("verify_cmds") or []),
)

os.makedirs(os.path.dirname(out_path), exist_ok=True)
open(out_path, "w", encoding="utf-8").write(packet)

print("state\t%s" % task.get("state", ""))
print("owner\t%s" % task.get("owner", ""))
print("module\t%s" % task.get("module", ""))
for p in problems:
    print("problem\t%s" % p)
PY
)" || die "读取任务失败: $TASK"

STATE=""; OWNER=""; MODULE=""; PROBLEMS=""
while IFS=$'\t' read -r k v; do
  case "$k" in
    state)   STATE="$v" ;;
    owner)   OWNER="$v" ;;
    module)  MODULE="$v" ;;
    problem) PROBLEMS="${PROBLEMS}${v}
" ;;
  esac
done <<< "$meta"

[ -n "$STATE" ] || die "任务 $TASK 没有读到，检查 .agent/task-dag.yaml"
[ -z "$PROBLEMS" ] || die "$(printf '%s' "$PROBLEMS")"
[ "$STATE" = "ready" ] || [ "$ALLOW_UNREADY" -eq 1 ] || die "任务 $TASK 状态是 ${STATE}，只有 ready 才派发（应急加 --allow-unready）"
[ "$OWNER" = "$WORKER" ] || warn "任务 owner 是 ${OWNER}，与 --worker $WORKER 不一致"

# ---- 分支与 worktree ---------------------------------------------------------
[ -n "$MODULE" ] || MODULE="$(basename "$WORKER" | sed 's/^worker-//')"
[ -n "$BRANCH" ] || BRANCH="feature/$MODULE-$TASK"
[ -n "$WORKTREE" ] || WORKTREE="../worktrees/$WORKER"
case "$WORKTREE" in
  /*) WT_ABS="$WORKTREE" ;;
  *)  WT_ABS="$(cd "$PROJECT" && python3 -c 'import os,sys;print(os.path.abspath(sys.argv[1]))' "$WORKTREE")" ;;
esac
[ -n "$WT_ABS" ] || WT_ABS="$PROJECT/$WORKTREE"

if [ "$NO_WORKTREE" -eq 1 ]; then
  TARGET_DIR="$PROJECT"
else
  TARGET_DIR="$WT_ABS"
fi

# 已有同名目录可能属于别的仓库（默认路径 ../worktrees/<worker> 会在多个项目间撞名）。
common_dir() {
  local _d
  _d="$(git -C "$1" rev-parse --git-common-dir 2>/dev/null)" || return 1
  case "$_d" in
    /*) printf '%s' "$_d" ;;
    *)  printf '%s' "$(cd "$1" && cd "$_d" && pwd)" ;;
  esac
}
if [ "$NO_WORKTREE" -eq 0 ] && [ -d "$WT_ABS" ]; then
  proj_common="$(common_dir "$PROJECT")" || die "当前目录不是 git 仓库"
  wt_common="$(common_dir "$WT_ABS")" || die "worktree 路径已存在但不是 git 仓库: ${WT_ABS}（换 --worktree，或先移走）"
  [ "$proj_common" = "$wt_common" ] || die "worktree 路径属于另一个仓库: ${WT_ABS}（换 --worktree，或先移走）"
  wt_branch="$(git -C "$WT_ABS" branch --show-current 2>/dev/null)"
  [ "$wt_branch" = "$BRANCH" ] || warn "worktree 当前分支是 ${wt_branch:-detached}，不是 ${BRANCH}，脚本会直接复用它"
fi

# ---- 组装命令与 AppleScript --------------------------------------------------
shq() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }

run_cmd="cd $(shq "$TARGET_DIR") && opencode run --agent $(shq "$WORKER") --title $(shq "$TASK") \"\$(cat $(shq "$packet_final"))\""

as_escape() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }

ascript="tell application \"iTerm2\"
  activate
  if (count of windows) = 0 then
    create window with default profile
  else
    tell current window to create tab with default profile
  end if
  tell current session of current window
    write text \"$(as_escape "$run_cmd")\"
  end tell
end tell"

[ -n "$SCRIPT_OUT" ] && printf '%s\n' "$ascript" > "$SCRIPT_OUT" && say "AppleScript 已写入 $SCRIPT_OUT"

# ---- 干跑：只打印计划 --------------------------------------------------------
if [ "$RUN" -eq 0 ]; then
  say "任务: ${TASK}（状态 ${STATE}，owner ${OWNER}，模块 ${MODULE}）"
  say "派发包（预览，未落盘）:"
  sed 's/^/  /' "$packet_write"
  if [ "$NO_WORKTREE" -eq 0 ]; then
    if git -C "$PROJECT" show-ref --verify --quiet "refs/heads/$BRANCH"; then
      say "worktree: git worktree add $(shq "$WT_ABS") $(shq "$BRANCH")   # 分支已存在，直接检出"
    else
      say "worktree: git worktree add $(shq "$WT_ABS") -b $(shq "$BRANCH") $(shq "$BASE")"
    fi
  else
    say "worktree: 跳过（--no-worktree）"
  fi
  say "新标签页将执行:"
  say "  $run_cmd"
  say ""
  say "确认无误后加 --run 执行（会建 worktree 并打开 iTerm2 标签页）。"
  exit 0
fi

# ---- 真跑 --------------------------------------------------------------------
[ "$(uname -s)" = "Darwin" ] || die "--run 只支持 macOS"
[ -d /Applications/iTerm.app ] || die "没有找到 iTerm2（/Applications/iTerm.app）"
command -v osascript >/dev/null 2>&1 || die "缺少 osascript"
command -v opencode >/dev/null 2>&1 || warn "PATH 里没有 opencode，新标签页可能启动失败"

if [ "$NO_WORKTREE" -eq 0 ] && [ ! -d "$WT_ABS" ]; then
  if git -C "$PROJECT" show-ref --verify --quiet "refs/heads/$BRANCH"; then
    git -C "$PROJECT" worktree add "$WT_ABS" "$BRANCH" || die "建 worktree 失败"
  else
    git -C "$PROJECT" worktree add "$WT_ABS" -b "$BRANCH" "$BASE" || die "建 worktree 失败"
  fi
fi
mkdir -p "$(dirname "$packet_final")"
mv "$packet_write" "$packet_final" || die "写派发包失败"

osascript -e "$ascript" || die "AppleScript 执行失败（检查系统设置 → 隐私与安全性 → 自动化）"
say "已在 iTerm2 新标签页启动 ${WORKER}（${TASK}）"
say "派发包: $packet_final"
say "分支: $BRANCH  worktree: $TARGET_DIR"