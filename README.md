# OSC CI Dashboard

A dashboard for monitoring OpenShift Sandboxed Containers Operator periodic CI job results, powered by [prowjob-analyzer](https://github.com/openshift/sandboxed-containers-operator/tree/main/scripts/prowjob-analyzer).

## How it works

1. `collect.sh` runs [prowjob-analyzer](https://github.com/openshift/sandboxed-containers-operator/tree/main/scripts/prowjob-analyzer) to discover recent builds and analyze each one, producing one JSON file per build under `results/`.
2. After analyzing all builds, it rebuilds `results/manifest.json` — a lightweight index with summary data for each build.
3. `index.html` loads the manifest to populate a filterable table, and lazy-loads individual result files on demand for detailed views.

## Collecting results

### Prerequisites

- Python 3
- A clone of [sandboxed-containers-operator](https://github.com/openshift/sandboxed-containers-operator) with the `scripts/prowjob-analyzer/` directory (and its dependencies)

### Running

```bash
export PROWJOB_ANALYZER_DIR="/path/to/projob-analyzer"

# Analyze builds from the last 7 days (default)
./collect.sh

# Analyze builds since a specific date
./collect.sh --since 2026-11-01

# Specify the prowjob-analyzer location
./collect.sh --analyzer-dir /path/to/prowjob-analyzer
```

Collection is incremental: builds that already have a JSON file in `results/` are skipped, so re-running the script only analyzes new builds.

### Scheduling with cron

To keep the dashboard up to date automatically:

```bash
# Run every 6 hours, analyze the last 3 days of builds
0 */6 * * * /path/to/collect.sh --since "$(date -d '3 days ago' +\%Y-\%m-\%d)"
```

## Viewing the dashboard

- From the root, run “python3 -m http.server 8080”
- In your browser, go to "localhost:8080"

## Dashboard features

- **Summary cards**: total builds, pass/fail counts, pass rate, top failure pattern
- **Filterable table**: cloud provider, OCP version, workload type, status, root cause pattern, free-text search
- **Sortable columns**: click any column header to sort
- **Detail view**: expand any row to see:
  - Catalog info (tag, build date, kata RPM version, operator version)
  - Category breakdown (infra, overall, smoke, OSC, kata upstream, CAA) with status and timing
  - Root cause analysis with confidence level
  - Failing tests list
  - Test suite summary
  - Links to Prow artifacts

## Result files

Each build produces a `<build-id>.json` file containing the full prowjob-analyzer output: job metadata, test results, failure analysis, root cause patterns, and artifact URLs.

`manifest.json` is an index with summary fields extracted from each build file, used by the dashboard for the table view without loading every detail file.
