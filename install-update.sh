#!/usr/bin/env bash
set -euo pipefail

APP_NAME="1panel-appsync"
GITHUB_REPO="${GITHUB_REPO:-mengfox/1panel-appsync-release}"
CNB_REPO="${CNB_REPO:-https://cnb.cool/mengfox/1panel-appsync-release}"

BIN_DIR="${BIN_DIR:-/usr/local/bin}"
BIN_PATH="${BIN_DIR}/${APP_NAME}"
CONFIG_DIR="${CONFIG_DIR:-/etc/${APP_NAME}}"
DATA_DIR="${DATA_DIR:-/var/lib/${APP_NAME}}"
LOG_DIR="${LOG_DIR:-/var/log/${APP_NAME}}"
SERVICE_FILE="/etc/systemd/system/${APP_NAME}.service"

TMP_DIR="${TMP_DIR:-/tmp/${APP_NAME}-install}"
CHANNEL="${CHANNEL:-latest}"
FORCE_CN="${FORCE_CN:-false}"

log() {
  echo "[$(date '+%F %T')] $*"
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

环境变量：
  GITHUB_REPO=mengfox/1panel-appsync-release
  CNB_REPO=https://cnb.cool/mengfox/1panel-appsync-release
  FORCE_CN=true
  DOWNLOAD_URL=https://example.com/1panel-appsync-linux-amd64
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
    log "未识别包管理器，请手动安装：${packages[*]}"
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

download_binary() {
  local platform asset out urls url

  platform="$(detect_platform)"
  asset="${APP_NAME}-${platform}"
  out="${TMP_DIR}/${APP_NAME}"

  rm -rf "$TMP_DIR"
  mkdir -p "$TMP_DIR"

  if [ -n "${DOWNLOAD_URL:-}" ]; then
    urls=("$DOWNLOAD_URL")
  elif [ "$FORCE_CN" = "true" ]; then
    urls=(
      "${CNB_REPO}/-/releases/latest/download/${asset}"
      "${CNB_REPO}/-/raw/main/dist/${asset}"
      "https://github.com/${GITHUB_REPO}/releases/latest/download/${asset}"
    )
  else
    urls=(
      "https://github.com/${GITHUB_REPO}/releases/latest/download/${asset}"
      "${CNB_REPO}/-/releases/latest/download/${asset}"
      "${CNB_REPO}/-/raw/main/dist/${asset}"
    )
  fi

  for url in "${urls[@]}"; do
    log "尝试下载：$url"
    if download_file "$url" "$out"; then
      chmod +x "$out"
      if "$out" version >/dev/null 2>&1; then
        log "下载成功：$url"
        echo "$out"
        return 0
      fi
      log "下载文件不是有效二进制，跳过"
    fi
  done

  die "下载失败。可通过 DOWNLOAD_URL 指定二进制地址。"
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
