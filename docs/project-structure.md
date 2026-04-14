# IaCPOC — Project Structure & Design Decisions

## Folder Structure

```
IaCPOC/
├── bicepconfig.json              ← linting rules, module aliases
├── main.bicep                    ← (future) orchestration entry point for VSCode deploy
│
├── modules/                      ← reusable, single-responsibility modules
│   ├── networking/               ← VNet, subnets, private endpoint
│   ├── storage/                  ← storage account + SFTP config + VNet integration
│   ├── logicApp/                 ← Logic App standard + connections
│   └── monitoring/               ← Log Analytics workspace + tables
│
├── parameters/                   ← .bicepparam files per environment (dev, prod…)
│
└── docs/                         ← project documentation
```

## Solution Overview

The infrastructure comprises:

- **Storage Account** — VNet-integrated, SFTP-enabled for external customer access via private endpoint
- **Logic App** — reads logs from a blob container on the storage account and writes to a Log Analytics workspace table
- **Networking** — VNet with subnets and a private endpoint for the storage account
- **Monitoring** — Log Analytics workspace with a custom table populated by the Logic App

Deployment is performed manually using the VSCode Azure extension (right-click a `.bicep` file → Deploy).

## Design Decisions

- **Modules scoped by resource concern** — each subfolder under `modules/` owns one Azure resource area (networking, storage, logicApp, monitoring). This allows modules to be developed, tested, and deployed independently.

- **Root-level `main.bicep` as the orchestration entry point** — VSCode's Azure extension deploys from any `.bicep` file. Keeping the main orchestrator at the root makes the deploy target obvious and unambiguous.

- **`.bicepparam` files in `parameters/`** — Bicep's native parameter format (one file per environment, e.g. `dev.bicepparam`, `prod.bicepparam`). The VSCode deploy dialog lets you select the parameter file at deploy time.

- **`bicepconfig.json` at the root** — enables project-wide linting: warnings for unused parameters/variables, errors for secrets passed as plain-text params. Applies automatically to all `.bicep` files in the project.

- **No deployment scripts** — all deployments are triggered manually through the VSCode Azure extension, keeping the workflow simple and audit-friendly.
