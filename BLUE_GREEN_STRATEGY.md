# Blue-Green Deployment Strategy

## What is Blue-Green Deployment?

Blue-Green Deployment is a release strategy that maintains **two identical production environments** — **Blue** (current live version) and **Green** (new version being prepared). At any point, only one environment serves real user traffic. Switching between them is instantaneous and requires **zero downtime**.

```
                        ┌─────────────────────────────────────────────────┐
                        │  Production Service  (NodePort :30000)          │
                        │  frontend-active-service                        │
                        └──────────────┬──────────────────────────────────┘
                                       │  selector: app=frontend-blue (initially)
                    ┌──────────────────┴──────────────────┐
                    ▼                                     │
         ┌──────────────────────┐                         │
         │  🔵 BLUE Deployment  │  ◄── LIVE (traffic)    │ (selector switch)
         │  frontend-blue       │                         │
         │  port: 3100          │                         ▼
         │  NodePort: 30100     │        ┌──────────────────────┐
         └──────────────────────┘        │  🟢 GREEN Deployment │  ◄── STANDBY
                                         │  frontend-green      │
                                         │  port: 3200          │
                                         │  NodePort: 30200     │
                                         └──────────────────────┘
```

---

## Architecture: The Switch Mechanism

### The Key — One Production Service

The `frontend-active-service` (NodePort **:30000**) is the **single production entry point**. It uses Kubernetes **label selectors** to route traffic. Switching is done by atomically patching:
1. `spec.selector.app` — which deployment receives traffic
2. `spec.ports[0].targetPort` — the container port to reach

```yaml
# Initially points to BLUE
spec:
  selector:
    app: frontend-blue    # ← Change to 'frontend-green' to switch
  ports:
    - targetPort: 3100    # ← Change to 3200 for Green
      nodePort: 30000     # ← This NEVER changes (users always hit :30000)
```

### Individual Debug Services (still available)
| Service | URL | Purpose |
|---------|-----|---------|
| `frontend-blue-service` | `:30100` | Direct Blue access for testing |
| `frontend-green-service` | `:30200` | Direct Green access for testing |
| `frontend-active-service` | `:30000` | **Production URL** — switches between slots |

---

## Deployment Files

```
k8s/
├── blue-green-switch/
│   ├── active-service.yaml    ← Production service (starts on Blue)
│   ├── patch-to-green.yaml    ← Declarative switch: Blue → Green
│   └── patch-to-blue.yaml     ← Declarative rollback: Green → Blue
├── backend/
├── frontend-blue/
└── frontend-green/

scripts/
└── bg-switch.sh               ← Interactive switch CLI tool
```

---

## How to Perform a Blue-Green Switch

### Option A — Using the Switch Script (Recommended)

```bash
# Make executable (first time only)
chmod +x scripts/bg-switch.sh

# Check what's currently active
./scripts/bg-switch.sh status

# Switch production traffic to Green
./scripts/bg-switch.sh green

# Roll back to Blue instantly
./scripts/bg-switch.sh blue
```

### Option B — Declarative (kubectl apply)

```bash
# Switch to Green
kubectl apply -f k8s/blue-green-switch/patch-to-green.yaml

# Roll back to Blue
kubectl apply -f k8s/blue-green-switch/patch-to-blue.yaml
```

### Option C — Imperative (kubectl patch)

```bash
# Switch to Green
kubectl patch service frontend-active-service -n blue-green \
  --type='json' \
  -p='[{"op":"replace","path":"/spec/selector/app","value":"frontend-green"},
       {"op":"replace","path":"/spec/ports/0/targetPort","value":3200}]'

# Rollback to Blue
kubectl patch service frontend-active-service -n blue-green \
  --type='json' \
  -p='[{"op":"replace","path":"/spec/selector/app","value":"frontend-blue"},
       {"op":"replace","path":"/spec/ports/0/targetPort","value":3100}]'
```

---

## Deployment Workflow

```
┌──────────────────────────────────────────────────────────────┐
│           Standard Blue-Green Deployment Workflow            │
└──────────────────────────────────────────────────────────────┘

 1. CURRENT STATE
    ├── Blue: LIVE (serving users via :30000)
    └── Green: idle / being updated

 2. UPDATE GREEN (no user impact)
    ├── Deploy new image to frontend-green-deployment
    └── Verify green pods are healthy (readiness probes pass)

 3. SMOKE TEST on Green's individual URL (:30200)
    └── QA team validates the new version directly

 4. SWITCH  →  ./scripts/bg-switch.sh green
    ├── Script validates green pods are Ready
    ├── Atomically patches active-service selector
    └── Users now hit Green via :30000  [ZERO DOWNTIME]

 5. MONITOR Green in production
    └── Watch logs: kubectl logs -l app=frontend-green -n blue-green -f

 6a. SUCCESS → Decommission or repurpose Blue for next release
 6b. ISSUE   → ./scripts/bg-switch.sh blue  (instant rollback < 1 second)
```

---

## Benefits of This Approach

| Benefit | How It's Achieved |
|---------|------------------|
| **Zero Downtime** | Service patch is atomic; Kubernetes routes immediately |
| **Instant Rollback** | One command, < 1 second switch back |
| **Safe Testing** | New version verifiable on `:30200` before going live |
| **Health Gated** | Switch script validates readiness before patching |
| **Idempotent** | `kubectl apply` can be run repeatedly safely |
| **Auditable** | Service annotations record active slot + last switch time |

---

## Useful Commands

```bash
# Watch pods in real time
kubectl get pods -n blue-green -w

# Check active service endpoints
kubectl get endpoints frontend-active-service -n blue-green

# View which slot is active
kubectl get service frontend-active-service -n blue-green \
  -o jsonpath='{.metadata.annotations.blue-green/active-slot}'

# Open production URL in browser
minikube service frontend-active-service -n blue-green

# Open specific slots for comparison
minikube service frontend-blue-service -n blue-green
minikube service frontend-green-service -n blue-green
```
