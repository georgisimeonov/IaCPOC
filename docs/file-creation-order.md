# IaCPOC — File Creation Order & Dependencies

```
STEP 1 — modules/monitoring/
│
│   WHY FIRST: Has zero dependencies on other project resources.
│              Everything else may need to send logs to it.
│
└── logAnalyticsWorkspace.bicep
        Creates:  Log Analytics Workspace
        Outputs:  workspaceId, workspaceName, customerId
        Used by:  logicApp module (to write the table)


STEP 2 — modules/networking/
│
│   WHY SECOND: VNet and subnets must exist before any resource
│               can be injected into them or connected via private endpoint.
│
├── vnet.bicep
│       Creates:  Virtual Network + subnets
│                 (one subnet for storage VNet integration,
│                  one subnet for private endpoint)
│       Outputs:  vnetId, storageSubnetId, privateEndpointSubnetId
│       Used by:  storage module
│
└── privateEndpoint.bicep
        Creates:  Private Endpoint resource + private DNS zone link
        Params:   privateEndpointSubnetId (from vnet.bicep output)
                  storageAccountId        (from storage module output)
        Outputs:  privateEndpointId
        NOTE:     This file is defined here but called AFTER storage exists.
                  main.bicep controls the wiring.


STEP 3 — modules/storage/
│
│   WHY THIRD: Needs the subnet IDs from networking to configure
│              VNet integration and to be referenced by the private endpoint.
│
└── storageAccount.bicep
        Creates:  Storage Account
                  Blob container (for Logic App logs)
                  SFTP local user + permissions
                  VNet service endpoint / integration
        Params:   storageSubnetId (from vnet.bicep output)
        Outputs:  storageAccountId, storageAccountName,
                  blobEndpoint, blobContainerName
        Used by:  privateEndpoint.bicep (needs storageAccountId)
                  logicApp module       (needs blobEndpoint + container)


STEP 4 — modules/logicApp/
│
│   WHY FOURTH: Consumes outputs from both storage (where to read blobs)
│               and monitoring (where to write the table).
│               Must be last module — it is the top of the dependency tree.
│
└── logicApp.bicep
        Creates:  Logic App Standard (or Consumption)
                  API connections (Blob Storage, Log Analytics)
                  Workflow definition (read blob → write LA table)
        Params:   blobEndpoint        (from storage output)
                  blobContainerName   (from storage output)
                  workspaceId         (from monitoring output)
                  workspaceName       (from monitoring output)
        Outputs:  logicAppId, logicAppName


STEP 5 — main.bicep  (root)
│
│   WHY FIFTH: Written once all modules exist and their
│              input/output contracts are known.
│              This is the only file VSCode deploys.
│
└── main.bicep
        Calls:    monitoring module  → captures outputs
                  networking module  → captures outputs
                  storage module     → passes networking outputs in
                  privateEndpoint    → passes networking + storage outputs in
                  logicApp module    → passes storage + monitoring outputs in
        Params:   all top-level params (location, env, naming prefix, etc.)


STEP 6 — parameters/
│
│   WHY LAST: Written after main.bicep params are finalised.
│             One file per environment.
│
├── dev.bicepparam     ← references main.bicep, overrides values for dev
└── prod.bicepparam    ← references main.bicep, overrides values for prod
```

## Key Principle

Outputs flow downward. Each module exposes what it creates, and the next module
consumes those values as parameters. main.bicep is the glue that wires all
outputs to inputs — which is why it can only be written once all modules are stable.
