#!/usr/bin/env bash
# install-mac.sh — temp-electron 一键安装脚本
#
# 用法：
#   curl -fsSL "$RAW/install-mac.sh" | bash
#   INSTALL_BASE_URL=https://your-cdn bash <(curl -fsSL ...)        # 自定义下载源
#   INSTALL_VERSION=v1.0.33 bash <(curl -fsSL ...)                  # 锁版本
#   INSTALL_DIR="$HOME/Applications" bash <(curl -fsSL ...)          # 用户目录安装
#   HTTPS_PROXY=http://proxy:8080 bash <(curl -fsSL ...)            # 走代理
#
# 默认下载源：xrainoxu/zhaoyi-electron-release（public 分发仓库）

set -Eeuo pipefail

# ---------- 可调参数（环境变量覆盖） ----------
APP_NAME="${APP_NAME:-temp-electron}"
RELEASE_REPO="${RELEASE_REPO:-xrainoxu/zhaoyi-electron-release}"
RELEASE_BRANCH="${RELEASE_BRANCH:-main}"
ASSET_PREFIX="${ASSET_PREFIX:-${APP_NAME}-darwin}"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"
PINNED_VERSION="${INSTALL_VERSION:-}"
LOG_DIR="${HOME}/Library/Logs/${APP_NAME}"
LOG_FILE="${LOG_DIR}/install.log"
TMP_DIR=""
: "${TMPDIR:=/tmp}"

# ---------- 颜色（仅交互终端） ----------
if [[ -t 1 ]]; then
  C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YLW=$'\033[33m'; C_OFF=$'\033[0m'
else
  C_RED=""; C_GRN=""; C_YLW=""; C_OFF=""
fi

mkdir -p "$LOG_DIR" 2>/dev/null || true
log_line() { printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$1" >> "$LOG_FILE" 2>/dev/null || true; }
cleanup()  { [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]] && rm -rf "$TMP_DIR"; }
trap cleanup EXIT

fail() { printf '\n%s安装中止：%s%s\n' "$C_RED" "$1" "$C_OFF" >&2; log_line "FAIL: $1"; exit 1; }
info() { printf '\n%s%s%s\n' "$C_GRN" "$1" "$C_OFF";         log_line "INFO: $1"; }
warn() { printf '\n%s%s%s\n' "$C_YLW" "$1" "$C_OFF";         log_line "WARN: $1"; }

# ---------- 1. 系统与命令依赖 ----------
[[ "$(uname -s)" == "Darwin" ]] || fail "此安装脚本仅支持 macOS。"

case "$(uname -m)" in
  arm64)  ARCH="arm64" ;;
  x86_64) ARCH="x64"   ;;
  *)      fail "不支持的 Mac 架构：$(uname -m)" ;;
esac

for c in curl unzip xattr open pgrep ditto; do
  command -v "$c" >/dev/null 2>&1 || fail "系统缺少命令：${c}。请联系管理员。"
done

# ---------- 2. 代理透传 ----------
# 用 CURL_PROXY_OPT 字符串（单 token），传 "" 表示无代理；
# 避免数组在 set -u 下空展开触发"unbound variable"。
CURL_PROXY_OPT=""
if [[ -n "${HTTPS_PROXY:-${https_proxy:-}}" ]]; then
  CURL_PROXY_OPT="--proxy ${HTTPS_PROXY:-${https_proxy:-}}"
  info "检测到代理：${HTTPS_PROXY:-${https_proxy:-}}"
fi

# ---------- 3. 解析版本与下载链接 ----------
TMP_DIR="$(mktemp -d -t ${APP_NAME}-install)"

version="$PINNED_VERSION"
sha256=""

if [[ -z "$version" ]]; then
  # 通道 1：raw.githubusercontent.com 上的 latest.json（由 publish.sh 推到 main 分支）
  if curl -fL $CURL_PROXY_OPT --connect-timeout 10 --max-time 30 \
       "https://raw.githubusercontent.com/${RELEASE_REPO}/${RELEASE_BRANCH}/latest.json" \
       -o "$TMP_DIR/latest.json" 2>/dev/null; then
    version="$(grep -oE '"version"[[:space:]]*:[[:space:]]*"v?[0-9]+\.[0-9]+\.[0-9]+"' \
              "$TMP_DIR/latest.json" | head -n1 | sed -E 's/.*"(v?[0-9.]+)".*/\1/')"
    sha256="$(grep -oE "\"${ARCH}\"[[:space:]]*:[[:space:]]*\"[a-f0-9]{64}\"" \
              "$TMP_DIR/latest.json" | head -n1 | sed -E 's/.*"([a-f0-9]{64})".*/\1/')"
    log_line "channel=latest.json, version=$version, sha256=${sha256:0:8}..."
  fi

  # 通道 2：兜底 GitHub Release API
  if [[ -z "$version" ]]; then
    warn "静态清单不可达，回退到 GitHub Release API。"
    curl -fL $CURL_PROXY_OPT --retry 3 --connect-timeout 10 --max-time 60 \
      -H 'Accept: application/vnd.github+json' \
      "https://api.github.com/repos/${RELEASE_REPO}/releases/latest" \
      -o "$TMP_DIR/release.json" || fail "无法访问 GitHub Release。请检查网络或联系管理员。"
    version="$(grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"v[0-9]+\.[0-9]+\.[0-9]+"' \
              "$TMP_DIR/release.json" | head -n1 | sed -E 's/.*"(v[0-9.]+)".*/\1/')"
  fi
fi

[[ -n "$version" ]] || fail "无法解析最新版本号。"
version="${version#v}"
asset="${ASSET_PREFIX}-${ARCH}-${version}.zip"
info "目标版本：v${version}（架构 ${ARCH}）"

dl_url="https://github.com/${RELEASE_REPO}/releases/download/v${version}/${asset}"
zip_path="$TMP_DIR/$asset"
info "正在下载：$dl_url"
# --max-time 3600 (1h)：在弱网下 200MB zip 可能需要较长时间；
# --speed-time 30 --speed-limit 1024：连续 30s 速度低于 1KB/s 视为失败重试。
curl -fL $CURL_PROXY_OPT --retry 3 --connect-timeout 30 --max-time 3600 \
  --speed-time 30 --speed-limit 1024 \
  "$dl_url" -o "$zip_path" || fail "应用下载失败。"

# ---------- 4. SHA256 校验（可选） ----------
if [[ -n "$sha256" ]]; then
  actual="$(shasum -a 256 "$zip_path" | awk '{print $1}')"
  if [[ "$actual" != "$sha256" ]]; then
    fail "SHA256 校验失败：期望 $sha256，实际 $actual"
  fi
  info "SHA256 校验通过。"
fi

# ---------- 5. 解压与解签名 ----------
info "正在解压……"
unzip -q "$zip_path" -d "$TMP_DIR/app" || fail "压缩包解压失败。"
app_source="$TMP_DIR/app/${APP_NAME}.app"
[[ -d "$app_source" ]] || fail "压缩包中没有找到 ${APP_NAME}.app。"
xattr -cr "$app_source" 2>/dev/null || true

# ---------- 6. 关闭旧版本 ----------
if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
  warn "检测到旧版本正在运行，尝试优雅退出……"
  osascript -e "tell application \"$APP_NAME\" to quit" 2>/dev/null || true
  for _ in 1 2 3 4 5; do
    pgrep -x "$APP_NAME" >/dev/null 2>&1 || break
    sleep 1
  done
  pgrep -x "$APP_NAME" >/dev/null 2>&1 && fail "${APP_NAME} 仍在运行，请手动退出后重试。"
fi

# ---------- 7. 安装 ----------
APP_PATH="${INSTALL_DIR}/${APP_NAME}.app"
[[ -d "$INSTALL_DIR" && -w "$INSTALL_DIR" ]] || fail "${INSTALL_DIR} 目录不可写，请设置 INSTALL_DIR 或联系管理员。"
[[ -e "$APP_PATH" ]] && rm -rf "$APP_PATH"
ditto "$app_source" "$APP_PATH" || fail "无法将应用安装到 ${INSTALL_DIR}。"
[[ -x "$APP_PATH/Contents/MacOS/$APP_NAME" ]] || fail "安装后的应用文件不完整。"

# ---------- 8. 启动 ----------
info "安装完成，正在启动 ${APP_NAME} v${version}……"
open "$APP_PATH" || fail "应用已安装，但启动失败。"

printf '\n%s安装成功：%s%s\n' "$C_GRN" "$APP_PATH" "$C_OFF"
printf 'Node.js 运行环境将在应用首次启动时自动准备（约 30 秒）。\n'
printf '安装日志：%s\n' "$LOG_FILE"
log_line "install-mac.sh success, version=v${version}, path=${APP_PATH}"