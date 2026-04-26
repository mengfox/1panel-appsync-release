#!/usr/bin/env bash
set -euo pipefail

APP_NAME="1panel-appsync"

# 发布仓库
GITHUB_REPO="${GITHUB_REPO:-mengfox/1panel-appsync-release}"
CNB_REPO="${CNB_REPO:-https://cnb.cool/mengfox/1panel-appsync-release}"

# 安装路径
BIN_DIR="${BIN_DIR:-/usr/local/bin}"
BIN_PATH="${BIN_DIR}/${APP_NAME}"
CONFIG_DIR="${CONFIG_DIR:-/etc/${APP_NAME}}"
DATA_DIR="${DATA_DIR:-/var/lib/${APP_NAME}}"
LOG_DIR="${LOG_DIR:-/var/log/${APP_NAME}}"
SERVICE_FILE="/etc/systemd/system/${APP_NAME}.service"

# 临时目录与版本
TMP_DIR="${TMP_DIR:-/tmp/${APP_NAME}-install}"
CHANNEL="${CHANNEL:-latest}"

# 节点选择：
# REGION_MODE=auto   自动测速选择 GitHub/CNB
# REGION_MODE=cn     强制优先 CNB
# REGION_MODE=global 强制优先 GitHub
REGION_MODE="${REGION_MODE:-auto}"

# 兼容旧变量
FORCE_CN="${FORCE_CN:-false}"
FORCE_GLOBAL="${FORCE_GLOBAL:-false}"

# 指定版本时，CNB Raw 只能代表 main 最新文件，默认不作为指定版本兜底，避免装错版本。
# 如确实需要允许 CNB Raw 兜底，可设置：ALLOW_CNB_RAW_FALLBACK_FOR_VERSION=true
ALLOW_CNB_RAW_FALLBACK_FOR_VERSION="${ALLOW_CNB_RAW_FALLBACK_FOR_VERSION:-false}"

# 探测参数
PROBE_CONNECT_TIMEOUT="${PROBE_CONNECT_TIMEOUT:-5}"
PROBE_MAX_TIME="${PROBE_MAX_TIME:-10}"

# 手动指定下载地址，优先级最高
DOWNLOAD_URL="${DOWNLOAD_URL:-}"

log() {
  # 注意：日志必须输出到 stderr。
  # download_binary 会通过命令替换返回二进制路径，如果日志输出到 stdout，会污染返回值。
  echo "[$(date '+%F %T')] $*" >&2
}

warn() {
  echo "警告：$*" >&2
}

die() {
  echo "错误：$*" >&2
  exit 1
}

need_root() {
  if [ "$(id -u)" -ne 0 ]; then
    die "请使用 root 或 sudo 执行"
  fi
}

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

usage() {
  cat <<EOF
1Panel AppSync 安装 / 更新脚本

用法：
  bash install-update.sh
  bash install-update.sh install
  bash install-update.sh update
  bash install-update.sh uninstall
  bash install-update.sh status

常用环境变量：
  REGION_MODE=auto              自动判断国内/海外节点，默认
  REGION_MODE=cn                强制优先 CNB
  REGION_MODE=global            强制优先 GitHub
  FORCE_CN=true                 兼容旧参数，等价 REGION_MODE=cn
  FORCE_GLOBAL=true             等价 REGION_MODE=global
  CHANNEL=latest                安装最新版
  CHANNEL=v0.4.3                安装指定版本
  DOWNLOAD_URL=https://...      手动指定二进制下载地址

示例：
  curl -fsSL https://raw.githubusercontent.com/mengfox/1panel-appsync-release/main/install-update.sh | sudo bash

  curl -fsSL https://cnb.cool/mengfox/1panel-appsync-release/-/git/raw/main/install-update.sh | sudo bash

  curl -fsSL https://raw.githubusercontent.com/mengfox/1panel-appsync-release/main/install-update.sh | sudo env REGION_MODE=cn bash

  curl -fsSL https://raw.githubusercontent.com/mengfox/1panel-appsync-release/main/install-update.sh | sudo env CHANNEL=v0.4.3 bash
EOF
}

detect_pm() {
  for pm in apt-get dnf yum apk zypper pacman; do
    if has_cmd "$pm"; then
      echo "$pm"
      return 0
    fi
  done
  return 1
}

install_packages() {
  local packages=("$@")
  local pm
  pm="$(detect_pm || true)"

  if [ -z "$pm" ]; then
    warn "未识别包管理器，请手动安装：${packages[*]}"
    return 0
  fi

  case "$pm" in
    apt-get)
      apt-get update
      apt-get install -y "${packages[@]}"
      ;;
    dnf)
      dnf install -y "${packages[@]}"
      ;;
    yum)
      yum install -y "${packages[@]}"
      ;;
    apk)
      apk add --no-cache "${packages[@]}"
      ;;
    zypper)
      zypper --non-interactive install "${packages[@]}"
      ;;
    pacman)
      pacman -Sy --noconfirm "${packages[@]}"
      ;;
  esac
}

ensure_dependencies() {
  local missing=()

  has_cmd curl || has_cmd wget || missing+=("curl")
  has_cmd git || missing+=("git")
  has_cmd tar || missing+=("tar")

  if ! has_cmd update-ca-certificates && ! has_cmd trust; then
    missing+=("ca-certificates")
  fi

  if [ "${#missing[@]}" -gt 0 ]; then
    log "自动安装缺少依赖：${missing[*]}"
    install_packages "${missing[@]}"
  fi
}

detect_platform() {
  local os arch

  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  arch="$(uname -m)"

  case "$os" in
    linux) os="linux" ;;
    *) die "暂只支持 Linux，当前系统：$os" ;;
  esac

  case "$arch" in
    x86_64|amd64) arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
    *) die "暂不支持架构：$arch" ;;
  esac

  echo "${os}-${arch}"
}

download_file() {
  local url="$1"
  local output="$2"

  if has_cmd curl; then
    curl -fL --connect-timeout 15 --retry 3 --retry-delay 2 -o "$output" "$url"
  elif has_cmd wget; then
    wget --timeout=20 --tries=3 -O "$output" "$url"
  else
    die "缺少 curl 或 wget"
  fi
}

probe_url() {
  local url="$1"
  local cost=""

  if ! has_cmd curl; then
    return 1
  fi

  cost="$(
    curl -fsIL \
      --connect-timeout "$PROBE_CONNECT_TIMEOUT" \
      --max-time "$PROBE_MAX_TIME" \
      -o /dev/null \
      -w "%{time_total}" \
      "$url" 2>/dev/null || true
  )"

  if [ -n "$cost" ]; then
    echo "$cost"
    return 0
  fi

  cost="$(
    curl -fsL \
      -r 0-0 \
      --connect-timeout "$PROBE_CONNECT_TIMEOUT" \
      --max-time "$PROBE_MAX_TIME" \
      -o /dev/null \
      -w "%{time_total}" \
      "$url" 2>/dev/null || true
  )"

  if [ -n "$cost" ]; then
    echo "$cost"
    return 0
  fi

  return 1
}

float_less_than() {
  awk "BEGIN { exit !($1 < $2) }"
}

normalize_region_mode() {
  if [ "$FORCE_CN" = "true" ]; then
    echo "cn"
    return 0
  fi

  if [ "$FORCE_GLOBAL" = "true" ]; then
    echo "global"
    return 0
  fi

  case "$REGION_MODE" in
    auto|cn|global)
      echo "$REGION_MODE"
      ;;
    *)
      warn "REGION_MODE=$REGION_MODE 不支持，自动切换为 auto"
      echo "auto"
      ;;
  esac
}

build_candidate_urls() {
  local asset="$1"
  local mode="$2"

  local github_url=""
  local cnb_url=""

  if [ "$CHANNEL" = "latest" ]; then
    github_url="https://github.com/${GITHUB_REPO}/releases/latest/download/${asset}"
    cnb_url="${CNB_REPO}/-/git/raw/main/dist/${asset}"
  else
    github_url="https://github.com/${GITHUB_REPO}/releases/download/${CHANNEL}/${asset}"
    cnb_url="${CNB_REPO}/-/git/raw/main/dist/${asset}"

    # 指定版本时优先保证版本准确。CNB Raw 不是版本化地址，默认只返回 GitHub Release URL。
    if [ "$ALLOW_CNB_RAW_FALLBACK_FOR_VERSION" != "true" ]; then
      printf "%s\n" "$github_url"
      return 0
    fi
  fi

  case "$mode" in
    cn)
      printf "%s\n%s\n" "$cnb_url" "$github_url"
      ;;
    global)
      printf "%s\n%s\n" "$github_url" "$cnb_url"
      ;;
    auto)
      local github_cost=""
      local cnb_cost=""

      log "正在自动判断下载节点..."
      github_cost="$(probe_url "$github_url" || true)"
      cnb_cost="$(probe_url "$cnb_url" || true)"

      if [ -n "$github_cost" ]; then
        log "GitHub 可用，耗时：${github_cost}s"
      else
        log "GitHub 探测失败"
      fi

      if [ -n "$cnb_cost" ]; then
        log "CNB 可用，耗时：${cnb_cost}s"
      else
        log "CNB 探测失败"
      fi

      if [ -n "$github_cost" ] && [ -n "$cnb_cost" ]; then
        if float_less_than "$cnb_cost" "$github_cost"; then
          log "自动选择：CNB"
          printf "%s\n%s\n" "$cnb_url" "$github_url"
        else
          log "自动选择：GitHub"
          printf "%s\n%s\n" "$github_url" "$cnb_url"
        fi
      elif [ -n "$cnb_cost" ]; then
        log "自动选择：CNB"
        printf "%s\n%s\n" "$cnb_url" "$github_url"
      elif [ -n "$github_cost" ]; then
        log "自动选择：GitHub"
        printf "%s\n%s\n" "$github_url" "$cnb_url"
      else
        warn "GitHub 和 CNB 探测均失败，按默认顺序尝试：GitHub -> CNB"
        printf "%s\n%s\n" "$github_url" "$cnb_url"
      fi
      ;;
  esac
}

download_binary() {
  local platform asset out mode urls url

  platform="$(detect_platform)"
  asset="${APP_NAME}-${platform}"
  out="${TMP_DIR}/${APP_NAME}"

  rm -rf "$TMP_DIR"
  mkdir -p "$TMP_DIR"

  if [ -n "$DOWNLOAD_URL" ]; then
    urls="$DOWNLOAD_URL"
    log "使用手动指定下载地址：$DOWNLOAD_URL"
  else
    mode="$(normalize_region_mode)"
    log "下载节点模式：$mode"
    urls="$(build_candidate_urls "$asset" "$mode")"
  fi

  while IFS= read -r url; do
    [ -n "$url" ] || continue

    log "尝试下载：$url"

    if download_file "$url" "$out"; then
      chmod +x "$out"

      if "$out" version >/dev/null 2>&1; then
        log "下载成功：$url"
        # 只有这里输出到 stdout，供 new_bin="$(download_binary)" 接收。
        echo "$out"
        return 0
      fi

      warn "下载文件不是有效二进制，跳过：$url"
    else
      warn "下载失败，尝试下一个源：$url"
    fi
  done <<EOF
$urls
EOF

  die "下载失败。可设置 REGION_MODE=cn/global 或 DOWNLOAD_URL 手动指定二进制地址。"
}

write_systemd_service() {
  if ! has_cmd systemctl; then
    log "未检测到 systemd，跳过 service 写入"
    return 0
  fi

  mkdir -p "$CONFIG_DIR"

  if [ ! -f "$CONFIG_DIR/env" ]; then
    cat > "$CONFIG_DIR/env" <<'EOF'
# 传给 daemon 的额外参数，默认留空即可。
# 示例：
# APPSYNC_DAEMON_ARGS="--local-dir /data/1panel/resource/apps/local"

APPSYNC_DAEMON_ARGS=""
EOF
  fi

  cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=1Panel AppSync Daemon
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=-${CONFIG_DIR}/env
ExecStart=/bin/sh -c '${BIN_PATH} daemon \${APPSYNC_DAEMON_ARGS:-}'
Restart=always
RestartSec=10
User=root
Group=root
Nice=10
IOSchedulingClass=best-effort

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
}

install_or_update() {
  need_root
  ensure_dependencies

  mkdir -p "$BIN_DIR" "$CONFIG_DIR" "$DATA_DIR/repos" "$DATA_DIR/backups" "$DATA_DIR/cache" "$LOG_DIR"

  local new_bin old_version new_version backup_bin
  new_bin="$(download_binary)"

  old_version=""
  if [ -x "$BIN_PATH" ]; then
    old_version="$("$BIN_PATH" version 2>/dev/null || true)"
    backup_bin="${BIN_PATH}.bak.$(date +%Y%m%d%H%M%S)"
    log "备份旧版本：$backup_bin"
    cp "$BIN_PATH" "$backup_bin"
  fi

  install -m 0755 "$new_bin" "$BIN_PATH"
  new_version="$("$BIN_PATH" version 2>/dev/null || true)"

  log "安装完成"
  [ -n "$old_version" ] && log "旧版本：$old_version"
  log "新版本：$new_version"

  write_systemd_service

  "$BIN_PATH" deps --install || true
  "$BIN_PATH" detect || true

  if has_cmd systemctl; then
    systemctl enable "$APP_NAME.service" >/dev/null 2>&1 || true
    systemctl restart "$APP_NAME.service" || true
  fi

  log "完成"
}

uninstall() {
  need_root

  if has_cmd systemctl; then
    systemctl disable --now "$APP_NAME.service" 2>/dev/null || true
    rm -f "$SERVICE_FILE"
    systemctl daemon-reload
  fi

  rm -f "$BIN_PATH"
  log "已卸载程序和 systemd service，配置与数据默认保留。"
}

status() {
  if [ -x "$BIN_PATH" ]; then
    "$BIN_PATH" version || true
  else
    echo "${APP_NAME} 未安装"
  fi

  if has_cmd systemctl; then
    systemctl status "$APP_NAME.service" --no-pager || true
  fi
}

case "${1:-install}" in
  install|update)
    install_or_update
    ;;
  uninstall)
    uninstall
    ;;
  status)
    status
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    die "未知命令：$1"
    ;;
esac
