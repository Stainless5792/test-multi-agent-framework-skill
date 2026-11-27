#!/usr/bin/env bash
# 按 .agent/quality-gates.yaml 顺序跑门禁，输出证据表。本地与 CI 共用同一脚本。
#
#   integration-check.sh [--only a,b] [--strict] [--project DIR]
#
# 契约门禁在最前（YAML 里已排序），先失败先止损。
# TBD 门禁默认跳过并标 NOT_READY；--strict 时判失败。

set -u
PROJECT="$PWD"
ONLY=""
STRICT=0

while [ $# -gt 0 ]; do
  case "$1" in
    --only) ONLY="${2:-}"; shift 2 ;;
    --strict) STRICT=1; shift ;;
    --project) PROJECT="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    *) printf '未知参数: %s\n' "$1" >&2; exit 2 ;;
  esac
done

cd "$PROJECT" 2>/dev/null || { printf '错误: 目录不存在 %s\n' "$PROJECT" >&2; exit 2; }
QG=".agent/quality-gates.yaml"
[ -f "$QG" ] || { printf '错误: 缺少 %s\n' "$QG" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { printf '需要 python3\n' >&2; exit 2; }

TS="$(date +%Y%m%d-%H%M%S)"
LOG=".agent/logs/$TS"
mkdir -p "$LOG"

python3 - "$QG" "$ONLY" "$STRICT" "$LOG" <<'PY'
import sys, os, subprocess, time, yaml
qg_path, only, strict, logdir = sys.argv[1], sys.argv[2], sys.argv[3] == "1", sys.argv[4]
gates = (yaml.safe_load(open(qg_path, encoding="utf-8")) or {}).get("gates", [])
want = {x.strip() for x in only.split(",") if x.strip()} if only else None

rows, failures, not_ready = [], [], []
for g in gates:
    gid = g.get("id", "?")
    if want and gid not in want:
        continue
    cmd = str(g.get("command", "")).strip()
    req = bool(g.get("required", True))
    if cmd in ("TBD", ""):
        rows.append((gid, "-", "NOT_READY", "0.0", "-"))
        not_ready.append(gid)
        if strict and req:
            failures.append(f"{gid}: 门禁命令仍是 TBD")
        continue
    t0 = time.time()
    log = os.path.join(logdir, f"{gid}.log")
    with open(log, "w", encoding="utf-8") as f:
        p = subprocess.run(cmd, shell=True, stdout=f, stderr=subprocess.STDOUT, text=True)
    dt = time.time() - t0
    status = "PASS" if p.returncode == 0 else "FAIL"
    rows.append((gid, cmd, status, f"{dt:.1f}", log))
    if p.returncode != 0 and req:
        failures.append(f"{gid}: exit={p.returncode}（日志 {log}）")

w = [max(len(str(r[i])) for r in rows) for i in range(5)] if rows else [4]*5
def line(vals): return " | ".join(str(v).ljust(w[i]) for i, v in enumerate(vals))
print(line(("门禁", "命令", "结果", "秒", "日志")))
print("-+-".join("-"*x for x in w))
for r in rows:
    print(line(r))

print()
if not_ready:
    print(f"未就绪（TBD，{'strict 下算失败' if strict else '仅告警'}）: {', '.join(not_ready)}")
passed = sum(1 for r in rows if r[2] == "PASS")
print(f"通过 {passed}/{len(rows)}，失败 {len(failures)}")

# 供看板读取的机器可读摘要
summary = {
    "generatedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "passed": passed,
    "total": len(rows),
    "failed": len(failures),
    "gates": [
        {"id": r[0], "command": r[1], "status": r[2],
         "seconds": float(r[3]) if r[3] not in ("-", "") else 0.0, "log": r[4]}
        for r in rows
    ],
}
for f in failures:
    print("FAIL  " + f)
with open(os.path.join(logdir, "summary.json"), "w", encoding="utf-8") as f:
    import json
    json.dump(summary, f, ensure_ascii=False, indent=2)

sys.exit(1 if failures else 0)
PY