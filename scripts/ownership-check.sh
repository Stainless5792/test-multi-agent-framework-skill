#!/usr/bin/env bash
# 越界检查：把 diff 里的文件映射到 file-ownership.md 的所有者。
#
#   ownership-check.sh [base] [head] [--owner ID] [--worktree] [--project DIR]
#
# 判定：无主路径 = 失败；同一路径命中两个不同所有者 = 失败；
#       指定 --owner 时，任何不属于该所有者的文件 = 失败。

set -u
PROJECT="$PWD"
BASE=""
HEAD=""
EXPECT=""
WORKTREE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --owner) EXPECT="${2:-}"; shift 2 ;;
    --worktree) WORKTREE=1; shift ;;
    --project) PROJECT="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
    -*) printf '未知参数: %s\n' "$1" >&2; exit 2 ;;
    *)
      if [ -z "$BASE" ]; then BASE="$1"; elif [ -z "$HEAD" ]; then HEAD="$1"; else
        printf '多余参数: %s\n' "$1" >&2; exit 2
      fi
      shift ;;
  esac
done

cd "$PROJECT" 2>/dev/null || { printf '错误: 目录不存在 %s\n' "$PROJECT" >&2; exit 2; }
git rev-parse --git-dir >/dev/null 2>&1 || { printf '错误: 不是 git 仓库\n' >&2; exit 2; }

[ -f .agent/file-ownership.md ] || { printf '错误: 缺少 .agent/file-ownership.md\n' >&2; exit 2; }
[ -n "$BASE" ] || BASE="origin/main"
git rev-parse --verify -q "$BASE" >/dev/null 2>&1 || BASE="HEAD"
[ -n "$HEAD" ] || HEAD="HEAD"

python3 - "$BASE" "$HEAD" "$EXPECT" "$WORKTREE" <<'PY'
import sys, os, subprocess, re, fnmatch
base, head, expect, worktree = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4] == "1"

def sh(args):
    return subprocess.run(args, capture_output=True, text=True).stdout

files = [f for f in sh(["git", "diff", "--name-only", f"{base}..{head}"]).splitlines() if f]
if worktree or head == "HEAD":
    files += [f for f in sh(["git", "diff", "--name-only"]).splitlines() if f]
    files += [f for f in sh(["git", "ls-files", "--others", "--exclude-standard"]).splitlines() if f]
files = sorted(set(files))

rows = re.findall(r"^\|\s*`([^`]+)`\s*\|\s*([^|]+?)\s*\|\s*([^|]*)\|?",
                  open(".agent/file-ownership.md", encoding="utf-8").read(), re.M)
rules = [(g.strip(), o.strip()) for g, o, _ in rows if g.strip() and o.strip()]

def candidates(path):
    hits = []
    for pat, owner in rules:
        if fnmatch.fnmatch(path, pat) or fnmatch.fnmatch(path, pat + "/**"):
            hits.append((len(pat), owner))
    if not hits:
        return []
    best = max(h[0] for h in hits)
    return sorted({o for ln, o in hits if ln == best})

if not files:
    print("没有需要检查的改动")
    sys.exit(0)

fails, unknown = [], []
print(f"{'文件':<58} 所有者")
for f in files:
    owners = candidates(f)
    if not owners:
        print(f"{f:<58} <无主>")
        unknown.append(f)
    elif len(owners) > 1:
        print(f"{f:<58} {', '.join(owners)}  <- 冲突")
        fails.append(f"{f}: 同时命中多个所有者 {owners}")
    else:
        print(f"{f:<58} {owners[0]}")
        if expect and owners[0] != expect:
            fails.append(f"{f}: 属于 {owners[0]}，本次提交声称是 {expect}")

for f in unknown:
    fails.append(f"{f}: 没有任何所有者（先在 file-ownership.md 里登记，再改）")

print()
if fails:
    for m in fails:
        print("FAIL  " + m)
    print(f"\n越界或未登记: {len(fails)} 项")
    sys.exit(1)
print(f"全部 {len(files)} 个文件都在所有权范围内")
PY