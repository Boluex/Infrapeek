# infrapeek

**Preview your infrastructure before you deploy it.**

`infrapeek` is a single Bash tool you run against any infrastructure project
directory. It reads your definition files, builds a dependency graph, and shows
you a **diagram**, a **resource list**, **validation warnings**, and a rough
**cost estimate** — all in your terminal, before you run `terraform apply`,
`docker compose up`, `kubectl apply`, or `cdk deploy`.

It's built for **learners**: see what your code actually builds and how the
pieces connect, then deploy with confidence.

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 infrapeek  v0.1.0          Terraform • LocalStack
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

ARCHITECTURE

         Internet
            │
   ┌────────▼────────┐
   │  Api Gateway    │
   │  api            │
   └────────┬────────┘
            │
   ┌────────▼────────┐
   │ Lambda Function │
   │ process_order   │
   └────────┬────────┘
            │
   ┌────────▼────────┐
   │    Dynamodb     │
   │  orders_table   │
   └─────────────────┘
```

## Supported tools (v1)

| Tool             | Detected by                         | Parsed                                   |
|------------------|-------------------------------------|------------------------------------------|
| Terraform        | `*.tf`                              | `resource` blocks + references           |
| Docker Compose   | `docker-compose.yml` / `compose.yml`| services, ports, `depends_on`            |
| Kubernetes       | YAML with `apiVersion` + `kind`     | Deployments, Services, Ingress, …        |
| AWS CDK          | `cdk.json`                          | `cdk synth` → CloudFormation JSON        |
| LocalStack       | `:4566` / `localstack` endpoints    | flagged in the header badge              |

## Install

Via curl:

```bash
curl -fsSL https://raw.githubusercontent.com/USER/infrapeek/main/install.sh | bash
```

Or manually:

```bash
git clone https://github.com/USER/infrapeek
cd infrapeek
sudo ./install.sh
```

The installer copies `infrapeek` to `/usr/local/bin`, its libraries to
`/usr/local/lib/infrapeek`, and checks for optional dependencies.

### Run without installing

```bash
git clone https://github.com/USER/infrapeek
./infrapeek/infrapeek ~/my-project
```

## Usage

```
infrapeek [PATH] [OPTIONS]

Arguments:
  PATH              Directory to scan (default: current directory)

Options:
  --diagram         Export PNG + SVG (requires graphviz 'dot')
  --interactive     Launch interactive resource browser (requires fzf)
  --format FMT      Force a parser: tf | k8s | compose | cdk
  --no-cost         Skip the cost estimate section
  --no-warn         Skip the validation / warnings section
  --version         Print version
  --help            Print help
```

### Examples

```bash
infrapeek                       # scan the current directory
infrapeek ~/my-terraform-proj   # scan a specific path
infrapeek --diagram             # also export infrapeek-diagram.png/.svg
infrapeek --interactive         # browse resources with fzf
infrapeek --format compose .    # force the Docker Compose parser
```

## Output sections

1. **ARCHITECTURE** — a top-down Unicode diagram of the dependency flow.
2. **RESOURCES** — every resource parsed, with its type and name.
3. **WARNINGS** — heuristic security / best-practice checks (`⚠` / `✓`).
4. **COST ESTIMATE** — ballpark monthly cost (Terraform + CDK), from a static
   table. No API calls; figures are for learning, not billing.

## Optional dependencies

`infrapeek` works with zero extra dependencies. These unlock extra output modes:

- **graphviz** (`dot`) — `--diagram` PNG/SVG export.
- **fzf** — `--interactive` resource browser.
- **jq** — richer AWS CDK parsing (falls back to grep/awk if absent).

If a dependency is missing, that mode is skipped with a one-line install hint.

## How it works

```
detect → parse → build graph → render (ascii / dot / fzf) → validate → cost
```

Each parser populates a shared in-memory model (resources + edges). Renderers,
the validator, and the cost estimator all read from that single model, so
adding a new tool means writing one `parse_*.sh` and nothing else.

## Requirements

- Bash **4.0+** (associative arrays)
- `grep`, `awk`, `sed` (standard on Linux/macOS/WSL2)
- Tested on Ubuntu 20.04+, macOS 12+, WSL2

## Project layout

```
infrapeek/
├── infrapeek              # main executable
├── install.sh             # installer
├── lib/                   # detect / parse / render / validate / cost
├── tests/                 # fixtures + test runner
└── README.md
```

## License

MIT — see source. Cost figures are approximate and provided as-is.
