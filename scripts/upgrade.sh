#!/usr/bin/env bash
# 升级已有的脚手架项目到当前 skill 版本。
#
#   upgrade.sh              # 只出计划（dry-run）
#   upgrade.sh --apply      # 真写
#   upgrade.sh --check      # 落后则 exit 1
#   upgrade.sh --apply --force --allow-dirty --strict
#
# 只处理 assets/managed.map 里的文件与 AGENTS.md 的 maf 段；
# 项目自己的 .agent/*.yaml、contracts/**、docs/architecture/**、worker-*.md 永不触碰。

set -u
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$SELF_DIR/../assets/managed.map" ] && [ -f "$SELF_DIR/../VERSION" ]; then
  SKILL_DIR="$(cd "$SELF_DIR/.." && pwd)"
elif [ -n "${MAF_SKILL_DIR:-}" ] && [ -f "$MAF_SKILL_DIR/assets/managed.map" ]; then
  SKILL_DIR="$MAF_SKILL_DIR"
else
  SKILL_DIR="$HOME/.config/opencode/skills/multi-agent-framework"
fi
MAP="$SKILL_DIR/assets/managed.map"
VER_FILE="$SKILL_DIR/VERSION"
PROJECT="$PWD"
APPLY=0
FORCE=0
STRICT=0
ALLOW_DIRTY=0
CHECK=0

while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1; shift ;;
    --check) CHECK=1; shift ;;
    --force) FORCE=1; shift ;;
    --strict) STRICT=1; shift ;;
    --allow-dirty) ALLOW_DIRTY=1; shift ;;
    --project) PROJECT="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) printf '未知参数: %s\n' "$1" >&2; exit 2 ;;
  esac
done

[ -f "$MAP" ] || { printf '错误: 找不到 %s\n（先 install.sh 安装 skill，或设 MAF_SKILL_DIR）\n' "$MAP" >&2; exit 2; }
[ -f "$VER_FILE" ] || { printf '错误: 找不到 %s\n' "$VER_FILE" >&2; exit 2; }
[ -d "$PROJECT/.agent" ] || { printf '错误: %s 不是脚手架项目（缺少 .agent/）\n' "$PROJECT" >&2; exit 2; }
cd "$PROJECT" || exit 2

python3 - "$SKILL_DIR" "$MAP" "$VER_FILE" "$APPLY" "$FORCE" "$STRICT" "$CHECK" "$ALLOW_DIRTY" <<'PY'
import hashlib, json, os, shutil, subprocess, sys, time

skill, map_file, ver_file, apply_s, force_s, strict_s, check_s, dirty_ok_s = sys.argv[1:9]
apply, force, strict, check = apply_s == "1", force_s == "1", strict_s == "1", check_s == "1"
allow_dirty = dirty_ok_s == "1"
new_ver = open(ver_file, encoding="utf-8").read().strip()

def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(65536), b""):
            h.update(b)
    return h.hexdigest()

def read(p):
    with open(p, encoding="utf-8") as f:
        return f.read()

map_path = os.path.join(skill, map_file)
pairs = []
for line in open(map_path, encoding="utf-8"):
    line = line.strip()
    if not line or line.startswith("#"):
        continue
    src, dst = line.split("\t")
    pairs.append((src, dst))

# 脏工作区：只拦受管文件之外的改动（受管文件的改动会走 conflict，不会丢）
managed_dests = {dst for _, dst in pairs} | {"AGENTS.md", ".gitignore"}
dirty_files = []
if apply and not allow_dirty:
    try:
        out = subprocess.run(["git", "status", "--porcelain"], capture_output=True, text=True).stdout
        for line in out.splitlines():
            pth = line[3:].strip()
            if " -> " in pth:
                pth = pth.split(" -> ")[-1]
            dirty_files.append(pth)
    except Exception:
        pass
    unexpected = [d for d in dirty_files
                  if d not in managed_dests and not d.startswith(".agent/logs/")]
    if unexpected:
        print("工作区有与本次升级无关的未提交改动，已停止（升级会与别人正在写的改动混在一起）：\n")
        for d in unexpected[:15]:
            print("  " + d)
        print("\n确认要继续，加 --allow-dirty。")
        sys.exit(4)
    if dirty_files:
        print("注意: 有 %d 个受管文件被改动，将按 conflict 处理（原文件保留）\n" % len(dirty_files))

manifest_path = ".agent/framework.json"
old = {}
old_agents = ""
old_ver = ""
if os.path.exists(manifest_path):
    try:
        m = json.load(open(manifest_path, encoding="utf-8"))
        old = m.get("files") or {}
        old_agents = m.get("agents_block") or ""
        old_ver = m.get("version") or ""
    except Exception:
        pass

actions = []  # (status, dest, note)
to_write = []
new_hashes = {}

for src, dst in pairs:
    sp = os.path.join(skill, src)
    if not os.path.exists(sp):
        actions.append(("missing-src", dst, src))
        continue
    new_hash = sha(sp)
    new_hashes[dst] = new_hash
    if not os.path.exists(dst):
        actions.append(("create", dst, ""))
        to_write.append((dst, sp))
        continue
    cur = sha(dst)
    if cur == new_hash:
        actions.append(("same", dst, ""))
        continue
    old_hash = old.get(dst)
    if old_hash and cur == old_hash:
        actions.append(("update", dst, ""))
        to_write.append((dst, sp))
    elif not old_hash and not strict:
        actions.append(("legacy-update", dst, "无历史记录，覆盖并备份"))
        to_write.append((dst, sp))
    elif force:
        actions.append(("forced", dst, "本地有改动，强制覆盖"))
        to_write.append((dst, sp))
    else:
        actions.append(("conflict", dst, "本地有改动，保留原文件并写 .framework-new"))
        to_write.append((dst + ".framework-new", sp))

# AGENTS.md 的 maf 段
block_src = os.path.join(skill, "assets/AGENTS.section.md")
block_new = read(block_src).rstrip()
block_new_hash = hashlib.sha256(block_new.encode()).hexdigest()
agents_mode = "same"   # same | update | conflict
if os.path.exists("AGENTS.md"):
    txt = read("AGENTS.md")
    start, end = txt.find("<!-- maf:begin"), txt.find("<!-- maf:end -->")
    if start >= 0 and end > start:
        block_cur = txt[start:end + len("<!-- maf:end -->")].rstrip()
        cur_hash = hashlib.sha256(block_cur.encode()).hexdigest()
        if cur_hash == block_new_hash:
            agents_mode = "same"
        elif old_agents and old_agents == cur_hash:
            agents_mode = "update"
        elif force:
            agents_mode = "update"
        else:
            # 段内有本地改动：不覆盖，另存一份新版供人工合并
            agents_mode = "conflict"
    else:
        agents_mode = "update"
agents_changed = agents_mode in ("update",)

# .gitignore 受管条目
want_ignores = [".agent/logs/", ".agent/workers/", ".agent/inbox/done/",
                ".agent/dashboard.json", ".agent/dashboard.log"]
ignore_missing = []
if os.path.exists(".gitignore"):
    cur_ig = read(".gitignore")
    ignore_missing = [x for x in want_ignores if x not in cur_ig.splitlines()]
else:
    ignore_missing = want_ignores

changes = [a for a in actions if a[0] in ("create", "update", "legacy-update", "forced", "conflict")]
behind = bool(changes) or agents_changed or bool(ignore_missing) or agents_mode == "conflict"

print("项目版本: %s → 目标版本: %s" % (old_ver or "(无记录)", new_ver))
print()
for st, dst, note in actions:
    mark = {"same": "ok      ", "create": "create  ", "update": "update  ",
            "legacy-update": "update* ", "forced": "forced  ", "conflict": "CONFLICT",
            "missing-src": "WARN    "}[st]
    extra = ("  " + note) if note else ""
    print("%s %s%s" % (mark, dst, extra))
if agents_mode == "update":
    print("update   AGENTS.md（maf 段）")
elif agents_mode == "conflict":
    print("CONFLICT AGENTS.md（maf 段有本地改动，新版另存为 .agent/AGENTS.section.new.md）")
if ignore_missing:
    print("append   .gitignore: " + ", ".join(ignore_missing))

print()
agents_note = ""
if agents_mode == "update":
    agents_note = "，AGENTS 段将更新"
elif agents_mode == "conflict":
    agents_note = "，AGENTS 段冲突（不覆盖）"
print("需要变更: %d 个文件%s%s" % (
    len(changes), agents_note,
    "，gitignore 补 %d 条" % len(ignore_missing) if ignore_missing else ""))

if check:
    sys.exit(1 if behind else 0)
if not apply:
    print("\n（dry-run：未写入；加 --apply 执行）")
    sys.exit(0)

if not behind:
    print("\n已是最新，无需写入。")
    # 仍刷新版本号
    write_manifest = True
else:
    write_manifest = True

# 备份
os.makedirs(".agent/logs", exist_ok=True)
ts = time.strftime("%Y%m%d-%H%M%S")
backup = ".agent/logs/upgrade-%s.tar.gz" % ts
paths = [dst for _, dst, _ in actions if dst and os.path.exists(dst)]
if agents_changed and os.path.exists("AGENTS.md"):
    paths.append("AGENTS.md")
if paths:
    try:
        subprocess.run(["tar", "czf", backup] + paths, check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        print("备份: %s" % backup)
    except Exception as e:
        print("WARN: 备份失败（%s），继续但请自行留底" % e)

for dst, sp in to_write:
    os.makedirs(os.path.dirname(dst) or ".", exist_ok=True)
    shutil.copy2(sp, dst)
    mode = os.stat(sp).st_mode
    os.chmod(dst, mode)

if agents_changed:
    txt = read("AGENTS.md") if os.path.exists("AGENTS.md") else "# 项目指令\n\n"
    start, end = txt.find("<!-- maf:begin"), txt.find("<!-- maf:end -->")
    if start >= 0 and end > start:
        txt = txt[:start] + block_new + txt[end + len("<!-- maf:end -->"):]
    else:
        txt = txt.rstrip() + "\n\n" + block_new + "\n"
    with open("AGENTS.md", "w", encoding="utf-8") as f:
        f.write(txt)
elif agents_mode == "conflict":
    os.makedirs(".agent", exist_ok=True)
    with open(".agent/AGENTS.section.new.md", "w", encoding="utf-8") as f:
        f.write(block_new + "\n")

if ignore_missing:
    with open(".gitignore", "a", encoding="utf-8") as f:
        if not (os.path.exists(".gitignore") and read(".gitignore").endswith("\n")):
            f.write("\n")
        for x in ignore_missing:
            f.write(x + "\n")

# 重算受管文件哈希（含冲突时保留原文件的情况）
final = {}
for src, dst in pairs:
    if os.path.exists(dst):
        final[dst] = sha(dst)
manifest = {
    "framework": "multi-agent-framework",
    "version": new_ver,
    "agents_block": block_new_hash if agents_mode != "conflict" else old.get("_agents_block", ""),
    "upgraded_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "files": final,
}
json.dump(manifest, open(manifest_path, "w", encoding="utf-8"), ensure_ascii=False, indent=2)

conflicts = [d for s, d, _ in actions if s == "conflict"]
print("\n完成。版本: %s" % new_ver)
if conflicts:
    print("有 %d 个冲突，已写 .framework-new：%s" % (len(conflicts), ", ".join(conflicts)))
    print("逐个 diff 后决定保留哪份，然后删掉 .framework-new。")
PY