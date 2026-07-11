# Production RabbitMQ High Availability & Disaster Recovery Platform

## 1. Overview

This document describes the architecture, security model, deployment strategy, and disaster recovery design for a production-grade RabbitMQ messaging platform.

The platform consists of:

* Primary RabbitMQ cluster hosted on Oracle Cloud (1 VM K3s instance)
* Disaster Recovery RabbitMQ cluster hosted on Tencent Cloud (1 VM K3s instance)
* Kubernetes-based deployment using K3s
* Quorum queues for high availability
* Asynchronous replication between sites
* Infrastructure automation using Terraform and GitOps
* Enterprise security controls including TLS, Vault, network isolation, and WireGuard VPN

The objective is to build a messaging platform capable of surviving:

* RabbitMQ pod/process failures
* Node/VM failures (via Disaster Recovery site promotion)
* Storage failures
* Primary site outages
* Network interruptions

---

# 2. Architecture Overview

```
                         GitHub Enterprise

              Terraform + GitHub Actions + ArgoCD

                               |
                               |
                  GitOps Deployment Pipeline

                               |
        =================================================

            Kubernetes-Native WireGuard VPN (Public UDP)
                 Mutual TLS Communication

        =================================================

             Primary Site                 Disaster Recovery Site

          Oracle Cloud (VM-1)              Tencent Cloud (VM-1)

              |                                |

          K3s Cluster                     K3s Cluster

              |                                |

     RabbitMQ Cluster                RabbitMQ Cluster
     (3 Pods on 1 VM)                (3 Pods on 1 VM)

       Pod-0                           Pod-0
       Pod-1                           Pod-1
       Pod-2                           Pod-2

              |                                |

     Cloud-Native / Local Storage     Cloud-Native / Local Storage
     (No Longhorn Double-Replication) (No Longhorn Double-Replication)


              |
              |
        RabbitMQ Shovel Replication (over WireGuard)

              |
              |
        DR Synchronization
```

---

# 3. Design Principles

## High Availability

The platform follows these principles:

* No single RabbitMQ pod should cause downtime
* No single VM failure should cause permanent data loss (handled via DR site promotion)
* No single disk/volume failure should cause data loss (quorum queue Raft consensus replicates messages across multiple pods)
* Production traffic must never depend on a single cloud provider

---

## Data Integrity

The platform guarantees:

* Persistent messages
* Publisher confirmations
* Consumer acknowledgements
* Quorum-based replication
* Idempotent message processing
* Controlled failover procedures

---

## Security First

Security controls include:

* Private RabbitMQ messaging interfaces
* Mutual TLS authentication
* Secret management through Vault
* Least privilege access
* Kubernetes network isolation
* Publicly exposed WireGuard VPN with cryptographic peer verification
* Certificate rotation
* Audit logging

---

# 4. Infrastructure Design

## Primary Environment

Provider:

Oracle Cloud

Purpose:

Production messaging cluster

Components:

```
1 x VM Node (K3s Control Plane + Worker)
    |
    +-- WireGuard Pod (vpn Namespace)
    |
    +-- RabbitMQ Operator
    |
    +-- RabbitMQ Cluster (rabbitmq Namespace)
        |-- rabbitmq-server-0
        |-- rabbitmq-server-1
        |-- rabbitmq-server-2
```

VM Resource Sizing:

* CPU: 8 vCPUs (Allocating 2 vCPUs per RabbitMQ pod + 2 vCPUs for K3s system overhead)
* RAM: 16 GB+ RAM (Allocating 4 GB per RabbitMQ pod + 4 GB for K3s and VPN overhead)
* Storage: High-performance OCI Block Volume or Local NVMe SSD

---

## Disaster Recovery Environment

Provider:

Tencent Cloud

Purpose:

Warm standby disaster recovery environment

Components:

```
1 x VM Node (K3s Control Plane + Worker)
    |
    +-- WireGuard Pod (vpn Namespace)
    |
    +-- RabbitMQ Operator
    |
    +-- RabbitMQ Cluster (rabbitmq Namespace)
        |-- rabbitmq-server-0
        |-- rabbitmq-server-1
        |-- rabbitmq-server-2
```

The DR environment remains synchronized but does not actively serve production traffic. VM resources match the primary environment.

---

# 5. Kubernetes Platform

## Distribution

K3s Kubernetes

Reason:

* Lightweight and highly efficient for single-VM deployments
* Production capable
* Easy cluster bootstrapping and lifecycle management

---

## Storage Layer

Technology:

Cloud-Native CSI / Local Path (Longhorn Removed)

Purpose:

Provides low-latency, high-throughput persistent volumes directly connected to the host VM storage.

Why Longhorn Was Removed (Optimization):
1. **Double Replication Overhead**: Quorum queues utilize the Raft consensus algorithm, which replicates message data at the application layer across the 3 RabbitMQ pods. Replicating the underlying storage layer using Longhorn introduces a "double replication" tax, which leads to massive write amplification, disk I/O bottlenecking, and increased network latency.
2. **Single-Node Topology**: Since each cluster is deployed on a single VM, distributing replicas across multiple virtual disk volumes on the same physical VM via Longhorn provides no physical fault tolerance while adding significant CPU and memory overhead.

Recommended Setup:
- **Oracle Cloud**: OCI Block Storage (via OCI Block Volume CSI Driver) or K3s local-path-provisioner.
- **Tencent Cloud**: Tencent Cloud CBS (via Tencent CBS CSI Driver) or K3s local-path-provisioner.
- Each RabbitMQ pod claims a dedicated Persistent Volume Claim (PVC) bound to an independent directory on the VM's local storage.

Example:

```
RabbitMQ Pod 0     RabbitMQ Pod 1     RabbitMQ Pod 2
      |                  |                  |
   PVC-0              PVC-1              PVC-2
      |                  |                  |
Local Path SSD     Local Path SSD     Local Path SSD
(Host VM Disk)     (Host VM Disk)     (Host VM Disk)
```

---

# 6. RabbitMQ Architecture

## Deployment Method

RabbitMQ Cluster Operator

Not a standalone Helm deployment.

Architecture:

```
Kubernetes

     |

RabbitMQ Operator

     |

RabbitMQ Custom Resource

     |

RabbitMQ Nodes
```

## Single-VM Pod Scheduling Configuration

Since each environment runs on a single VM:
* The 3-node RabbitMQ cluster is deployed as 3 pods (`rabbitmq-server-0`, `-1`, `-2`) scheduled on the single VM node.
* To prevent concurrent pod disruptions during host upgrades or maintenance, we configure a **Pod Disruption Budget (PDB)** allowing a maximum of 1 unavailable pod (`maxUnavailable: 1`). This ensures at least 2 replicas remain active to maintain the Raft quorum.
* To prevent resource starvation on the host VM, each RabbitMQ pod is configured with explicit resource requests and limits (Recommended: CPU request/limit at 2 vCPU, Memory request/limit at 4GB).
* Node topology spread constraints and pod anti-affinity are documented for future scale-out: when additional VMs are added, these constraints should be enabled to ensure RabbitMQ pods are never co-located on the same physical VM.

---

# 7. Queue Configuration

## Queue Type

All production queues use:

```
Quorum Queues
```

Reasons:

* Raft consensus
* Data safety
* Automatic leader election
* Better failure handling

Avoid:

* Classic mirrored queues
* Non-durable queues
* Temporary production queues

---

# 8. Message Reliability

## Publisher Side

Required:

* Publisher confirms enabled
* Persistent messages
* Mandatory publishing

Flow:

```
Application

    |

Publish Message

    |

RabbitMQ

    |

Confirm Received

    |

Application continues
```

---

## Consumer Side

Required:

* Manual acknowledgements
* Retry handling
* Dead Letter Queues

Flow:

```
Consumer

    |

Process Message

    |

Success

    |

ACK


Failure

    |

Retry Queue

    |

Dead Letter Queue
```

---

# 9. Disaster Recovery Strategy

## Replication Model

The platform uses asynchronous replication.

Architecture:

```
Primary RabbitMQ

        |

        |

RabbitMQ Shovel

        |

        |

DR RabbitMQ
```

Reason:

A single RabbitMQ cluster should not span multiple clouds because:

* WAN latency affects quorum consensus
* Network partitions can cause availability problems
* Failure domains become coupled

---

# 10. Recovery Objectives

Target objectives:

## Recovery Point Objective (RPO)

Approximate:

Seconds

Depends on replication delay.

## Recovery Time Objective (RTO)

Target:

5-15 minutes

---

# 11. Disaster Recovery Procedure

Scenario:

Primary Oracle Cloud environment unavailable.

Steps:

1. Verify primary outage
2. Stop or isolate failed environment
3. Promote Tencent DR cluster
4. Update application endpoints
5. Validate queues
6. Resume application traffic
7. Monitor message flow
8. Restore primary environment
9. Reverse synchronization
10. Perform failback

---

# 12. Network Security & VPN

## Site-to-Site VPN (Kubernetes-Native WireGuard)

To securely connect the Oracle Cloud (Primary) and Tencent Cloud (DR) single-VM clusters, a point-to-point WireGuard VPN is deployed inside the Kubernetes clusters.

### Public Endpoint Exposure
- The WireGuard service is exposed on port `51820/UDP` mapping to each VM's public IP using `hostPort` or a Kubernetes service of type `NodePort`.
- **Security Design**: Since WireGuard is cryptographically silent (responding only to packets that are signed by recognized peer keys), the public UDP port is highly secure and scan-resistant out of the box, without requiring static IP whitelisting at the firewall layer.

### Subnet Configurations (Non-Overlapping)
Subnets are configured to prevent overlapping IP address space and allow direct routing through the WireGuard VPN:

| Environment | Host/VM Subnet | Pod CIDR | Service CIDR | WireGuard Transit IP |
| :--- | :--- | :--- | :--- | :--- |
| **Oracle Cloud (Primary)** | `10.0.0.0/16` | `10.244.0.0/16` | `10.96.0.0/16` | `192.168.250.1/30` |
| **Tencent Cloud (DR)** | `10.1.0.0/16` | `10.245.0.0/16` | `10.97.0.0/16` | `192.168.250.2/30` |

### Pod Configuration and Routing
- The WireGuard router runs in an isolated `vpn` namespace on both clusters as a single-pod Deployment with kernel privileges (`cap_add: [NET_ADMIN]`) and IP forwarding enabled (`sysctl net.ipv4.ip_forward=1`).
- Routing is defined in the WireGuard interface configuration (`AllowedIPs`):
  - **Oracle Peer config**:
    ```ini
    [Peer]
    PublicKey = <Tencent_WireGuard_Public_Key>
    Endpoint = <Tencent_VM_Public_IP>:51820
    AllowedIPs = 10.1.0.0/16, 10.245.0.0/16, 10.97.0.0/16, 192.168.250.2/32
    PersistentKeepalive = 25
    ```
  - **Tencent Peer config**:
    ```ini
    [Peer]
    PublicKey = <Oracle_WireGuard_Public_Key>
    Endpoint = <Oracle_VM_Public_IP>:51820
    AllowedIPs = 10.0.0.0/16, 10.244.0.0/16, 10.96.0.0/16, 192.168.250.1/32
    PersistentKeepalive = 25
    ```
- A static route is added to the host VM's routing table (or distributed within the K3s CNI routing table) to direct traffic bound for the peer's subnets through the WireGuard interface/pod.
- **DNS Stub-Domains**: CoreDNS on both clusters is updated to forward resolution requests for the other site's internal domains (e.g., forwarding `*.dr.local` to the Tencent cluster DNS service at `10.97.0.10`), enabling Shovel synchronization to use stable DNS names.

---

# 13. Network Security Controls

## Rules
* RabbitMQ ports are private only.
* No direct internet access allowed for RabbitMQ nodes.
* Access is restricted strictly to the local network or through the WireGuard VPN.

## Allowed Ports
* `5671` (AMQP over TLS)
* `15671` (Management UI over TLS)
* `15692` (Prometheus Metrics Scrape)
* `51820/UDP` (WireGuard VPN Tunnel port - publicly exposed)

## Kubernetes Network Policies (`NetworkPolicy`)
Strict network policies are implemented in the `rabbitmq` namespace:
- **Ingress Policy**: Only allow traffic to RabbitMQ ports (`5671`, `15671`, `15692`) from:
  - Authorized application namespaces (Publishers & Consumers).
  - The `vpn` namespace (enabling Shovel traffic from the peer cluster).
  - The `monitoring` namespace (allowing Prometheus to scrape metrics).
- **Egress Policy**: Block all outgoing internet connections from RabbitMQ pods, allowing egress only to DNS (`kube-system` namespace) and the peer VPN endpoints.

---

# 14. TLS Architecture

All communication uses encryption.

```
Application

     |

Mutual TLS

     |

RabbitMQ
```

Certificates managed by:

* cert-manager
* Vault PKI

---

# 15. Secret Management

Technology:

Hashicorp Vault

Stores:

* RabbitMQ credentials
* TLS private keys
* Application secrets
* Service credentials

Architecture:

```
Vault

 |

Kubernetes CSI Driver

 |

Application Pods
```

---

# 16. Authentication and Authorization

Recommended users:

```
publisher-user

consumer-user

monitoring-user

backup-user

administrator
```

Principles:

* Least privilege
* No shared accounts
* Credential rotation
* Auditing

---

# 17. Monitoring and Observability

Stack:

## Metrics

Prometheus

## Dashboards

Grafana

## Logs

Loki

## Alerts

Alertmanager

## Tracing

OpenTelemetry

Monitor:

* Queue depth
* Consumer lag
* Publish latency
* Node health
* Memory alarms
* Disk usage
* Replication status
* Certificate expiry

---

# 18. Definition Backup Strategy

To ensure recovery of the RabbitMQ schema, users, queues, and exchanges in the event of catastrophic cluster failure:
* A daily Kubernetes `CronJob` runs within the `rabbitmq` namespace.
* The job uses `rabbitmqadmin` or requests the management API endpoint `/api/definitions` to export a JSON payload of the entire cluster configuration.
* The exported definition file is encrypted and uploaded to secure cloud object storage (OCI Object Storage / Tencent COS) with a 30-day lifecycle retention policy.

---

# 19. Failure Testing

The platform must regularly test:

## RabbitMQ Node Failure

Test:

```
Delete rabbitmq-0 pod
```

Expected:

* Leader election
* Continued message processing

---

## Storage Failure

Test:

* Temporarily delete or corrupt local volume path or simulate cloud block volume detach.

Expected:

* Kubernetes restarts the failed RabbitMQ pod.
* The pod re-binds to its persistent storage volume and catches up with the cluster's Raft consensus logs.

---

## Network Partition

Test:

* Block site communication (e.g. stop the WireGuard pod or block UDP 51820).

Expected:

* Cluster remains consistent locally.
* Primary cluster continues processing messages.
* DR cluster detects loss of Shovel connection and logs errors, resuming sync immediately once WireGuard re-establishes connection.

---

## Full Site Failure

Test:

* Disable Oracle VM instance.

Expected:

* DR promotion of Tencent site.

---

# 20. CI/CD and GitOps

Deployment flow:

```
Developer

   |

GitHub Enterprise

   |

GitHub Actions

   |

Terraform

   |

ArgoCD

   |

Kubernetes

   |

RabbitMQ Platform
```

No manual production changes.

---

# 21. Repository Structure

```
rabbitmq-platform/

├── terraform/
│
├── kubernetes/
│
├── rabbitmq/
│
├── vault/
│
├── monitoring/
│
├── networking/
│
└── disaster-recovery/
```

---

# 22. Production Readiness Checklist

## Infrastructure

[ ] Kubernetes cluster deployed (1 VM per site)

[ ] Persistent volume storage (CSI / local path) configured (Longhorn removed)

[ ] Network isolation and WireGuard VPN configured

## RabbitMQ

[ ] Three-node cluster (3 pods on 1 VM)

[ ] Quorum queues enabled

[ ] Pod Disruption Budget (PDB) configured

[ ] TLS enabled

[ ] Publisher confirms enabled

## Security

[ ] Vault integrated

[ ] Certificate rotation configured

[ ] Network policies enabled

[ ] WireGuard VPN publicly exposed on UDP 51820 with cryptographic peer verification

[ ] Audit logging enabled

## DR

[ ] Secondary cluster deployed

[ ] Replication tested

[ ] Failover procedure documented

[ ] Recovery drills completed

## Operations

[ ] Monitoring configured

[ ] Alerts configured

[ ] Definition backup CronJob scheduled and tested

[ ] Incident procedures documented

---

# Final Goal

The completed platform should demonstrate:

* Distributed systems design
* Kubernetes operations
* Messaging reliability engineering
* Disaster recovery engineering
* Cloud architecture
* Security engineering
* Production operations maturity

The success criteria is:

"Destroy infrastructure intentionally and prove that messages survive."
