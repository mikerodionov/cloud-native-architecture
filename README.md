# Cloud-Native Microservices Platform: Zero-Trust Mesh & SRE Observability

An enterprise-grade, cloud-native reference architecture engineered to demonstrate modern application lifecycle patterns: containerization, zero-trust traffic control, GitOps-ready orchestration, and distributed observability.

---

## Architectural Pillars & Design Decisions

| Pillar | Technology Choice | Technical Justification |
| :--- | :--- | :--- |
| **Microservices & Persistence** | Python (FastAPI), Node.js (Express), PostgreSQL | Simulates an asynchronous transactional topology (Public Gateway $\rightarrow$ Presentation Layer $\rightarrow$ Worker/Business Logic $\rightarrow$ Relational State). |
| **Containerization** | Docker Multi-Stage Builds, Google Container Tools (Distroless Base) | Isolates build-time toolchains from runtime; removes shells, package managers, and OS binaries to minimize CVE attack surfaces and artifact footprint. |
| **Orchestration** | Kubernetes (EKS / GKE / AKS) | Declarative resource management, self-healing deployments, dynamic pod scheduling, and horizontal auto-scaling. |
| **North-South Traffic** | Istio IngressGateway / API Gateway | Single edge entry point handling TLS termination, unified URL routing, external rate limiting, and header sanitization. |
| **East-West Traffic** | Istio Service Mesh (Envoy Sidecars) | Enforces transparent mutual TLS (mTLS) with SPIFFE (Secure Production Identity Framework for Everyone) workload identity, granular L7 authorization policies, and intra-pod traffic isolation. |
| **Observability** | Prometheus, Grafana, Jaeger, Fluent Bit / Cloud Logging | Full telemetry collection covering Google SRE Golden Signals (Latency, Traffic, Errors, Saturation), unified logs, and distributed trace propagation. |

---

## Request Lifecycle Architecture

```text
                                  NORTH - SOUTH TRAFFIC
                                            │
                             [ Public Internet Request ]
                                            │
                                            ▼
                           ┌─────────────────────────────────┐
                           │   Cloud Provider Load Balancer  │
                           └────────────────┬────────────────┘
                                            │
                                            ▼
                           ┌─────────────────────────────────┐
                           │    Istio Ingress Gateway        │ (Edge Routing & TLS)
                           └────────────────┬────────────────┘
────────────────────────────────────────────┼────────────────────────────────────────────
                                            │ EAST - WEST TRAFFIC (Strict mTLS)
                                            ▼
                           ┌─────────────────────────────────┐
                           │          Frontend Pod           │
                           │  ┌───────────┐   ┌───────────┐  │
                           │  │   Envoy   │───│  Express  │  │
                           │  │  Sidecar  │   │   (App)   │  │
                           │  └───────────┘   └───────────┘  │
                           └────────────────┬────────────────┘
                                            │ (Encrypted mTLS tunnel)
                                            ▼
                           ┌─────────────────────────────────┐
                           │           Backend Pod           │
                           │  ┌───────────┐   ┌───────────┐  │
                           │  │   Envoy   │───│  FastAPI  │  │
                           │  │  Sidecar  │   │   (App)   │  │
                           │  └───────────┘   └───────────┘  │
                           └────────────────┬────────────────┘
                                            │
                                            ▼
                           ┌─────────────────────────────────┐
                           │      Stateful Database Pod      │
                           │  ┌───────────┐   ┌───────────┐  │
                           │  │   Envoy   │───│PostgreSQL │  │
                           │  │  Sidecar  │   │ (Storage) │  │
                           │  └───────────┘   └─────┬─────┘  │
                           └────────────────────────┼────────┘
                                                    ▼
                                         [ Persistent Volume ]