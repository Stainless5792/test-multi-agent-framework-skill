#!/usr/bin/env bash
# 查看所有 Worker 状态。优先用 maf-dashboard（Go 二进制），没有则退化为轻量表格。
#
#   status.sh [项目目录] [--json]
#
# 环境变量 MAF_DASHBOARD 可指定二进制路径。

set -u
DIR="${1:-.}"
shift || true
if [ -d "$DIR" ]; then cd "$DIR" || exit 2; fi
[ -d .agent ] || { printf '错误: 当前目录不是脚手架项目（缺少 .agent/）\n' >&2; exit 2; }

BIN="${MAF_DASHBOARD:-maf-dashboard}"
if command -v "$BIN" >/dev/null 2>&1; then
  exec "$BIN" --dir . --once
fi

printf '（未找到 maf-dashboard，退回轻量视图；安装：install.sh --with-dashboard）\n\n'
python3 - <<'PY'
import glob, os, subprocess, sys
try:
    import yaml
except ImportError:
    print("需要 python3 + PyYAML"); sys.exit(0)

def git(*a):
    return subprocess.run(["git", *a], capture_output=True, text=True).stdout.strip()

dag = {}
if os.path.exists(".agent/task-dag.yaml"):
    dag = yaml.safe_load(open(".agent/task-dag.yaml")) or {}
tasks = dag.get("tasks", [])
wts = []
for block in git("worktree", "list", "--porcelain").split("\n\n"):
    path = branch = ""
    for line in block.splitlines():
        if line.startswith("worktree "):
            path = line[9:]
        elif line.startswith("branch refs/heads/"):
            branch = line[18:]
    if path:
        wts.append((path, branch))

def match(module, tid):
    want = "feature/%s-%s" % (module, tid)
    for p, b in wts:
        if b == want:
            return p, b
    for p, b in wts:
        if tid.lower() in b.lower():
            return p, b
    return None, None

base = "main"
if os.path.exists(".agent/project-profile.yaml"):
    prof = yaml.safe_load(open(".agent/project-profile.yaml")) or {}
    base = (prof.get("project") or {}).get("default_branch") or "main"

print("%-16s %-14s %-12s %-24s %5s %5s" % ("TASK", "OWNER", "STATE", "BRANCH", "AHEAD", "DIRTY"))
for t in tasks:
    p, b = match(t.get("module", ""), t.get("id", ""))
    ahead = dirty = "-"
    if p:
        ahead = git("-C", p, "rev-list", "--count", "%s..HEAD" % base) or "0"
        dirty = "yes" if git("-C", p, "status", "--porcelain") else "no"
    print("%-16s %-14s %-12s %-24s %5s %5s" % (
        t.get("id", "-"), t.get("owner", "-"), t.get("state", "-"),
        b or "-", ahead, dirty))
print("\n（轻量视图不计算信号与合并门；完整信息用 maf-dashboard）")
PY