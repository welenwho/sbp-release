#!/usr/bin/env bash
# Public download entry point. The verified release owns all installation logic.
set -Eeuo pipefail

sbp_bootstrap_error() { printf '\n[SBP] %s\n' "$*" >&2; return 1; }
sbp_bootstrap_version() { [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; }
sbp_bootstrap_fetch() {
  curl --fail --location --show-error --silent --proto '=https' --proto-redir '=https' \
    --connect-timeout 15 --max-time 300 --retry 2 --max-filesize 134217728 "$1" -o "$2"
}
sbp_bootstrap_hash() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  else openssl dgst -sha256 "$1" | awk '{print $NF}'; fi
}
sbp_bootstrap_verify() {
  local archive=$1 manifest=$2 expected filename extra actual
  [[ $(wc -l <"$manifest" | tr -d ' ') == 1 ]] || return 1
  read -r expected filename extra <"$manifest" || return 1
  [[ ${#expected} == 64 && "$expected" != *[!a-fA-F0-9]* && -z "$extra" ]] || return 1
  [[ "$filename" == "${archive##*/}" ]] || return 1
  actual=$(sbp_bootstrap_hash "$archive") || return 1
  [[ "$actual" == "$(printf '%s' "$expected" | tr 'A-F' 'a-f')" ]]
}
sbp_bootstrap_free_kb() { df -Pk "$1" | awk 'END {print $4}'; }
sbp_bootstrap_terminal() {
  [[ -t 0 ]] && return 0
  [[ -r /dev/tty ]] || { sbp_bootstrap_error '请在交互终端执行一键安装命令。'; return 1; }
  exec </dev/tty
}
sbp_bootstrap_archive_safe() {
  local archive=$1 root=$2 listing=$3 path segment entries=0
  local -a segments=()
  unzip -Z1 "$archive" >"$listing" || return 1
  while IFS= read -r path; do
    [[ "$path" == "$root/"* && "$path" != *'\'* && "$path" != *$'\r'* ]] || return 1
    IFS=/ read -r -a segments <<<"$path"
    for segment in "${segments[@]}"; do
      [[ -n "$segment" && "$segment" != . && "$segment" != .. ]] || return 1
    done
    entries=$((entries + 1))
    ((entries <= 10000)) || return 1
  done <"$listing"
  ((entries > 0)) || return 1
  # Info-ZIP's long listing starts Unix symlinks with l. Do not extract them.
  unzip -Z -l "$archive" >"$listing.details" || return 1
  ! awk '$1 ~ /^l/ {found=1} END {exit !found}' "$listing.details"
}
sbp_bootstrap_dependencies() {
  local answer
  if command -v unzip >/dev/null 2>&1 && { command -v sha256sum >/dev/null 2>&1 || command -v openssl >/dev/null 2>&1; }; then return 0; fi
  printf '[SBP] 需要安装 unzip、CA 证书和 SHA-256 校验工具。\n'
  read -r -p '安装这些依赖？[Y/n]: ' answer || return 1
  case "$answer" in ''|y|Y) ;; *) return 1 ;; esac
  local -a privilege=(env)
  if ((EUID != 0)); then command -v sudo >/dev/null || return 1; privilege=(sudo); fi
  if command -v apt-get >/dev/null; then
    "${privilege[@]}" apt-get update || return 1
    "${privilege[@]}" apt-get install -y unzip ca-certificates openssl
  elif command -v dnf >/dev/null; then "${privilege[@]}" dnf install -y unzip ca-certificates openssl
  elif command -v yum >/dev/null; then "${privilege[@]}" yum install -y unzip ca-certificates openssl
  elif command -v apk >/dev/null; then "${privilege[@]}" apk add unzip ca-certificates openssl
  else sbp_bootstrap_error '无法自动安装依赖，请先安装 unzip 和 openssl。'; fi
}
sbp_bootstrap_main() (
  umask 077
  local repo=welenwho/sbp-release work= base=/var/tmp version choice archive free required unpacked qnap=false
  local node_mode=false node_token= entry=install.sh
  if [[ ${1:-} == --node ]]; then
    [[ $# -ge 3 && $2 == --release-version ]] || { sbp_bootstrap_error '节点引导缺少固定版本。'; exit 1; }
    version=$3; shift 3
    sbp_bootstrap_version "$version" || { sbp_bootstrap_error '节点安装版本无效。'; exit 1; }
    IFS= read -r -n 513 node_token || [[ -n "$node_token" ]] || exit 1
    [[ ${#node_token} -ge 16 && ${#node_token} -le 512 && "$node_token" =~ ^[A-Za-z0-9._~-]+$ ]] || { sbp_bootstrap_error '一次性加入码无效。'; exit 1; }
    node_mode=true
    entry=install-node.sh
    [[ ! -e /etc/sbp/deployment-mode && ! -e /etc/sbp/native.env ]] || { sbp_bootstrap_error '目标机已有 SBP，请使用面板接管或节点管理，不能重复加入。'; exit 1; }
  fi
  [[ $(uname -s) == Linux ]] || { sbp_bootstrap_error '安装器仅支持 Linux。'; exit 1; }
  case "$(uname -m)" in x86_64|amd64|aarch64|arm64) ;; *) sbp_bootstrap_error '目前只提供 amd64 和 arm64 安装包。'; exit 1 ;; esac
  command -v curl >/dev/null || { sbp_bootstrap_error '请先安装 curl。'; exit 1; }
  sbp_bootstrap_terminal || exit 1
  [[ ! -f /etc/config/qpkg.conf ]] || qnap=true
  if $node_mode && $qnap; then sbp_bootstrap_error '此引导用于标准 Linux Docker 节点，不能覆盖 QNAP Container Station。'; exit 1; fi
  if ! $node_mode; then
  printf '\nSBP 安装 / 升级\n1) 最新稳定版（默认）\n2) 指定稳定版本\n0) 退出\n'
  read -r -p '请选择 [1]: ' choice || exit 1
  case "${choice:-1}" in
    1) version= ;;
    2) read -r -p '版本号，例如 1.5.17: ' version || exit 1
       version=${version#v}; sbp_bootstrap_version "$version" || { sbp_bootstrap_error '版本号格式错误。'; exit 1; } ;;
    0) exit 0 ;;
    *) sbp_bootstrap_error '无效选项。'; exit 1 ;;
  esac
  fi
  # Never unpack into a small RAM-backed /tmp, notably QTS's 64 MB tmpfs.
  while true; do
    if [[ -d "$base" && -w "$base" ]]; then
      free=$(sbp_bootstrap_free_kb "$base")
      if [[ "$free" =~ ^[0-9]+$ ]] && ((free >= 262144)) && ! $qnap; then break; fi
    fi
    read -r -p '请输入至少有 256 MiB 可用空间的工作目录（QNAP 请选择 /share 下数据卷）: ' base || exit 1
    [[ "$base" == /* && -d "$base" && -w "$base" ]] || continue
    if $qnap && [[ "$base" != /share/* ]]; then continue; fi
    free=$(sbp_bootstrap_free_kb "$base")
    if [[ "$free" =~ ^[0-9]+$ ]] && ((free >= 262144)); then break; fi
  done
  work=$(mktemp -d "$base/sbp-download.XXXXXX") || exit 1
  trap '[[ -z "$work" ]] || rm -rf -- "$work"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  sbp_bootstrap_dependencies || exit 1
  if [[ -z "$version" ]]; then
    sbp_bootstrap_fetch "https://github.com/$repo/releases/latest/download/version.txt" "$work/version.txt" || exit 1
    version=$(tr -d '\r\n' <"$work/version.txt")
    sbp_bootstrap_version "$version" || { sbp_bootstrap_error '发布版本信息无效。'; exit 1; }
  fi
  archive="sbp-$version.zip"
  printf '\n[SBP] 下载稳定版 %s\n' "$version"
  sbp_bootstrap_fetch "https://github.com/$repo/releases/download/v$version/$archive.sha256" "$work/$archive.sha256" || exit 1
  sbp_bootstrap_fetch "https://github.com/$repo/releases/download/v$version/$archive" "$work/$archive" || exit 1
  sbp_bootstrap_verify "$work/$archive" "$work/$archive.sha256" || { sbp_bootstrap_error 'SHA-256 校验失败，未执行安装。'; exit 1; }
  sbp_bootstrap_archive_safe "$work/$archive" "sbp-$version" "$work/entries" || { sbp_bootstrap_error '安装包路径或类型无效。'; exit 1; }
  unpacked=$(LC_ALL=C unzip -l "$work/$archive" | awk 'END {print $1}')
  [[ "$unpacked" =~ ^[0-9]+$ ]] && ((unpacked <= 536870912)) || { sbp_bootstrap_error '安装包展开尺寸异常。'; exit 1; }
  free=$(sbp_bootstrap_free_kb "$work")
  required=$((unpacked / 1024 * 2 + 65536))
  [[ "$free" =~ ^[0-9]+$ ]] && ((free >= required)) || { sbp_bootstrap_error '解压空间不足，未执行安装。'; exit 1; }
  unzip -q "$work/$archive" -d "$work" || exit 1
  [[ -f "$work/sbp-$version/install.sh" && $(tr -d '\r\n' <"$work/sbp-$version/VERSION") == "$version" ]] || exit 1
  if $node_mode; then
    [[ -f "$work/sbp-$version/$entry" ]] || { sbp_bootstrap_error '安装包不包含节点安装器。'; exit 1; }
    printf '%s' "$node_token" >"$work/enrollment.token"
    chmod 0600 "$work/enrollment.token"
    unset node_token
    set -- "$@" --token-file "$work/enrollment.token" --yes
    printf '\n[SBP] 正在安装受管节点，完成后自动注册到中心。\n'
  fi
  if $qnap; then
    printf '\n[SBP] QNAP 安装包已校验并保留在 %s\n请使用包内 qnap-runtime-compose.yaml；本入口不会使用通用安装器覆盖 Container Station。\n' "$work/sbp-$version"
    work=
    exit 0
  fi
  # The child owns upgrade locks, credentials, core preservation and rollback.
  # Keep the parent alive so EXIT cleanup does not discard the package early.
  if ((EUID == 0)); then bash "$work/sbp-$version/$entry" "$@"
  else
    command -v sudo >/dev/null || { sbp_bootstrap_error '需要 root 或 sudo 权限。'; exit 1; }
    sudo bash "$work/sbp-$version/$entry" "$@"
  fi
)

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then sbp_bootstrap_main "$@"; fi
