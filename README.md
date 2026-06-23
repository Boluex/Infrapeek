# infrapeek

> **Preview your infrastructure topology, relationships, and security posture in your terminal before you deploy.**

`infrapeek` is a lightweight, zero-dependency-by-default Bash tool that lets you scan any infrastructure directory to understand exactly what you are building. It parses your source definitions, builds a unified resource dependency graph, detects targeting towards LocalStack, runs security heuristic checks, and renders a clean visualization — all in the console, before you run `terraform apply`, `docker compose up`, `kubectl apply`, or `cdk deploy`.

It is designed for **learners**, **educators**, and **engineers** who want to deploy with absolute clarity and confidence.

---

## 🎨 Visual Preview

`infrapeek` dynamically formats the output depending on your configuration:

### 1. Nested AWS VPC Network Diagram (Terraform)
When scanning a Terraform project that contains a VPC, `infrapeek` draws the actual containment topology and routes (Internet $\to$ Internet Gateway $\to$ Subnets $\to$ Instances/NAT) using exact-width box characters, plus a detailed list of security-group-derived data flows:

```text
       +--------------------+
       |   PUBLIC INTERNET  |
       +---------+----------+
                 |
        +--------+--------+
        |                 |
     Public Web Traffic (80/443)  SSH Administration (Port 22)
        |                 |
        v                 v
+-------+-----------------+----------------------------------------+
| VIRTUAL PRIVATE CLOUD (VPC)   10.0.0.0/16                        |
|                                                                  |
| +--------------------------------------------------------------+ |
| | PUBLIC SUBNET (10.0.1.0/24)  -  routes to Internet via IGW   | |
| |                                                              | |
| | +---------------+   +---------------+                        | |
| | | Nginx Frontend|   | NAT Gateway   |                        | |
| | | (nginx)       |   | (nat)         |                        | |
| | +---------------+   +---------------+                        | |
| +--------------------------------------------------------------+ |
|                                                                  |
|       |  v  8000/app        Nginx Frontend --> Django Backend    |
|       |  ^  egress          Django Backend --> NAT Gateway --> Internet
| +--------------------------------------------------------------+ |
| | PRIVATE SUBNET 1 (10.0.2.0/24)  -  outbound via NAT Gateway  | |
| |                                                              | |
| | +---------------+                                            | |
| | | Django Backend|                                            | |
| | | (django)      |                                            | |
| | +---------------+                                            | |
| +--------------------------------------------------------------+ |
+------------------------------------------------------------------+

  Legend:  v = inbound into a subnet/VPC      ^ = egress out via NAT
```

### 2. Layered Branching Tree (Flat / Non-VPC / Docker Compose / Kubernetes / AWS CDK)
For compose, k8s, CDK, or flat Terraform layouts, it structures and centers resources side-by-side inside category-ranked layers with auto-routing connection lines:

```text
               Internet
                  │
         ┌────────▼────────┐
         │  Load Balancer  │
         │  api_gateway    │
         └────────┬────────┘
         ┌────────┴────────┐
         │                 │
  ┌──────▼──────┐   ┌──────▼──────┐
  │   Function  │   │   Function  │
  │  get_order  │   │ process_order │
  └──────┬──────┘   └──────┬──────┘
         └────────┬────────┘
               ┌──▼──┐
               │ DB  │
               │ rds │
               └─────┘
```

---

## ⚡ Key Features

- 🔍 **Auto-Format Detection**: Instantly detects Terraform (`*.tf`), Docker Compose (`docker-compose.yml` / `compose.yml`), Kubernetes configurations (`*.yaml`), and AWS CDK applications (`cdk.json`).
- ☁️ **LocalStack Flagging**: Auto-detects endpoint overrides, LocalStack Docker images, or local AWS URLs, displaying a visual badge in the header.
- 🗂️ **VPC / Subnet Isolation**: Visualizes AWS network topologies, security groups, public/private subnets, and routing flows directly in the terminal.
- 🛡️ **Heuristic Security Auditing**: Flags security risks (e.g. `0.0.0.0/0` ports open to the world, public S3 buckets, unencrypted databases, privileged container modes, missing liveness/readiness probes, and hardcoded secrets) with clean terminal warning alerts.
- 🖼️ **Multi-Format Export**: Generates `.dot`, PNG, and SVG graphics, prints interactive fuzzy search displays (`fzf`), or outputs standard GitHub Markdown Mermaid diagrams (`--mermaid`).

---

## 🚀 Installation

### 1. Quick Install (cURL)
Install the latest release system-wide:
```bash
curl -fsSL https://raw.githubusercontent.com/USER/infrapeek/main/install.sh | bash
```

### 2. Manual Installation
```bash
git clone https://github.com/USER/infrapeek.git
cd infrapeek
sudo ./install.sh
```

### 3. User Installation (No `sudo` required)
Install to `$HOME/.local/bin` and `$HOME/.local/lib/infrapeek`:
```bash
./install.sh --user
```

### 4. Running Without Installing
Run the executable directly from the cloned repository source tree:
```bash
./infrapeek /path/to/infra-project
```

---

## 📖 CLI Usage

```text
infrapeek [PATH] [OPTIONS]

ARGUMENTS
  PATH              Directory to scan (default: current directory)

OPTIONS
  --diagram         Export PNG + SVG diagrams (requires graphviz 'dot')
  --mermaid         Print a Mermaid graph block of the real dependency graph
  --ascii-graph     Draw the real dependency graph as ASCII in the terminal
                    (requires Perl's 'graph-easy')
  --wide            Force full-width branching rendering (stops terminal auto-wrap)
  --flat            Force a flat layered graph instead of a nested VPC view
  --interactive     Launch an interactive resource browser (requires 'fzf')
  --format FMT      Force a specific parser format: tf | compose | k8s | cdk
  --no-warn         Skip the security and best-practice validation warnings
  --version, -V     Print CLI version and exit
  --help, -h        Print usage documentation and exit
```

### Example Commands
```bash
infrapeek                         # Scan the current directory
infrapeek ~/my-terraform-project  # Scan a specific directory path
infrapeek --diagram               # Parse and output graphviz files (infrapeek.dot/png/svg)
infrapeek --mermaid               # Output GitHub-ready Mermaid.js block and write infrapeek.mmd
infrapeek --interactive           # Open terminal fuzzy finder to browse metadata
infrapeek --format compose .      # Force-parse directory using Docker Compose parser
```

---

## 🛠️ Supported Frameworks & Analyzers

| Tool / Framework | Detection Heuristics | Parsed Details & Dependencies |
| :--- | :--- | :--- |
| **Terraform** | Any file matching `*.tf` | Resources, attributes, internal block relationships, variables, and security group inputs. |
| **Docker Compose** | `docker-compose.yml`, `compose.yml`, `docker-compose.yaml`, `compose.yaml` | Service blocks, environment variables, images, ports, and `depends_on` dependencies. |
| **Kubernetes** | Any `*.yaml`/`*.yml` file containing `apiVersion` and `kind` | Deployments, Services, Pods, Ingress routes, securityContext, and resource limits. |
| **AWS CDK** | `cdk.json` | Runs synth to parse CloudFormation JSON outputs (looks up resource types, metadata, and relations). |

---

## 🔍 Heuristic Security Policies Checked

`infrapeek` runs static analysis checks on your infrastructure scripts to flag potential misconfigurations:

### AWS (Terraform / AWS CDK)
- **Wildcard Security Inbound**: Identifies security groups allowing inbound traffic from `0.0.0.0/0` (especially port 22/SSH).
- **Public Storage**: Detects S3 bucket configurations with policies allowing `public-read`, `PublicRead`, or `AllUsers`.
- **Data Encrypt-at-Rest**: Confirms if DynamoDB, RDS, or DB Instances have encryption/KMS key server-side encryption configured.
- **S3 Bucket Versioning**: Flags buckets that do not have versioning enabled.
- **Serverless Timeouts**: Warns when Lambda timeouts are not explicitly configured (preventing sudden 3s default timeouts).

### Docker Compose
- **Privileged Access**: Flags containers running with `privileged: true` (grants host kernel-level control).
- **Global Bindings**: Flags container ports exposed to all interfaces (`0.0.0.0:`).
- **Static Credentials**: Warns if environmental parameters match potential password, token, or secret strings.
- **Unpinned Tags**: Detects container images using the `:latest` tag instead of a specific version tag.

### Kubernetes
- **Node Escape Control**: Flags container blocks requesting `privileged: true` or `hostNetwork: true`.
- **Resource Starvation**: Warns if workloads fail to declare explicit CPU and Memory `requests` / `limits`.
- **Unchecked Health**: Flags workloads that do not define `livenessProbe` or `readinessProbe` health checks.

---

## 🧩 Optional Dependencies

The core script works using standard built-in Linux utilities. Install these optional utilities to unlock advanced visualization and navigation modes:

1. **Graphviz (`dot`)** (Unlocks `--diagram` PNG & SVG exports):
   - *Ubuntu:* `sudo apt-get install graphviz`
   - *macOS:* `brew install graphviz`
2. **FZF** (Unlocks `--interactive` fuzzy browser):
   - *Ubuntu:* `sudo apt-get install fzf`
   - *macOS:* `brew install fzf`
3. **Graph::Easy** (Unlocks `--ascii-graph` block layouts):
   - *Ubuntu:* `sudo apt-get install libgraph-easy-perl`
   - *CPAN:* `cpan Graph::Easy`
4. **jq** (Used for richer AWS CDK CloudFormation metadata extraction; falls back to standard text processing if missing).

---

## 🏗️ Architecture Design & Pipeline

```text
Detect Format ──> Parse Resources ──> Shared Model ──> Render Visualization
                                                      ├── Nested VPC/Subnet Map
                                                      ├── Flat Category Tree
                                                      ├── Mermaid/Graphviz Export
                                                      ├── Interactive fzf Browser
                                                      └── Heuristic Validator
```

- **Shared Data Model**: Every parser populates a unified in-memory associative data structure defining resource IDs, names, types, categories, and edge connections.
- **Independent Parsers**: Adding support for a new framework is as simple as adding a single script (`lib/parse_*.sh`) to register resources into the shared model.
- **Decoupled Renderers**: Renderers read solely from the shared model, allowing flexible outputs independent of the source infrastructure framework.

---

## 📂 Project Layout

```text
infrapeek/
├── infrapeek              # Main command executable (manages pipeline and rendering flow)
├── install.sh             # Installation script supporting system-wide and user scopes
├── lib/                   # Module directory for detection, parsers, renderers, and validation
│   ├── detect.sh          # Auto-detection for project formats and LocalStack targeting
│   ├── parse_cdk.sh       # Synthesized AWS CDK CloudFormation parser
│   ├── parse_compose.sh   # Docker Compose file syntax parser
│   ├── parse_k8s.sh       # Kubernetes YAML manifest parser
│   ├── parse_terraform.sh # Terraform HCL syntax parser
│   ├── render_ascii.sh    # Flat vertical ASCII stacked renderer
│   ├── render_dot.sh      # Graphviz DOT generator
│   ├── render_fzf.sh      # Interactive fzf resource & metadata browser
│   ├── render_mermaid.sh  # Markdown Mermaid graph definitions exporter
│   ├── render_tree.sh     # Clean layered branching ASCII tree layout renderer
│   ├── render_vpc.sh      # Nested AWS network VPC diagram compiler
│   └── validate.sh        # Static security warnings and rule checks validator
├── tests/                 # Integrated test runner and fixture directories
│   ├── fixtures/          # Configuration test sets for each supported system
│   └── test.sh            # End-to-end verification script
└── README.md              # This file
```

---

## 🧪 Testing

A suite of end-to-end tests runs against static fixtures to verify parser accuracy, formatting detection, and LocalStack flagging.

Run the tests:
```bash
./tests/test.sh
```

---

## 📄 License

MIT — see source headers for details. Cost calculations and warning heuristics are approximations and provided as-is.
