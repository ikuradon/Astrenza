#!/usr/bin/env bash
set -u

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$repo_root" ]; then
    echo "error: git repository root を解決できませんでした。"
    exit 2
fi

cd "$repo_root" || exit 2

if ! command -v rg >/dev/null 2>&1; then
    echo "error: rg が見つかりません。DesignSystem guard には ripgrep が必要です。"
    exit 2
fi

scan_roots=(
    "Packages/DesignSystem/Sources/DesignSystem"
)

optional_roots=(
    "Astrenza/Sources/AstrenzaApp/TimelineEngine"
    "Astrenza/Sources/AstrenzaApp/TimelineRows"
    "Astrenza/Sources/AstrenzaApp/TimelineV1"
)

existing_roots=()
for root in "${scan_roots[@]}" "${optional_roots[@]}"; do
    if [ -d "$root" ]; then
        existing_roots+=("$root")
    fi
done

if [ "${#existing_roots[@]}" -eq 0 ]; then
    echo "DesignSystem static guard: scan 対象がありません。"
    exit 0
fi

scan_files="$(mktemp)"
violations_file="$(mktemp)"
icon_frame_file="$(mktemp)"
trap 'rm -f "$scan_files" "$violations_file" "$icon_frame_file"' EXIT

is_allowlisted_file() {
    case "$1" in
        Packages/DesignSystem/Sources/DesignSystem/Tokens/*) return 0 ;;
        Packages/DesignSystem/Sources/DesignSystem/Timeline/*Metrics.swift) return 0 ;;
        Packages/DesignSystem/Tests/DesignSystemTests/*) return 0 ;;
        *) return 1 ;;
    esac
}

for root in "${existing_roots[@]}"; do
    rg --files "$root" -g '*.swift'
done | sort -u | while IFS= read -r file; do
    if ! is_allowlisted_file "$file"; then
        printf '%s\n' "$file"
    fi
done > "$scan_files"

violations=0

check_pattern() {
    label="$1"
    pattern="$2"
    found=0

    while IFS= read -r file; do
        matches="$(rg -n "$pattern" "$file" || true)"
        if [ -n "$matches" ]; then
            if [ "$found" -eq 0 ]; then
                {
                    echo
                    echo "[$label]"
                } >> "$violations_file"
            fi
            echo "$matches" >> "$violations_file"
            found=1
        fi
    done < "$scan_files"

    if [ "$found" -eq 1 ]; then
        violations=1
    fi
}

check_pattern "raw fixed system font" '\.font\(\.system\(size:'
check_pattern "numeric padding" '\.padding\([[:space:]]*[0-9]+(\.[0-9]+)?[[:space:]]*\)'
check_pattern "numeric corner radius" '\.cornerRadius\([[:space:]]*[0-9]+(\.[0-9]+)?'
check_pattern "raw SF Symbol literal" 'Image\(systemName:[[:space:]]*"[^"]+"'

while IFS= read -r file; do
    awk '
        /Image[[:space:]]*\([[:space:]]*systemName:/ {
            sf_symbol_window = 6
        }
        sf_symbol_window > 0 && /\.frame\([^)]*(width|height):[[:space:]]*[0-9]/ {
            if ($0 !~ /(DSIcon|TimelineActionMetrics|TimelineContextChipMetrics|TimelineRowMetrics|DSMediaMetrics)/) {
                print FILENAME ":" NR ":" $0
            }
        }
        sf_symbol_window > 0 {
            sf_symbol_window--
        }
    ' "$file"
done < "$scan_files" > "$icon_frame_file"

if [ -s "$icon_frame_file" ]; then
    {
        echo
        echo "[ad-hoc SF Symbol numeric frame]"
        cat "$icon_frame_file"
    } >> "$violations_file"
    violations=1
fi

if [ "$violations" -ne 0 ]; then
    echo "DesignSystem static guard failed."
    cat "$violations_file"
    echo
    echo "Tokens、Timeline/*Metrics.swift、DesignSystemTests は baseline 値や expected 値のため allowlist されています。"
    echo "この v1 guard は conservative な rg/awk scan です。必要な styling は DSIcon / TimelineActionMetrics / TimelineContextChipMetrics / TimelineRowMetrics / DSMediaMetrics 経由にしてください。"
    exit 1
fi

echo "DesignSystem static guard passed."
echo "Scanned roots:"
printf ' - %s\n' "${existing_roots[@]}"
