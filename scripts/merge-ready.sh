#!/usr/bin/env bash
# 合并前检查（纯 bash 兜底；有 maf-dashboard 时用 --check-merge 更好）。
#
#   merge-ready.sh <TASK-ID> [--base BRANCH] [--run-gates]
#
# 九条全过才输出 GO。任何 FAIL 退出码为 1。

set -u
TASK="${1:-}"
shift || true
BASE=""
RUN_GATES=0
while [ $# -gt 0 ]; do
  case "$1" in
    --base) BASE="${2:-}"; shift 2 ;;
    --run-gates) RUN_GATES=1; shift ;;
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
    *) printf '未知参数: %s\n' "$1" >&2; exit 2 ;;
  esac
done
[ -n "$TASK" ] || { printf '用法: merge-ready.sh <TASK-ID> [--base BRANCH] [--run-gates]\n' >&2; exit 2; }

command -v python3 >/dev/null 2>&1 || { printf '需要 python3\n' >&2; exit 2; }

python3 - "$TASK" "$BASE" "$RUN_GATES" <<'PY'
import os, re, subprocess, sys, glob
task_id, base, run_gates = sys.argv[1], sys.argv[2], sys.argv[3] == "1"

try:
    import yaml
except ImportError:
    print("需要 PyYAML"); sys.exit(2)

def git(*a, cwd=None):
    r = subprocess.run(["git", *a], capture_output=True, text=True, cwd=cwd)
    return r.returncode == 0, r.stdout.strip()

dag = yaml.safe_load(open(".agent/task-dag.yaml")) or {}
tasks = {t.get("id"): t for t in dag.get("tasks", [])}
t = tasks.get(task_id)
if not t:
    print(f"找不到任务 {task_id}"); sys.exit(2)

prof = yaml.safe_load(open(".agent/project-profile.yaml")) or {}
base = base or (prof.get("project") or {}).get("default_branch") or "main"

# 找 worktree
want = f"feature/{t.get('module')}-{task_id}"
worktree, branch = "", ""
ok, out = git("worktree", "list", "--porcelain")
for block in out.split("\n\n"):
    p = b = ""
    for line in block.splitlines():
        if line.startswith("worktree "): p = line[9:]
        elif line.startswith("branch refs/heads/"): b = line[18:]
    if b == want or (not branch and task_id.lower() in b.lower()):
        worktree, branch = p, b

checks = []
def add(name, ok, note=""):
    checks.append((name, bool(ok), note))

add("任务状态", t.get("state") in ("review", "integration"), t.get("state", "-"))
ahead = 0
dirty = True
if worktree:
    ok, out = git("-C", worktree, "rev-list", "--count", f"{base}..HEAD")
    ahead = int(out) if ok and out.isdigit() else 0
    ok, out = git("-C", worktree, "status", "--porcelain")
    dirty = bool(out)
add("分支领先 base", ahead > 0, f"{ahead} 个提交")
add("工作区干净", worktree and not dirty, "有未提交改动" if dirty else "")

owner = t.get("owner", "")
delivery_rel = "docs/reviews/deliveries/%s/%s-delivery.md" % (owner, task_id)
delivery_path = ""
# 交付报告在 worker 的 worktree 里，合并前还没进主仓库。先查 worktree，主仓库只作回退。
for root in ([worktree] if worktree else []) + ["."]:
    for cand in (delivery_rel, "docs/reviews/%s-delivery.md" % task_id):
        p2 = os.path.join(root, cand)
        if os.path.exists(p2):
            delivery_path, delivery_rel = p2, cand
            break
    if delivery_path:
        break
ready_flag = False
if delivery_path:
    s = open(delivery_path, encoding="utf-8").read()
    ready_flag = "VERIFY" in s and "READY_FOR_REVIEW: YES" in s.upper()
add("交付报告", bool(delivery_path) and ready_flag, delivery_rel)

SCRIPT_DIR = os.path.abspath("scripts")

def run_script(name, args):
    if not worktree:
        return False, "没有 worktree"
    # 用编排者这份脚本 + --project 指向 worktree：worker 分支里的 scripts/ 是切分支时的旧版，
    # 拿它跑门禁会让每个分支执行不同版本的规则。
    r = subprocess.run(["bash", os.path.join(SCRIPT_DIR, name), *args, "--project", worktree],
                       capture_output=True, text=True, cwd=worktree)
    lines = [l for l in (r.stdout or r.stderr).strip().splitlines() if l.strip()]
    return r.returncode == 0, (lines[-1] if lines else "")

if worktree:
    # base 可能在开工后前移：越界与契约兼容都只该看「分支自己改了什么」。
    ok_mb, mb = git("-C", worktree, "merge-base", base, "HEAD")
    diff_base = mb if ok_mb and mb else base
    ok5, n5 = run_script("ownership-check.sh", [diff_base, "HEAD", "--owner", t.get("owner", "")])
    add("所有权", ok5, n5)
    ok6, n6 = run_script("contract-check.sh", ["--base", diff_base])
    add("契约兼容", ok6, n6)
    if run_gates:
        ok7, n7 = run_script("integration-check.sh", ["--only", "contract,ownership,unit"])
        add("门禁", ok7, n7)
    else:
        add("门禁", True, "SKIP（--run-gates 才执行）")
else:
    add("工作区", False, "没有找到对应 worktree")

verdict = "missing"
p = f"docs/reviews/{task_id}-review.md"
if os.path.exists(p):
    s = open(p, encoding="utf-8").read().upper()
    if "REQUEST_CHANGES" in s: verdict = "changes"
    elif "APPROVE_WITH_FOLLOWUPS" in s: verdict = "approve_with_followups"
    elif "BLOCKED" in s: verdict = "blocked"
    elif "APPROVE" in s: verdict = "approve"
add("评审结论", verdict in ("approve", "approve_with_followups"), verdict)

pushed = False
if branch:
    ok, out = git("ls-remote", "--heads", "origin", branch)
    pushed = ok and bool(out)
add("分支已推送", pushed, "未在 origin 找到")

print(f"任务 {task_id}（{t.get('owner')} / {t.get('module')}）\n")
allpass = True
for i, (name, ok, note) in enumerate(checks, 1):
    if not ok: allpass = False
    print(f"{'PASS' if ok else 'FAIL'} {i}. {name:<12} {note}")
print()
print("结论: GO" if allpass else "结论: NO-GO")
sys.exit(0 if allpass else 1)
PY