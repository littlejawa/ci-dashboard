# OSC CI Dashboard

A single-page dashboard for monitoring OpenShift Sandboxed Containers Operator CI job results.

## What it does

- Discovers all periodic CI jobs for `openshift/sandboxed-containers-operator` from the public GCS bucket
- Fetches recent build results (pass/fail, duration, timestamps) live in the browser
- Parses job metadata: cloud provider, OCP version, test type, release type
- Displays a filterable, sortable table with per-job pass rates and history sparklines
- Supports on-demand loading of older runs beyond the initial fetch window

No backend, no build step, no external dependencies. Everything runs client-side against the public Prow/GCS APIs.

## Usage

Open `index.html` directly in a browser — it works from `file://` since it only fetches from public HTTPS APIs with permissive CORS headers.

Alternatively, serve it over HTTP:

```bash
cd osc-ci-dashboard
python3 -m http.server 8080
# open http://localhost:8080
```

Or enable GitHub Pages in the repo settings, pointing to the `main` branch root. The dashboard will be available at `https://<org>.github.io/osc-ci-dashboard/`.

## Data sources

All data comes from public, unauthenticated APIs:

- **Job discovery:** GCS listing of `gs://test-platform-results-public/logs/periodic-ci-openshift-sandboxed-containers-operator-*`
- **Build results:** `started.json` and `finished.json` per build in the same bucket
- **Links:** Each run links to its Prow build page for full logs and artifacts

## Filters

The dashboard supports filtering by:

| Filter | Values |
|---|---|
| Cloud | AWS, Azure, ARO, N/A (for non-cloud tests) |
| OCP Version | 4.19 through 5.0 |
| Test Type | kata, coco, peerpods, kata-disconnected, peerpods-sts, tls-scanner, etc. |
| Release Type | Pre-GA, GA |
| Status | Passing, Failing |
| Search | Free-text match on full job name |

All columns are sortable. Click any row to expand and see individual run details with links to Prow.
