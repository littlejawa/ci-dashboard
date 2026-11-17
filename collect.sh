#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESULTS_DIR="$SCRIPT_DIR/results"

usage() {
    echo "Usage: $0 [--since DATE] [--analyzer-dir PATH]"
    echo ""
    echo "Collect prowjob analysis results for the OSC CI dashboard."
    echo ""
    echo "Options:"
    echo "  --since DATE         Analyze builds since DATE (default: 7 days ago)"
    echo "  --analyzer-dir PATH  Path to prowjob-analyzer scripts directory"
    echo "                       (default: use PROWJOB_ANALYZER_DIR env var)"
    exit 1
}

SINCE=$(date -d '7 days ago' +%Y-%m-%d 2>/dev/null || date -v-7d +%Y-%m-%d)
ANALYZER_DIR="${PROWJOB_ANALYZER_DIR:-}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --since) SINCE="$2"; shift 2 ;;
        --analyzer-dir) ANALYZER_DIR="$2"; shift 2 ;;
        --help|-h) usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

if [ -z "$ANALYZER_DIR" ] || [ ! -f "$ANALYZER_DIR/dig.py" ]; then
    echo "Error: prowjob-analyzer not found. Set PROWJOB_ANALYZER_DIR or use --analyzer-dir."
    exit 1
fi

echo "Analyzer: $ANALYZER_DIR"
echo "Since:    $SINCE"
echo ""

mkdir -p "$RESULTS_DIR"

echo "Discovering builds..."
URLS=$("$ANALYZER_DIR/batch_job_history.py" --since "$SINCE" --no-group-headers 2>/dev/null || true)

if [ -z "$URLS" ]; then
    echo "No builds found since $SINCE"
    exit 0
fi

TOTAL=$(echo "$URLS" | grep -c '^http' || true)
echo "Found $TOTAL builds"
echo ""

NEW=0
SKIPPED=0
FAILED=0

while IFS= read -r URL; do
    [[ -z "$URL" || ! "$URL" =~ ^http ]] && continue

    BUILD_ID=$(basename "$URL")

    if [ -f "$RESULTS_DIR/$BUILD_ID.json" ]; then
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    echo -n "  $BUILD_ID ... "

    TMPFILE=$(mktemp)
    EXIT_CODE=0
    (cd "$ANALYZER_DIR" && python3 dig.py "$URL" --json --no-wait) 2>/dev/null | sed -n '/^{/,$p' > "$TMPFILE" || EXIT_CODE=$?

    if [ "$EXIT_CODE" -le 1 ] && [ -s "$TMPFILE" ] && python3 -I -c "import json,sys; json.load(sys.stdin)" < "$TMPFILE" 2>/dev/null; then
        mv "$TMPFILE" "$RESULTS_DIR/$BUILD_ID.json"
        NEW=$((NEW + 1))
        echo "ok"
    else
        rm -f "$TMPFILE"
        FAILED=$((FAILED + 1))
        echo "failed (exit $EXIT_CODE)"
    fi
done <<< "$URLS"

echo ""
echo "Results: $NEW new, $SKIPPED already analyzed, $FAILED errors ($TOTAL total)"
echo ""

echo "Rebuilding manifest..."
python3 -I -c "
import json, os, sys
from datetime import datetime, timezone

results_dir = sys.argv[1]
entries = []
for fname in sorted(os.listdir(results_dir)):
    if not fname.endswith('.json') or fname == 'manifest.json':
        continue
    path = os.path.join(results_dir, fname)
    try:
        with open(path) as f:
            data = json.load(f)
    except (json.JSONDecodeError, IOError) as e:
        print(f'  Warning: skipping {fname}: {e}', file=sys.stderr)
        continue

    pj = data.get('prowjob', {})
    md = data.get('metadata', {})
    rc = data.get('root_cause') or data.get('failure_analysis', {}).get('root_cause') or {}
    tr = data.get('test_results') or {}
    cats = data.get('result_categories', {})

    entries.append({
        'file': fname,
        'build_id': pj.get('build_id', fname.replace('.json', '')),
        'job_name': pj.get('name', ''),
        'status': pj.get('status', 'unknown'),
        'start_time': pj.get('start_time', ''),
        'duration_seconds': pj.get('duration_seconds', 0),
        'test_elapsed_time': data.get('test_elapsed_time', ''),
        'provider': md.get('provider', ''),
        'ocp_version': md.get('ocp_version', ''),
        'workload_type': md.get('workload_type', ''),
        'variant': md.get('variant', ''),
        'kata_rpm_version': md.get('kata_rpm_version', ''),
        'catalog': md.get('catalog_full_tag') or md.get('catalog_version') or '',
        'categories': {k: v.get('status', 'unknown') for k, v in cats.items()},
        'primary_pattern': rc.get('primary_pattern', ''),
        'confidence': rc.get('confidence', ''),
        'tests_total': tr.get('total', 0),
        'tests_passed': tr.get('passed', 0),
        'tests_failed': tr.get('failures', 0),
    })

entries.sort(key=lambda e: e.get('start_time', ''), reverse=True)
manifest = {
    'generated_at': datetime.now(timezone.utc).isoformat(),
    'total_entries': len(entries),
    'entries': entries,
}
manifest_path = os.path.join(results_dir, 'manifest.json')
with open(manifest_path, 'w') as f:
    json.dump(manifest, f, indent=2)
print(f'Manifest: {len(entries)} entries')
" "$RESULTS_DIR"

echo "Done."
