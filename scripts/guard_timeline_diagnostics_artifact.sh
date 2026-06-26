#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'USAGE'
Usage:
  scripts/guard_timeline_diagnostics_artifact.sh <artifact.json> [more.json-or-dir...]
  scripts/guard_timeline_diagnostics_artifact.sh --self-test

TimelineDiagnosticsExport の JSON artifact だけを対象に privacy marker を検査します。
repository 全体や docs を scan する guard ではありません。
directory を渡した場合は、その配下の *.json だけを検査します。
USAGE
}

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$repo_root" ]; then
    echo "error: git repository root を解決できませんでした。"
    exit 2
fi

cd "$repo_root" || exit 2

if ! command -v rg >/dev/null 2>&1; then
    echo "error: rg が見つかりません。Timeline diagnostics artifact privacy guard には ripgrep が必要です。"
    exit 2
fi

forbidden_pattern='nsec|secret|privateKey|private_key|raw_json|rawEvent|raw_event|raw[[:space:]_-]*event[[:space:]_-]*json|seed|mnemonic|keychain|nostr[[:space:]_-]+secret|dm[[:space:]_-]*raw|raw[[:space:]_-]*dm|direct[[:space:]_-]*message[[:space:]_-]*raw|raw[[:space:]_-]*private[[:space:]_-]*(content|message|dm)|private[[:space:]_-]*raw[[:space:]_-]*(content|message|dm)|decrypted[[:space:]_-]*(private|message|dm)|nip-?0?4[[:space:]_-]*plaintext|nip-?44[[:space:]_-]*plaintext|kind[[:space:]_-]*4[[:space:]_-]*raw'

run_self_test() {
    local tmpdir safe_json unsafe_json unsafe_log unsafe_status
    SELF_TEST_TMPDIR="$(mktemp -d)"
    tmpdir="$SELF_TEST_TMPDIR"
    trap 'rm -rf "${SELF_TEST_TMPDIR:-}"' EXIT

    safe_json="$tmpdir/safe-timeline-diagnostics.json"
    unsafe_json="$tmpdir/unsafe-timeline-diagnostics.json"
    unsafe_log="$tmpdir/unsafe.log"

    cat > "$safe_json" <<'JSON'
{
  "mutationRecords": [],
  "restoreGateRecords": ["restoreGate"],
  "restoreGateMetrics": [],
  "restoreGateDiagnostics": [
    {
      "metrics": [],
      "firstInteractiveScrollAllowedAtMS": 1735000000180,
      "networkWaitedBeforeInteractiveScrollMS": 0,
      "readMarkerChanged": false,
      "continuesSplash": false,
      "requiresNetworkWork": false,
      "requiresDBWork": false
    }
  ],
  "summary": {
    "restoreGateMetrics": {
      "totalAttempts": 1,
      "withinBudgetCount": 1,
      "overTargetCount": 0,
      "exceededBudgetCount": 0,
      "releaseBlockingCount": 0,
      "networkWaitedBeforeInteractiveScrollViolationCount": 0,
      "maxRestoreGateDurationMS": 180,
      "maxLocalInitialWindowQueryMS": 42,
      "maxInitialSnapshotApplyMS": 61,
      "maxAnchorRestoreMS": 12,
      "maxNetworkWaitedBeforeInteractiveScrollMS": 0,
      "latestFallbackReason": null,
      "readMarkerChanged": false,
      "continuesSplash": false,
      "requiresNetworkWork": false,
      "requiresDBWork": false
    }
  }
}
JSON

    cat > "$unsafe_json" <<'JSON'
{
  "mutationRecords": [],
  "restoreGateRecords": [],
  "restoreGateMetrics": [],
  "restoreGateDiagnostics": [],
  "raw_json": {
    "fixtureMarker": "nsec_test_marker_only"
  }
}
JSON

    "$0" "$safe_json" >/dev/null

    set +e
    "$0" "$unsafe_json" >"$unsafe_log" 2>&1
    unsafe_status=$?
    set -e

    if [ "$unsafe_status" -eq 0 ]; then
        echo "error: self-test の unsafe sample が reject されませんでした。"
        return 1
    fi

    echo "Timeline diagnostics artifact privacy guard self-test passed."
    echo " - safe sample passed"
    echo " - unsafe sample was rejected"
}

if [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

if [ "${1:-}" = "--self-test" ]; then
    run_self_test
    exit 0
fi

if [ "$#" -eq 0 ]; then
    usage
    exit 2
fi

artifact_files=()
invalid_input=0

for path in "$@"; do
    if [ -d "$path" ]; then
        found_in_dir=0
        while IFS= read -r -d '' json_file; do
            artifact_files+=("$json_file")
            found_in_dir=1
        done < <(find "$path" -type f -name '*.json' -print0)

        if [ "$found_in_dir" -eq 0 ]; then
            echo "error: $path に検査対象の *.json がありません。"
            invalid_input=1
        fi
    elif [ -f "$path" ]; then
        case "$path" in
            *.json) artifact_files+=("$path") ;;
            *)
                echo "error: $path は .json file ではありません。Timeline diagnostics artifact JSON だけを渡してください。"
                invalid_input=1
                ;;
        esac
    else
        echo "error: $path が見つかりません。"
        invalid_input=1
    fi
done

if [ "$invalid_input" -ne 0 ]; then
    exit 2
fi

if [ "${#artifact_files[@]}" -eq 0 ]; then
    echo "error: 検査対象の JSON artifact がありません。"
    exit 2
fi

matches_file="$(mktemp)"
trap 'rm -f "$matches_file"' EXIT

set +e
rg -n -i -o --color never -e "$forbidden_pattern" -- "${artifact_files[@]}" > "$matches_file"
rg_status=$?
set -e

case "$rg_status" in
    0)
        echo "Timeline diagnostics artifact privacy guard failed."
        echo "Forbidden privacy markers matched in JSON artifacts:"
        cat "$matches_file"
        echo
        echo "この guard は JSON artifact に含まれる marker だけを表示し、実 payload 行全体は表示しません。"
        exit 1
        ;;
    1)
        echo "Timeline diagnostics artifact privacy guard passed."
        echo "Scanned JSON artifacts:"
        printf ' - %s\n' "${artifact_files[@]}"
        ;;
    *)
        echo "error: rg scan failed with status $rg_status."
        exit "$rg_status"
        ;;
esac
