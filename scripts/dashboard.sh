#!/usr/bin/env bash
# 启动本项目看板。默认前台常驻（Ctrl+C 结束）；--detach 后台常驻并立即返回 URL。
#
#   dashboard.sh [项目目录] [--port N] [--detach] [--stop] [--list] [--open-all]
#                [--no-open]
#
# 二进制查找顺序：$MAF_DASHBOARD → PATH 里的 maf-dashboard → ~/.local/bin/maf-dashboard

set -u
DIR="."
ARGS=""
OPEN="--open"

while [ $# -gt 0 ]; do
  case "$1" in
    --port|--bind|--stale)
      ARGS="$ARGS $1 ${2:-}"; shift 2 ;;
    --detach|--stop|--list|--open-all)
      ARGS="$ARGS $1"; shift ;;
    --open)
      OPEN="--open"; shift ;;
    --no-open)
      OPEN=""; shift ;;
    -h|--help)
      sed -n '2,8p' "$0"; exit 0 ;;
    *)
      DIR="$1"; shift ;;
  esac
done

[ -d "$DIR" ] || { printf '错误: 目录不存在 %s\n' "$DIR" >&2; exit 2; }

case " $ARGS " in
  *" --stop "*|*" --list "*|*" --open-all "*) OPEN="" ;;
esac

BIN="${MAF_DASHBOARD:-}"
if [ -z "$BIN" ]; then
  if command -v maf-dashboard >/dev/null 2>&1; then
    BIN="maf-dashboard"
  elif [ -x "$HOME/.local/bin/maf-dashboard" ]; then
    BIN="$HOME/.local/bin/maf-dashboard"
  fi
fi

if [ -z "$BIN" ]; then
  cat >&2 <<'EOF'
找不到 maf-dashboard。三种装法，任选其一：

  1. 本地构建（推荐，需 Go 1.23+）
     cd <仓库>/server && go build -o ~/.local/bin/maf-dashboard ./cmd/maf-dashboard

  2. 用安装脚本构建
     ./install.sh --with-dashboard

  3. 用 Release 资产（私有仓库需要登录或 token）
     gh release download v1.2.1 -R Stainless5792/multi-agent-framework-skill -p 'maf-dashboard_darwin_*'

装好后重跑本脚本。没有二进制时仍可用 scripts/status.sh 的轻量视图。
EOF
  exit 1
fi

# shellcheck disable=SC2086
exec "$BIN" --dir "$DIR" $ARGS $OPEN