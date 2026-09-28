# Cloud-Native Microservices Platform: Zero-Trust Mesh & SRE Observability

[![OpenTofu](https://img.shields.io/badge/IaC-OpenTofu_v1.8+-FFDA18?logo=opentofu&logoColor=black)](https://opentofu.org/)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.30-326CE5?logo=kubernetes&logoColor=white)](https://kubernetes.io/)
[![Istio](https://img.shields.io/badge/Service_Mesh-Istio_v1.22+-466BB0?logo=istio&logoColor=white)](https://istio.io/)
[![AWS](https://img.shields.io/badge/Cloud-AWS_EKS-232F3E?logo=amazon-aws&logoColor=white)](https://aws.amazon.com/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

A production-grade cloud-native platform demonstrating modern application lifecycle operations: multi-stage distroless container builds, declarative infrastructure with OpenTofu, zero-trust traffic mesh (mTLS), and Google SRE Golden Signal observability with chaos engineering resilience testing.

---

## Table of Contents
1. [Architecture Overview & Request Lifecycle](#1-architecture-overview--request-lifecycle)
2. [Platform Capabilities & Compliance Matrix](#2-platform-capabilities--compliance-matrix)
3. [Technology Rationale & Design Decisions](#3-technology-rationale--design-decisions)
4. [Repository Structure](#4-repository-structure)
5. [Prerequisites & Local Tooling](#5-prerequisites--local-tooling)
6. [Step-by-Step Deployment Runbook](#6-step-by-step-deployment-runbook)
7. [Observability & SRE Golden Signals](#7-observability--sre-golden-signals)
8. [Chaos Engineering & Resilience Testing](#8-chaos-engineering--resilience-testing)
9. [Decommissioning & Teardown](#9-decommissioning--teardown)

---

## 1. Architecture Overview & Request Lifecycle

The platform provisions a multi-tier microservice architecture decoupled into presentation, business logic, and relational persistence layers.

```text
                                   NORTH - SOUTH TRAFFIC
                                            │
                                [ Public Internet Request ]
                                            │
                                            ▼
                           ┌───────────────────────────────────┐
                           │     AWS Network Load Balancer     │
                           └────────────────┬──────────────────┘
                                            │
                                            ▼
                           ┌───────────────────────────────────┐
                           │      Istio Ingress Gateway        │ (Edge Routing & TLS)
                           └────────────────┬──────────────────┘
────────────────────────────────────────────┼────────────────────────────────────────────
                                            │ EAST - WEST TRAFFIC (Strict mTLS)
                                            ▼
                           ┌───────────────────────────────────┐
                           │     Frontend Pod (Express)        │
                           │  ┌───────────┐   ┌──────────────┐ │
                           │  │   Envoy   │───│  Node.js     │ │
                           │  │  Sidecar  │   │ (Distroless) │ │
                           │  └───────────┘   └──────────────┘ │
                           └────────────────┬──────────────────┘
                                            │ (Encrypted SPIFFE mTLS)
                                            ▼
                           ┌───────────────────────────────────┐
                           │     Backend Pod (FastAPI)         │
                           │  ┌───────────┐   ┌──────────────┐ │
                           │  │   Envoy   │───│  Python      │ │
                           │  │  Sidecar  │   │ (Distroless) │ │
                           │  └───────────┘   └──────────────┘ │
                           └────────────────┬──────────────────┘
                                            │ (Intra-Cluster TCP)
                                            ▼
                           ┌───────────────────────────────────┐
                           │     Stateful Database Pod         │
                           │  ┌───────────┐   ┌───────────┐    │
                           │  │   Envoy   │───│PostgreSQL │    │
                           │  │  Sidecar  │   │ (Storage) │    │
                           │  └───────────┘   └─────┬─────┘    │
                           └────────────────────────┼──────────┘
                                                    ▼
                                           [ AWS EBS (gp3) PVC ]
```

### Flow Walkthrough (Step-by-step request flow)

1. **North-South Ingress**: External user traffic hits an AWS Network Load Balancer managed by the Istio IngressGateway, acting as the centralized cluster API Gateway.
2. **Edge Routing**: Istio `Gateway` and `VirtualService` resources evaluate layer-7 route rules, forwarding traffic to the internal frontend service.
3. **East-West Encryption**: Frontend communication to the Python FastAPI backend is secured inside an mTLS (Mutual TLS) tunnel automatically negotiated between Envoy sidecars.
4. **Data Layer Isolation:** PostgreSQL runs as a `StatefulSet` with an EBS-backed `PersistentVolumeClaim`. Ingress is restricted exclusively to the backend service via Kubernetes `NetworkPolicy`.
5. **Distributed Telemetry**: All HTTP spans (`x-request-id`, B3 propagation) flow into Jaeger, while Envoy metrics are scraped by Prometheus.

## 2. Platform Capabilities & Compliance Matrix

| Capability Domain | Architecture Specification | Target Technology | Verification / Invariant Test |
| :--- | :--- | :--- | :--- |
| **Compute & Runtime** | Multi-tier microservices with relational persistence | Python (FastAPI), Node.js (Express), PostgreSQL 16 | Zero-shell distroless container runtime (`gcr.io/distroless`); non-root execution (`UID 65532`). |
| **Traffic Ingress (N-S)** | Managed API Gateway & edge routing as single cluster entry point | AWS NLB + Istio IngressGateway | Single entry point routing `/` and `/api/v1/*` paths; HTTP-to-HTTPS redirect. |
| **Zero-Trust Network (E-W)**| Transparent mTLS with cryptographic workload identity and intra-cluster restriction | Istio `PeerAuthentication` (`STRICT`) | Intra-pod TCP payload encryption; NetworkPolicy drops direct database ingress from non-backend pods. |
| **SRE Observability** | Telemetry scraping of Golden Signals, centralized logs, and distributed tracing | Prometheus, Grafana, Jaeger | Prometheus scraping Envoy stats filtering `reporter="destination"`; Jaeger visualizing distributed trace waterfalls. |
| **Resilience & Chaos** | Self-healing pod recovery and error detection via Chaos Engineering | Kubernetes Controllers, Chaos injection scripts | Pod termination (`kubectl delete pod`) and simulated 5xx spikes tracked in real time in Grafana. |

---

## 3. Technology Rationale & Design Decisions

### OpenTofu vs. Proprietary Terraform
* **Open Source Governance:** Maintained under the Linux Foundation using the permissive Mozilla Public License v2.0 (MPL-2.0), avoiding HashiCorp's Business Source License (BSL/BUSL 1.1) commercial restrictions.
* **Licensing Compliance:** Guarantees enterprise infrastructure codebases remain free from vendor lock-in or licensing disputes.
* **Drop-in Compatibility:** Direct drop-in binary compatibility (tofu init, tofu plan, tofu apply) supporting AWS providers, local CLI commands, and native S3 remote state locking (eliminating the need for DynamoDB).

### Hardened Multi-Stage Distroless Containers
* **CVE Footprint Elimination:** The build stage compiles binaries and resolves packages inside heavy builder images, while the runtime stage selectively copies only compiled executables into `gcr.io/distroless` containers.
* **Attack Surface Reduction:** Stripping package managers (`apt`, `apk`), system utilities, and interactive shells (`/bin/sh`, `/bin/bash`) eliminates the attack surface by preventing arbitrary command execution inside compromised pods.
* **Rapid Startup Performance:** Omission of OS userland components shrinks container footprint to under 65MB, speeding up CI builds and node-level container pulls.

### Istio Service Mesh & Zero-Trust Architecture
* **Non-Invasive Mutual TLS:** Secures internal pod-to-pod communications via SPIFFE identities and strict mTLS without modifying application source code.
* **Decoupled Traffic Management:** Handles circuit breaking, timeouts, connection pooling, and canary routing entirely within Envoy proxy sidecars.
* **Standardized Golden Signals:** Envoy sidecars emit uniform Prometheus metrics and distribute B3/W3C trace spans across disparate programming runtimes (Node.js and Python).

---

## 4. Repository Structure

```text
├── .github/
│   └── workflows/
│       ├── ci-apps.yaml              # Multi-stage image build, test, and scan
│       └── cd-deploy.yaml            # GitOps deployment validation
├── apps/
│   ├── backend/                      # Python FastAPI service
│   │   ├── src/                      # App logic, metrics, and DB connector
│   │   ├── Dockerfile                # Multi-stage distroless build
│   │   └── requirements.txt
│   └── frontend/                     # Node.js Express service
│       ├── src/                      # Client routing and B3 header forwarding
│       ├── Dockerfile                # Multi-stage distroless build
│       └── package.json
├── k8s/
│   ├── base/                         # Agnostic core manifests
│   │   ├── backend/                  # Deployment, Service, ConfigMap
│   │   ├── database/                 # StatefulSet, Headless Service, PVC
│   │   ├── frontend/                 # Deployment, Service, ConfigMap
│   │   └── kustomization.yaml
│   ├── mesh/                         # Istio zero-trust configuration
│   │   ├── gateway.yaml              # IngressGateway listener config
│   │   ├── network-policies.yaml     # Intra-namespace network isolation
│   │   ├── peer-authentication.yaml  # STRICT mTLS enforcement
│   │   └── virtual-services.yaml     # Layer-7 routing definitions
│   ├── observability/                # Telemetry stack manifests
│   │   ├── jaeger-deployment.yaml    # Jaeger tracing backend & UI
│   │   └── kube-prometheus-values.yaml # Prometheus/Grafana Helm values
│   └── overlays/                     # Cloud provider specific overlays
│       ├── aws/                      # AWS EBS gp3 StorageClass & NLB annotations
│       ├── azure/                    # Azure Disk / AGIC overlays
│       └── gcp/                      # GCP GKE / Managed Cert overlays
├── scripts/
│   ├── bootstrap-aws.sh              # Provisions S3 with native state locking and ECR
│   ├── teardown-aws.sh               # Decommissions cloud bootstrap assets
│   └── test-traffic.sh               # Chaos load generator and fault injector
└── opentofu/
    ├── aws/                          # EKS cluster, VPC, and IAM configuration
    ├── azure/                        # Azure landing zone (multi-cloud parity)
    └── gcp/                          # GCP landing zone (multi-cloud parity)
```

## 5. Prerequisites & Local Tooling

Ensure the following tools are installed and available on your system execution path:
* **OpenTofu:** `tofu version` (>= 1.8.x)
* **AWS CLI:** `aws --version` (>= 2.15.x)
* **Docker CLI:** `docker version` (>= 24.x)
* **Kubernetes CLI:** `kubectl version --client` (>= 1.28.x)
* **Istio CLI:** `istioctl version` (>= 1.22.x)
* **Helm:** `helm version` (>= 3.14.x)
* **curl / jq:** Command-line utilities for payload generation and telemetry parsing

### Local AWS Authentication
Before executing any infrastructure scripts, you must authenticate your local terminal with an AWS IAM User that possesses `AdministratorAccess`. **Do not use the AWS Root account.**

```bash
# Configure your local AWS profile (Requires AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY)
aws configure

# Verify your active identity
aws sts get-caller-identity
```

## 6. Step-by-Step Deployment Runbook

### Step 1: Bootstrap Cloud Storage & Registries
Execute the bootstrap automation script to initialize remote state storage (S3 bucket with native locking) and private Amazon ECR repositories:
```bash
chmod +x scripts/*.sh
./scripts/bootstrap-aws.sh
```

### Step 2: Provision Infrastructure with OpenTofu
Initialize the AWS provider modules, inspect the execution plan, and provision the VPC network and Amazon EKS cluster:
```bash
cd opentofu/aws

AWS_REGION="eu-south-2"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="tofu-state-cloudnative-${ACCOUNT_ID}-${AWS_REGION}"

tofu init \
  -backend-config="bucket=${BUCKET_NAME}" \
  -backend-config="region=${AWS_REGION}"

tofu apply

# Authenticate local kubectl context with the newly provisioned Amazon EKS cluster
aws eks update-kubeconfig --region eu-south-2 --name prod-cloud-native-eks
kubectl get nodes
cd ../..
```

### Step 3: Build & Push Hardened Container Images
Log in to Amazon ECR, build the multi-stage distroless containers directly with your release tags, and push them to your private registry:
```bash
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION="eu-south-2"
ECR_URL="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

# 1. Log Docker into the private Amazon ECR registry
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$ECR_URL"

# 2. Build Backend image directly with the ECR target tag
docker build -t "${ECR_URL}/backend-app:v1.0.0" apps/backend

# 3. Build Frontend image directly with the ECR target tag
docker build -t "${ECR_URL}/frontend-app:v1.0.0" apps/frontend

# 4. Push both images to Amazon ECR
docker push "${ECR_URL}/backend-app:v1.0.0"
docker push "${ECR_URL}/frontend-app:v1.0.0"
```

### Step 4: Install Istio Service Mesh
Deploy the Istio control plane using the default production profile and label the workload namespace for automatic Envoy sidecar injection:
```bash
istioctl install --set profile=default -y
kubectl label namespace default istio-injection=enabled --overwrite
```

### Step 5: Deploy Application Workloads & Zero-Trust Mesh
Apply the core base workloads via Kustomize (PostgreSQL StatefulSet, Backend, Frontend deployments) followed by Istio routing and security configurations:
```bash
# Deploy Database, Backend, and Frontend workloads using Kustomize
kubectl apply -k k8s/base/

# Apply Zero-Trust Mesh configurations (Strict mTLS, Ingress Gateway, Network Policies)
kubectl apply -f k8s/mesh/

# Verify rollout status across all deployments
kubectl rollout status deployment/frontend --timeout=120s
kubectl rollout status deployment/backend --timeout=120s
kubectl rollout status statefulset/postgres-db --timeout=120s
```

### Step 6: Deploy Observability Stack
Deploy the Prometheus/Grafana stack via Helm and configure the Jaeger tracing backend for capturing distributed spans:
```bash
helm repo add prometheus-community [https://prometheus-community.github.io/helm-charts](https://prometheus-community.github.io/helm-charts)
helm repo update

helm install prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  -f k8s/observability/kube-prometheus-values.yaml

kubectl apply -f k8s/observability/jaeger-deployment.yaml
```

---

## 7. Observability & SRE Golden Signals

### Local Telemetry Dashboard Access
Forward local ports to inspect Prometheus metrics, Grafana dashboards, and Jaeger traces directly:
```bash
# Access Grafana Dashboards (Default credentials: admin / immune)
kubectl port-forward -n monitoring svc/prometheus-stack-grafana 3000:80

# Access Jaeger Distributed Tracing UI
kubectl port-forward -n monitoring svc/jaeger-query 16686:16686
```

### Google SRE Golden Signal PromQL Queries
The golden rule for Istio metrics collection is to always filter by `reporter="destination"`. Istio records telemetry on both the client sidecar (`reporter="source"`) and the server sidecar (`reporter="destination"`). Omitting this label causes duplicate request counts.

* **Traffic (Rate - Requests Per Second):**
  ```promql
  sum(rate(istio_requests_total{reporter="destination", destination_service_name="backend"}[5m]))
  ```
  *Calculates the per-second rate of incoming requests over a 5-minute window for the target backend service.*

* **Errors (Ratio of HTTP 5xx Failures):**
  ```promql
  (
    sum(rate(istio_requests_total{reporter="destination", destination_service_name="backend", response_code=~"5.*"}[5m]))
    or
    vector(0)
  )
  /
  sum(rate(istio_requests_total{reporter="destination", destination_service_name="backend"}[5m]))
  ```
  *Calculates the proportion of 5xx server errors divided by total traffic. The `or vector(0)` operator prevents the expression from returning `NaN` / `No Data` when the service is healthy and zero errors exist.*

* **Latency (Percentile 95 - p95):**
  ```promql
  histogram_quantile(
    0.95,
    sum(rate(istio_request_duration_milliseconds_bucket{reporter="destination", destination_service_name="backend"}[5m])) by (le)
  )
  ```
  *Calculates the 95th percentile latency in milliseconds across aggregated histogram bucket boundaries (`by (le)`).*

* **Canary Latency Comparison:**
  ```promql
  histogram_quantile(
    0.95,
    sum(rate(istio_request_duration_milliseconds_bucket{reporter="destination", destination_service_name="backend"}[5m])) by (le, destination_version)
  )
  ```
  *Emits side-by-side time series comparing the p95 latency profile of canary deployments across active versions.*

### Distributed Context Propagation
To preserve distributed trace continuity inside Jaeger, the Express frontend extracts incoming tracing headers and forwards them down to the FastAPI backend:
* `x-request-id`: Edge UUID used for end-to-end log correlation.
* `x-b3-traceid`: Root transaction identity across the entire microservice call tree.
* `x-b3-spanid`: Unique identifier for the immediate child execution segment.
* `x-b3-parentspanid`: Identifier of the calling span for hierarchical waterfall reconstruction.
* `x-b3-sampled`: Proxy sampling flag determining span persistence.

---

## 8. Chaos Engineering & Resilience Testing

The platform validates autonomous recovery and observability detection under simulated failure:

### Resilience Scenario 1: Pod Drop & Autonomous Self-Healing
1. Generate sustained background traffic through the Ingress Gateway using a curl burst loop:
   ```bash
   kubectl run burst --rm -i --restart=Never --image=curlimages/curl -n default -- \
     sh -c 'for i in $(seq 1 300); do curl -s -o /dev/null http://frontend-service:3000/api/data; done'
   ```
2. In a separate terminal, abruptly delete an active backend pod to trigger a runtime failure:
   ```bash
   kubectl delete pod -l app=backend --now
   ```
3. Observe real-time recovery:
   * The Kubernetes control plane detects the divergence between actual state and desired state, immediately spinning up a replacement pod.
   * Grafana records a temporary error spike and latency variance before returning to baseline.
   * Jaeger flags dropped spans with `503 Service Unavailable` before routing re-stabilizes.

### Resilience Scenario 2: Network Policy Isolation Invariant
Execute an unauthorized lateral connection test from an arbitrary container directly to the PostgreSQL database:
```bash
# Attempt direct TCP connection bypassing the backend microservice
kubectl run lateral-attack --rm -i --restart=Never --image=busybox -- nc -zv -w 3 postgres-db 5432
```
*Expected Result:* The connection times out. The Kubernetes `NetworkPolicy` drops the packets, confirming that zero-trust database ingress isolation is active.

---

## 9. Decommissioning & Teardown

To avoid unnecessary cloud consumption costs, destroy all cloud resources in reverse order:

```bash
# 1. Decommission EKS cluster and VPC infrastructure
cd opentofu/aws
tofu destroy -auto-approve
cd ../..

# 2. Delete ECR repositories and S3 state storage
./scripts/teardown-aws.sh
```

## 10. Troubleshooting

**Docker Login Error (Linux/Fedora): `pass not initialized`** 
If you encounter a credential store error when piping the AWS STS token to `docker login` on Linux (as in [Step 3: Build & Push Hardened Container Images](#step-3-build--push-hardened-container-images)), it is likely because Docker defaults to using `pass` (a password manager) which may not be initialized with a GPG key on your local machine.

You can temporarily bypass this credential helper by backing up your Docker config before authenticating:
```bash
mv ~/.docker/config.json ~/.docker/config.json.backup
# Retry the AWS ECR login command