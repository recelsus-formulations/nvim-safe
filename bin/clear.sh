#!/usr/bin/env bash
# Neovim の実行で生成されたデータ・状態・キャッシュを削除する。
# 設定ディレクトリ (~/.config/nvim) は削除しない。
#
# 対象 (Neovim の stdpath と同じ規則で決定し、XDG_* と NVIM_APPNAME に従う):
#   data  : ${XDG_DATA_HOME:-~/.local/share}/<appname>  mason.nvim、LSP サーバーなど
#   state : ${XDG_STATE_HOME:-~/.local/state}/<appname> shada、ログ、lsp.log など
#   cache : ${XDG_CACHE_HOME:-~/.cache}/<appname>       undo 履歴、jdtls の作業データなど
set -euo pipefail

usage() {
    cat <<EOF
Usage: $(basename "$0") [-n] [-y] [-h]

  -n, --dry-run  削除対象を表示するだけで削除しない
  -y, --yes      確認せずに削除する
  -h, --help     このヘルプを表示する
EOF
}

dry_run=false
assume_yes=false
for argument in "$@"; do
    case "$argument" in
        -n | --dry-run) dry_run=true ;;
        -y | --yes) assume_yes=true ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $argument" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [[ -z "${HOME:-}" ]]; then
    echo "HOME is not set" >&2
    exit 1
fi

appname="${NVIM_APPNAME:-nvim}"
if [[ -z "$appname" || "$appname" == *..* || "$appname" == /* ]]; then
    echo "Invalid NVIM_APPNAME: $appname" >&2
    exit 1
fi

candidates=(
    "${XDG_DATA_HOME:-$HOME/.local/share}/$appname"
    "${XDG_STATE_HOME:-$HOME/.local/state}/$appname"
    "${XDG_CACHE_HOME:-$HOME/.cache}/$appname"
)
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/$appname"

targets=()
for path in "${candidates[@]}"; do
    # 誤設定で HOME や / を消さないよう、appname で終わる絶対パス以外は拒否する
    if [[ "$path" != /* || "$(basename "$path")" != "$appname" || "$path" == "$config_dir" ]]; then
        echo "Refusing unsafe path: $path" >&2
        exit 1
    fi
    if [[ -e "$path" || -L "$path" ]]; then
        targets+=("$path")
    fi
done

if [[ ${#targets[@]} -eq 0 ]]; then
    echo "Nothing to delete."
    exit 0
fi

echo "The following directories will be deleted:"
for path in "${targets[@]}"; do
    size="$(du -sh "$path" 2>/dev/null | cut -f1 || true)"
    printf '  %s (%s)\n' "$path" "${size:-?}"
done

if command -v pgrep >/dev/null 2>&1 && pgrep -x nvim >/dev/null 2>&1; then
    echo "Warning: nvim is running. Files may be recreated when it exits." >&2
fi

if $dry_run; then
    echo "Dry run: nothing deleted."
    exit 0
fi

if ! $assume_yes; then
    read -r -p "Delete these directories? [y/N] " answer
    if [[ "$answer" != "y" && "$answer" != "Y" ]]; then
        echo "Cancelled."
        exit 0
    fi
fi

for path in "${targets[@]}"; do
    rm -rf -- "$path"
    echo "Deleted: $path"
done
