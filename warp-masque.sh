#!/usr/bin/env bash
# Cloudflare official Linux client exposed as a MASQUE local SOCKS5 proxy.
# Author: 0157Martin
# SPDX-License-Identifier: GPL-3.0-or-later
set -Eeuo pipefail

readonly APP_NAME=warp-masque-manager
readonly APP_VERSION=1.1.0
readonly CONFIG_DIR=/etc/warp-masque-manager
readonly STATE_FILE="$CONFIG_DIR/state.env"
readonly DEFAULT_PORT=40000
readonly CONNECT_TIMEOUT=18

red() { printf '\033[31m%s\033[0m\n' "$*" >&2; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
die() { red "错误：$*"; exit 1; }
require_root() { [[ ${EUID:-$(id -u)} -eq 0 ]] || die '请使用 root 运行。'; }
warp_cli() { warp-cli --accept-tos "$@"; }

proxy_ready() {
  local port=${1:-$DEFAULT_PORT}
  systemctl is-active --quiet warp-svc && ss -H -lnt "sport = :$port" 2>/dev/null | grep -q .
}

wait_for_proxy() {
  local port=$1 timeout=${2:-$CONNECT_TIMEOUT} attempt
  for ((attempt=0; attempt<timeout; attempt++)); do
    proxy_ready "$port" && return 0
    sleep 1
  done
  return 1
}

proxy_trace_ok() {
  local port=$1 trace
  proxy_ready "$port" || return 1
  trace=$(curl --fail --silent --show-error --max-time 8 \
    --proxy "socks5h://127.0.0.1:$port" https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null) || return 1
  grep -q '^warp=on$' <<<"$trace"
}

try_tunnel() {
  local protocol=$1 endpoint=$2 port=$3
  warp_cli disconnect >/dev/null 2>&1 || true
  warp_cli tunnel protocol set "$protocol" >/dev/null 2>&1 || return 1
  if [[ $endpoint == default ]]; then
    warp_cli tunnel endpoint reset >/dev/null 2>&1 || true
  else
    warp_cli tunnel endpoint set "$endpoint" >/dev/null 2>&1 || return 1
  fi
  warp_cli connect >/dev/null 2>&1 || return 1
  wait_for_proxy "$port" && proxy_trace_ok "$port"
}

select_working_tunnel() {
  local port=$1 protocol endpoint
  local -a masque_endpoints=(
    default
    162.159.198.2:443 162.159.198.2:4443 162.159.198.2:8095
    162.159.197.1:443 162.159.197.1:4443 162.159.197.1:8443 162.159.197.1:8095
  )
  local -a wireguard_endpoints=(
    188.114.98.1:2408 162.159.193.1:2408
    162.159.193.1:4500 162.159.193.1:500 162.159.193.1:1701
  )
  for endpoint in "${masque_endpoints[@]}"; do
    yellow "测试官方客户端 MASQUE 入口：$endpoint" >&2
    if try_tunnel MASQUE "$endpoint" "$port"; then
      printf 'masque\t%s\n' "$endpoint"
      return 0
    fi
  done
  for endpoint in "${wireguard_endpoints[@]}"; do
    yellow "测试官方客户端 WireGuard 入口：$endpoint" >&2
    if try_tunnel WireGuard "$endpoint" "$port"; then
      printf 'wireguard\t%s\n' "$endpoint"
      return 0
    fi
  done
  warp_cli disconnect >/dev/null 2>&1 || true
  warp_cli tunnel endpoint reset >/dev/null 2>&1 || true
  return 1
}

test_proxy() {
  local port=${1:-$DEFAULT_PORT} trace
  proxy_ready "$port" || die "127.0.0.1:$port 未监听。"
  trace=$(curl --fail --silent --show-error --max-time 20 --proxy "socks5h://127.0.0.1:$port" https://www.cloudflare.com/cdn-cgi/trace) || die '无法通过 MASQUE WARP 代理联网。'
  grep -q '^warp=on$' <<<"$trace" || die 'Cloudflare 未确认 WARP 已连接。'
  awk -F= '/^(ip|loc|warp)=/{printf "%s: %s\n", $1, $2}' <<<"$trace"
}

install_client() {
  local codename key_file
  [[ -r /etc/os-release ]] || die '仅支持 Debian/Ubuntu。'
  # shellcheck disable=SC1091
  source /etc/os-release
  [[ ${ID:-} == debian || ${ID:-} == ubuntu ]] || die '仅支持 Debian/Ubuntu。'
  codename=${VERSION_CODENAME:-}
  [[ -n $codename ]] || die '无法识别发行版代号。'
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl gnupg iproute2
  key_file=$(mktemp)
  trap 'rm -f -- "$key_file"' RETURN
  curl --fail --show-error --location --retry 3 https://pkg.cloudflareclient.com/pubkey.gpg -o "$key_file"
  gpg --batch --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg "$key_file"
  printf 'deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ %s main\n' "$codename" > /etc/apt/sources.list.d/cloudflare-client.list
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y cloudflare-warp
  rm -f -- "$key_file"
  trap - RETURN
}

configure_proxy() {
  local port=$1 selected protocol endpoint
  if [[ ! $port =~ ^[0-9]+$ ]] || (( port < 1024 || port > 65535 )); then
    die 'SOCKS5 端口必须在 1024-65535。'
  fi
  systemctl enable --now warp-svc
  warp_cli registration show >/dev/null 2>&1 || timeout 45 warp-cli --accept-tos registration new
  warp_cli mode proxy
  warp_cli proxy port "$port"
  if ! selected=$(select_working_tunnel "$port"); then
    warp_cli status >&2 || true
    die '官方客户端的 MASQUE/WireGuard 候选入口均未通过真实流量验证。注册已保留。'
  fi
  IFS=$'\t' read -r protocol endpoint <<<"$(tail -n 1 <<<"$selected")"
  install -d -m 700 "$CONFIG_DIR"
  printf 'BACKEND=masque\nPORT=%q\nPROTOCOL=%q\nENDPOINT=%q\n' "$port" "$protocol" "$endpoint" >"$STATE_FILE"
  chmod 600 "$STATE_FILE"
  test_proxy "$port"
  green "官方客户端已选择：$protocol / $endpoint"
}

install_backend() {
  local port=${1:-$DEFAULT_PORT}
  install_client
  configure_proxy "$port"
  green "Cloudflare 官方 Local Proxy 后端已就绪：127.0.0.1:$port"
}

status_backend() {
  local port=$DEFAULT_PORT
  # The state file is created by this script with mode 0600.
  # shellcheck disable=SC1090
  [[ -r $STATE_FILE ]] && { source "$STATE_FILE"; port=${PORT:-$DEFAULT_PORT}; }
  warp_cli status || true
  printf '后端：Cloudflare 官方 Local Proxy\n服务：%s\n监听：127.0.0.1:%s\n' "$(systemctl is-active warp-svc 2>/dev/null || true)" "$port"
  proxy_ready "$port" && test_proxy "$port" || return 1
}

redact_log() {
  sed -E \
    -e 's/([Ll]icense|[Tt]oken|[Ss]ecret|[Pp]rivate[_ -]?[Kk]ey|[Aa]ccount|[Dd]evice)[=: ][^ ,;}]+/\1=[REDACTED]/g' \
    -e 's/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/[REDACTED-UUID]/g'
}

diagnose_backend() {
  printf '%s\n' 'IPv4 默认路由：'; ip -4 route show default || true
  printf '%s\n' 'IPv6 默认路由：'; ip -6 route show default || true
  printf '%s\n' 'WARP 状态：'; warp_cli status 2>&1 || true
  printf '%s\n' '最近连接日志：'
  journalctl -u warp-svc -n 200 --no-pager 2>&1 | grep -Ei 'Connecting|HappyEyeballs|ERROR|WARN|failed|timeout|unreachable' | tail -n 30 | redact_log || true
  yellow '安装器会优先使用 MASQUE，并在失败时测试官方客户端支持的 WireGuard 入口。'
}

repair_backend() {
  command -v warp-cli >/dev/null 2>&1 || { install_backend "${1:-$DEFAULT_PORT}"; return; }
  configure_proxy "${1:-$DEFAULT_PORT}"
  green 'MASQUE WARP 后端已修复。'
}

start_backend() {
  systemctl enable --now warp-svc
  warp_cli connect
}

stop_backend() {
  warp_cli disconnect >/dev/null 2>&1 || true
}

uninstall_backend() {
  if command -v warp-cli >/dev/null 2>&1; then
    warp_cli disconnect >/dev/null 2>&1 || true
    warp_cli registration delete >/dev/null 2>&1 || true
  fi
  apt-get remove -y cloudflare-warp || true
  rm -f -- /etc/apt/sources.list.d/cloudflare-client.list /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
  rm -rf -- "$CONFIG_DIR"
  green 'MASQUE WARP 后端已卸载。'
}

main() {
  require_root
  case ${1:-status} in
    install) install_backend "${2:-$DEFAULT_PORT}" ;;
    status) status_backend ;;
    test) test_proxy "${2:-$DEFAULT_PORT}" ;;
    start) start_backend ;;
    stop) stop_backend ;;
    diagnose) diagnose_backend ;;
    repair) repair_backend "${2:-$DEFAULT_PORT}" ;;
    uninstall) uninstall_backend ;;
    version) printf '%s %s\n' "$APP_NAME" "$APP_VERSION" ;;
    *) die '用法：warp-masque [install|status|test|start|stop|diagnose|repair|uninstall|version] [端口]' ;;
  esac
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
