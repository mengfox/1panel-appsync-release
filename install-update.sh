#!/usr/bin/env bash
set -euo pipefail

APP_NAME="1panel-appsync"
APP_TITLE="1Panel AppSync"

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
TMP_DIR="${TMP_DIR:-/var/tmp/${APP_NAME}-install}"
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

# 安装后的运行方式：默认写入 systemd，并启用内置定时任务 daemon。
# INSTALL_SERVICE=false      仅安装二进制，不写 systemd
# ENABLE_SERVICE=false       写入 systemd 但不开机自启动
# START_SERVICE=false        写入 systemd 但不立即启动
# INSTALL_DEPS=false         不自动安装依赖
# RUN_DETECT=false           安装后不自动检测 1Panel 本地应用目录
# SYNC_AFTER_INSTALL=false   安装完成后不执行首次同步，只启动 daemon 等下一轮
# SYNC_TIMEOUT=600           首次同步最大等待秒数；0 表示不限制
# APPSYNC_DAEMON_ARGS=""     daemon/sync 额外参数，例如 --local-dir
INSTALL_SERVICE="${INSTALL_SERVICE:-true}"
ENABLE_SERVICE="${ENABLE_SERVICE:-true}"
START_SERVICE="${START_SERVICE:-true}"
INSTALL_DEPS="${INSTALL_DEPS:-true}"
RUN_DETECT="${RUN_DETECT:-true}"
SYNC_AFTER_INSTALL="${SYNC_AFTER_INSTALL:-true}"
SYNC_TIMEOUT="${SYNC_TIMEOUT:-600}"
APPSYNC_DAEMON_ARGS="${APPSYNC_DAEMON_ARGS:-}"

# 日志显示
QUIET="${QUIET:-false}"
NO_COLOR="${NO_COLOR:-false}"
STEP_NO=0

setup_colors() {
  if [ "$NO_COLOR" = "true" ] || [ ! -t 2 ]; then
    C_RESET=""; C_BOLD=""; C_DIM=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_CYAN=""
    return 0
  fi

  C_RESET="\033[0m"
  C_BOLD="\033[1m"
  C_DIM="\033[2m"
  C_RED="\033[31m"
  C_GREEN="\033[32m"
  C_YELLOW="\033[33m"
  C_BLUE="\033[34m"
  C_CYAN="\033[36m"
}

say() {
  [ "$QUIET" = "true" ] && return 0
  printf "%b\n" "$*" >&2
}

hr() {
  say "${C_DIM}────────────────────────────────────────────────────────────${C_RESET}"
}

banner() {
  say ""
  say "${C_BOLD}${C_CYAN}1Panel AppSync 自动同步工具${C_RESET}"
  say "${C_DIM}默认安装为 systemd daemon，使用内置定时任务自动同步，开机自启动。${C_RESET}"
  hr
}

step() {
  STEP_NO=$((STEP_NO + 1))
  say ""
  say "${C_BOLD}${C_BLUE}[$STEP_NO] $*${C_RESET}"
}

info() {
  say "  ${C_CYAN}›${C_RESET} $*"
}

ok() {
  say "  ${C_GREEN}✓${C_RESET} $*"
}

warn() {
  say "  ${C_YELLOW}!${C_RESET} $*"
}

fail() {
  say "  ${C_RED}✗${C_RESET} $*"
}

kv() {
  local key="$1"
  local value="$2"
  printf "  %-16s %b\n" "${key}:" "$value" >&2
}

die() {
  fail "$*"
  say ""
  say "排查建议："
  say "  1. 查看帮助：bash install-update.sh --help"
  say "  2. 强制国内源：REGION_MODE=cn bash install-update.sh"
  say "  3. 手动指定地址：DOWNLOAD_URL=https://... bash install-update.sh"
  exit 1
}

need_root() {
  if [ "$(id -u)" -ne 0 ]; then
    die "请使用 root 或 sudo 执行。示例：curl -fsSL <install-url> | sudo bash"
  fi
}

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

has_systemd() {
  has_cmd systemctl && [ -d /run/systemd/system ]
}

usage() {
  setup_colors
  cat <<EOF_USAGE
${APP_TITLE} 安装 / 更新脚本

用法：
  bash install-update.sh                 安装或更新，默认启动 daemon
  bash install-update.sh install          安装或更新
  bash install-update.sh update           安装或更新
  bash install-update.sh uninstall        卸载程序与 systemd 服务，保留数据
  bash install-update.sh status           查看程序与服务状态

默认行为：
  - 安装二进制到：${BIN_PATH}
  - 写入环境文件：${CONFIG_DIR}/env
  - 写入 systemd：${SERVICE_FILE}
  - 安装后先执行一次：${APP_NAME} sync
  - 然后执行：systemctl enable && systemctl restart ${APP_NAME}.service
  - 运行模式：${APP_NAME} daemon
  - 定时策略：daemon 启动后立即检查，之后按程序内置 scheduler 周期同步

常用环境变量：
  REGION_MODE=auto              自动判断下载节点，默认
  REGION_MODE=cn                强制优先 CNB
  REGION_MODE=global            强制优先 GitHub
  CHANNEL=latest                安装最新版
  CHANNEL=v0.5.0                安装指定版本
  DOWNLOAD_URL=https://...      手动指定二进制下载地址
  INSTALL_SERVICE=true          是否写入 systemd 服务
  ENABLE_SERVICE=true           是否设置开机自启动
  START_SERVICE=true            是否安装后立即启动
  INSTALL_DEPS=true             是否自动补齐 curl/git/ca-certificates
  RUN_DETECT=true               是否安装后自动检测 1Panel 本地应用目录
  SYNC_AFTER_INSTALL=true       是否安装后立即执行一次同步
  SYNC_TIMEOUT=600              首次同步最大等待秒数，0 表示不限制
  APPSYNC_DAEMON_ARGS=""        daemon/sync 额外参数，例如 --local-dir
  NO_COLOR=true                 关闭彩色输出
  QUIET=true                    减少安装提示

示例：
  curl -fsSL https://raw.githubusercontent.com/${GITHUB_REPO}/main/install-update.sh | sudo bash
  curl -fsSL ${CNB_REPO}/-/git/raw/main/install-update.sh | sudo bash
  curl -fsSL https://raw.githubusercontent.com/${GITHUB_REPO}/main/install-update.sh | sudo env REGION_MODE=cn bash
  curl -fsSL https://raw.githubusercontent.com/${GITHUB_REPO}/main/install-update.sh | sudo env CHANNEL=v0.5.0 bash
  curl -fsSL https://raw.githubusercontent.com/${GITHUB_REPO}/main/install-update.sh | sudo env START_SERVICE=false bash
EOF_USAGE
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

  info "使用包管理器：$pm"

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

  if ! has_cmd curl && ! has_cmd wget; then
    missing+=("curl")
  fi

  # INSTALL_DEPS=false 时，只保证安装脚本自身能下载安装包，不再自动安装 git 等运行依赖。
  if [ "$INSTALL_DEPS" = "true" ]; then
    has_cmd git || missing+=("git")

    if ! has_cmd update-ca-certificates && ! has_cmd trust; then
      missing+=("ca-certificates")
    fi
  fi

  if [ "${#missing[@]}" -eq 0 ]; then
    ok "依赖检查通过"
    return 0
  fi

  if [ "$INSTALL_DEPS" != "true" ]; then
    die "缺少下载安装工具：${missing[*]}。请手动安装，或使用 INSTALL_DEPS=true。"
  fi

  info "准备自动安装依赖：${missing[*]}"
  install_packages "${missing[@]}"
  ok "依赖处理完成"
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
    curl -fL --connect-timeout 15 --retry 3 --retry-delay 2 --progress-bar -o "$output" "$url"
  elif has_cmd wget; then
    wget --timeout=20 --tries=3 --show-progress -O "$output" "$url"
  else
    die "缺少 curl 或 wget"
  fi
}

binary_version() {
  local bin="$1"
  "$bin" version 2>/dev/null | awk '{print $2}' || true
}

verify_downloaded_binary() {
  local bin="$1"
  local got expected

  if ! "$bin" version >/dev/null 2>&1; then
    return 1
  fi

  if [ "$CHANNEL" != "latest" ]; then
    expected="${CHANNEL#v}"
    got="$(binary_version "$bin")"
    if [ "$got" != "$expected" ]; then
      warn "二进制版本不匹配：期望 ${expected}，实际 ${got:-unknown}"
      return 1
    fi
  fi

  return 0
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
  awk -v a="$1" -v b="$2" 'BEGIN { exit !(a < b) }'
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

      info "正在测速选择下载节点"
      github_cost="$(probe_url "$github_url" || true)"
      cnb_cost="$(probe_url "$cnb_url" || true)"

      if [ -n "$github_cost" ]; then
        ok "GitHub 可用，耗时 ${github_cost}s"
      else
        warn "GitHub 探测失败"
      fi

      if [ -n "$cnb_cost" ]; then
        ok "CNB 可用，耗时 ${cnb_cost}s"
      else
        warn "CNB 探测失败"
      fi

      if [ -n "$github_cost" ] && [ -n "$cnb_cost" ]; then
        if float_less_than "$cnb_cost" "$github_cost"; then
          ok "自动选择 CNB"
          printf "%s\n%s\n" "$cnb_url" "$github_url"
        else
          ok "自动选择 GitHub"
          printf "%s\n%s\n" "$github_url" "$cnb_url"
        fi
      elif [ -n "$cnb_cost" ]; then
        ok "自动选择 CNB"
        printf "%s\n%s\n" "$cnb_url" "$github_url"
      elif [ -n "$github_cost" ]; then
        ok "自动选择 GitHub"
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

  kv "系统平台" "$platform"
  kv "安装通道" "$CHANNEL"
  kv "临时目录" "$TMP_DIR"

  if [ -n "$DOWNLOAD_URL" ]; then
    urls="$DOWNLOAD_URL"
    info "使用手动指定下载地址"
  else
    mode="$(normalize_region_mode)"
    kv "节点模式" "$mode"
    urls="$(build_candidate_urls "$asset" "$mode")"
  fi

  while IFS= read -r url; do
    [ -n "$url" ] || continue

    info "下载：$url"

    if download_file "$url" "$out"; then
      chmod +x "$out"

      if verify_downloaded_binary "$out"; then
        ok "下载完成，版本：$($out version 2>/dev/null | awk '{print $2}')"
        # 只有这里输出到 stdout，供 new_bin="$(download_binary)" 接收。
        echo "$out"
        return 0
      fi

      warn "下载文件不是有效二进制，或版本与 CHANNEL 不一致，跳过"
    else
      warn "下载失败，尝试下一个源"
    fi
  done <<EOF_URLS
$urls
EOF_URLS

  die "下载失败。可设置 REGION_MODE=cn/global 或 DOWNLOAD_URL 手动指定二进制地址。"
}

write_systemd_service() {
  if ! has_systemd; then
    warn "未检测到 systemd，跳过 service 写入"
    return 0
  fi

  mkdir -p "$CONFIG_DIR"

  if [ ! -f "$CONFIG_DIR/env" ]; then
    cat > "$CONFIG_DIR/env" <<'EOF_ENV'
# 传给 daemon 的额外参数，默认留空即可。
# 示例：自定义 1Panel 本地应用路径
# APPSYNC_DAEMON_ARGS="--local-dir /data/1panel/resource/apps/local"

EOF_ENV
    printf 'APPSYNC_DAEMON_ARGS="%s"\n' "$APPSYNC_DAEMON_ARGS" >> "$CONFIG_DIR/env"
    ok "已创建环境文件：$CONFIG_DIR/env"
  else
    ok "环境文件已存在：$CONFIG_DIR/env"
    if [ -n "$APPSYNC_DAEMON_ARGS" ]; then
      if grep -q '^APPSYNC_DAEMON_ARGS=' "$CONFIG_DIR/env"; then
        sed -i "s|^APPSYNC_DAEMON_ARGS=.*|APPSYNC_DAEMON_ARGS=\"${APPSYNC_DAEMON_ARGS}\"|" "$CONFIG_DIR/env"
      else
        printf '\nAPPSYNC_DAEMON_ARGS="%s"\n' "$APPSYNC_DAEMON_ARGS" >> "$CONFIG_DIR/env"
      fi
      ok "已更新环境参数：APPSYNC_DAEMON_ARGS=${APPSYNC_DAEMON_ARGS}"
    fi
  fi

  cat > "$SERVICE_FILE" <<EOF_SERVICE
[Unit]
Description=1Panel AppSync Daemon
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=-${CONFIG_DIR}/env
ExecStart=${BIN_PATH} daemon \$APPSYNC_DAEMON_ARGS
Restart=always
RestartSec=10
TimeoutStopSec=30
KillSignal=SIGTERM
User=root
Group=root
Nice=10
IOSchedulingClass=best-effort
WorkingDirectory=/

[Install]
WantedBy=multi-user.target
EOF_SERVICE

  systemctl daemon-reload
  ok "已写入 systemd 服务：$SERVICE_FILE"
}

service_value() {
  local action="$1"
  local out=""

  if ! has_systemd; then
    echo "未检测到 systemd"
    return 0
  fi

  case "$action" in
    active)
      if out="$(systemctl is-active "$APP_NAME.service" 2>/dev/null)"; then
        echo "$out"
      else
        echo "${out:-inactive}"
      fi
      ;;
    enabled)
      if out="$(systemctl is-enabled "$APP_NAME.service" 2>/dev/null)"; then
        echo "$out"
      else
        echo "${out:-disabled}"
      fi
      ;;
    *)
      echo "unknown"
      ;;
  esac
}

run_appsync_command() {
  local subcmd="$1"
  if [ -n "$APPSYNC_DAEMON_ARGS" ]; then
    # APPSYNC_DAEMON_ARGS 用于兼容 systemd 环境文件中的追加参数。
    # shellcheck disable=SC2086
    "$BIN_PATH" "$subcmd" $APPSYNC_DAEMON_ARGS
  else
    "$BIN_PATH" "$subcmd"
  fi
}

run_initial_sync() {
  if [ "$SYNC_AFTER_INSTALL" != "true" ]; then
    info "已按 SYNC_AFTER_INSTALL=false 跳过首次同步"
    return 0
  fi

  step "首次同步应用"
  info "安装完成后立即执行一次同步，避免只启动 daemon 但未马上写入应用"
  [ -n "$APPSYNC_DAEMON_ARGS" ] && kv "同步参数" "$APPSYNC_DAEMON_ARGS"

  local start_ts end_ts elapsed rc
  start_ts="$(date +%s)"

  set +e
  if has_cmd timeout && [ "${SYNC_TIMEOUT:-0}" != "0" ]; then
    timeout "${SYNC_TIMEOUT}s" bash -c 'BIN_PATH="$1"; APPSYNC_DAEMON_ARGS="$2"; if [ -n "$APPSYNC_DAEMON_ARGS" ]; then "$BIN_PATH" sync $APPSYNC_DAEMON_ARGS; else "$BIN_PATH" sync; fi' bash "$BIN_PATH" "$APPSYNC_DAEMON_ARGS"
    rc=$?
  else
    run_appsync_command sync
    rc=$?
  fi
  set -e

  end_ts="$(date +%s)"
  elapsed=$((end_ts - start_ts))

  if [ "$rc" -eq 0 ]; then
    ok "首次同步完成，耗时 ${elapsed}s"
    return 0
  fi

  if [ "$rc" -eq 124 ]; then
    warn "首次同步超时，已超过 ${SYNC_TIMEOUT}s；daemon 启动后会继续定时同步"
  else
    warn "首次同步未完成，退出码：$rc。daemon 启动后会继续重试"
  fi
  warn "可查看日志：journalctl -u ${APP_NAME}.service -f，或手动执行：${APP_NAME} sync"
  return 0
}

print_last_sync_status() {
  [ -x "$BIN_PATH" ] || return 0
  [ -d "$DATA_DIR" ] || return 0

  say ""
  say "最近同步状态："
  if "$BIN_PATH" status 2>/dev/null | sed 's/^/  /' >&2; then
    return 0
  fi
  say "  暂无状态记录，等待首次同步完成后生成。"
}
print_summary() {
  local old_version="$1"
  local new_version="$2"

  say ""
  hr
  say "${C_BOLD}${C_GREEN}安装完成${C_RESET}"
  kv "程序路径" "$BIN_PATH"
  kv "配置目录" "$CONFIG_DIR"
  kv "数据目录" "$DATA_DIR"
  kv "日志目录" "$LOG_DIR"
  [ -n "$old_version" ] && kv "旧版本" "$old_version"
  kv "当前版本" "${new_version:-unknown}"

  if [ "$INSTALL_SERVICE" = "true" ]; then
    kv "服务状态" "$(service_value active)"
    kv "开机自启" "$(service_value enabled)"
  else
    kv "服务状态" "未安装 systemd service"
  fi

  say ""
  say "常用命令："
  say "  systemctl status ${APP_NAME}.service --no-pager"
  say "  journalctl -u ${APP_NAME}.service -f"
  say "  ${APP_NAME} status"
  say "  ${APP_NAME} doctor"
  say "  ${APP_NAME} sync"
  say "  ${APP_NAME} sync --dry-run"
  print_last_sync_status
  say ""
  say "卸载命令："
  say "  bash install-update.sh uninstall"
  hr
}

install_or_update() {
  setup_colors
  banner

  step "检查运行环境"
  need_root
  ensure_dependencies
  kv "安装目录" "$BIN_DIR"
  kv "配置目录" "$CONFIG_DIR"

  step "准备目录"
  mkdir -p "$BIN_DIR" "$CONFIG_DIR" "$DATA_DIR/repos" "$DATA_DIR/backups" "$DATA_DIR/cache" "$LOG_DIR"
  ok "目录准备完成"

  step "下载并校验程序"
  local new_bin old_version new_version backup_bin
  new_bin="$(download_binary)"

  old_version=""
  if [ -x "$BIN_PATH" ]; then
    old_version="$($BIN_PATH version 2>/dev/null || true)"
    backup_bin="${BIN_PATH}.bak.$(date +%Y%m%d%H%M%S)"
    cp "$BIN_PATH" "$backup_bin"
    ok "已备份旧版本：$backup_bin"
  fi

  step "安装程序"
  install -m 0755 "$new_bin" "$BIN_PATH"
  new_version="$($BIN_PATH version 2>/dev/null || true)"
  ok "主程序已安装：$BIN_PATH"
  [ -n "$old_version" ] && kv "旧版本" "$old_version"
  kv "新版本" "$new_version"

  if [ "$INSTALL_DEPS" = "true" ]; then
    step "检查运行依赖"
    "$BIN_PATH" deps --install || warn "运行依赖检查未完全通过，可稍后执行：$APP_NAME deps --install"
  fi

  if [ "$RUN_DETECT" = "true" ]; then
    step "检测 1Panel 本地应用目录"
    run_appsync_command detect || warn "自动检测失败，可稍后执行：$APP_NAME detect 或手动配置 --local-dir"
  fi

  run_initial_sync

  step "配置自启动服务"
  if [ "$INSTALL_SERVICE" = "true" ]; then
    write_systemd_service

    if has_systemd; then
      if [ "$ENABLE_SERVICE" = "true" ]; then
        if systemctl enable "$APP_NAME.service" >/dev/null 2>&1; then
          ok "已设置开机自启动：$APP_NAME.service"
        else
          warn "设置开机自启动失败，可手动执行：systemctl enable $APP_NAME.service"
        fi
      else
        info "已按 ENABLE_SERVICE=false 跳过开机自启动"
      fi

      if [ "$START_SERVICE" = "true" ]; then
        if systemctl restart "$APP_NAME.service"; then
          ok "服务已启动：$APP_NAME.service"
        else
          warn "启动服务失败，可手动执行：systemctl restart $APP_NAME.service"
        fi
      else
        info "已按 START_SERVICE=false 跳过立即启动，可执行：systemctl start $APP_NAME.service"
      fi
    else
      warn "当前系统未检测到 systemd，无法自动开机自启动。可手动运行：$BIN_PATH daemon"
    fi
  else
    info "已按 INSTALL_SERVICE=false 跳过 systemd 服务写入"
  fi

  print_summary "$old_version" "$new_version"
}

uninstall() {
  setup_colors
  banner
  step "卸载程序与 systemd 服务"
  need_root

  if has_systemd; then
    systemctl disable --now "$APP_NAME.service" 2>/dev/null || true
    rm -f "$SERVICE_FILE"
    systemctl daemon-reload
    ok "已删除 systemd 服务"
  else
    warn "未检测到 systemd，跳过服务处理"
  fi

  rm -f "$BIN_PATH"
  ok "已删除主程序：$BIN_PATH"

  say ""
  say "默认保留以下目录，避免误删配置和同步数据："
  say "  $CONFIG_DIR"
  say "  $DATA_DIR"
  say "  $LOG_DIR"
  say ""
  say "如确认不再需要，可手动删除："
  say "  rm -rf $CONFIG_DIR $DATA_DIR $LOG_DIR"
}

status() {
  setup_colors
  banner

  step "程序状态"
  if [ -x "$BIN_PATH" ]; then
    kv "程序路径" "$BIN_PATH"
    kv "程序版本" "$($BIN_PATH version 2>/dev/null || echo unknown)"
  else
    warn "$APP_NAME 未安装"
  fi

  step "服务状态"
  if has_systemd; then
    kv "运行状态" "$(service_value active)"
    kv "开机自启" "$(service_value enabled)"
    say ""
    systemctl status "$APP_NAME.service" --no-pager || true
  else
    warn "未检测到 systemd"
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
    setup_colors
    die "未知命令：$1"
    ;;
esac
