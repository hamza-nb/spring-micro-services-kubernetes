# Kubernetes Manifests Report
## E-Commerce Microservices Platform

---

## Table of Contents

1. [Overview](#overview)
2. [Namespace](#1-namespace--k8-namespaceyaml)
3. [Infrastructure](#infrastructure)
   - [PostgreSQL](#2-postgresql--k8-postgresyaml)
   - [Kafka](#3-kafka--k8-kafkayaml)
   - [Zipkin](#4-zipkin--k8-zipkinyaml)
   - [MailDev](#5-maildev--k8-mailer-devyaml)
   - [Kafka UI](#6-kafka-ui--k8-kafka-uiyaml)
4. [Platform Services](#platform-services)
   - [Config Server](#7-config-server)
   - [Discovery Service](#8-discovery-service)
5. [Business Microservices](#business-microservices)
   - [Customer Service](#9-customer-service)
   - [Gateway Service](#10-gateway-service)
   - [Order Service](#11-order-service)
   - [Payment Service](#12-payment-service)
   - [Product Service](#13-product-service)
   - [Notification Service](#14-notification-service)
6. [Resource Summary](#resource-summary)
7. [Network & Port Map](#network--port-map)
8. [Config Architecture](#config-architecture)

---

## Overview

All resources live in a single Kubernetes **namespace** called `e-commerce`. The platform follows a layered boot order:

```
Namespace
  └── Infrastructure (PostgreSQL, Kafka, Zipkin, MailDev, Kafka UI)
        └── Config Server  (Spring Cloud Config — holds all service configs)
              └── Discovery Service  (Eureka — service registry)
                    └── Business Microservices (customer, gateway, order, payment, product, notification)
```

Each business microservice mounts a lightweight `ConfigMap` (its own `application.yml`) that tells Spring Boot to pull the real config from the Config Server on startup.

---

## Infrastructure

### 1. Namespace — `k8-namespace.yaml`

```
Kind: Namespace
Name: e-commerce
```

Creates the logical boundary that isolates all platform resources. Every other manifest targets `namespace: e-commerce`.

---

### 2. PostgreSQL — `k8-postgres.yaml`

**Resources defined:** `PersistentVolumeClaim`, `ConfigMap` (config), `ConfigMap` (init script), `Secret`, `Deployment`, `Service`

#### PersistentVolumeClaim — `postgres-pvc`
| Field | Value |
|---|---|
| Access mode | `ReadWriteOnce` (single node read/write) |
| Storage | `1Gi` |

Provides durable disk storage so database data survives pod restarts.

#### ConfigMap — `postgres-config`
| Key | Value |
|---|---|
| `POSTGRES_USER` | `hamza` |
| `PGDATA` | `/data/postgres` |

Injects non-sensitive env vars into the PostgreSQL container.

#### ConfigMap — `postgres-init-script`
Contains an `init.sh` shell script mounted into `/docker-entrypoint-initdb.d/`. PostgreSQL automatically executes scripts in that directory on first start. It creates the following databases if they don't already exist:

- `customer`
- `notification`
- `payment`
- `product`
- `order`

#### Secret — `postgres-secret`
| Key | Value |
|---|---|
| `POSTGRES_PASSWORD` | `hamza` (stored as Opaque secret) |

Keeps the password out of plain ConfigMaps. In production this should be managed by a secrets manager (e.g. Vault, Sealed Secrets).

#### Deployment — `postgresql`
| Field | Value |
|---|---|
| Image | `postgres:16` |
| Replicas | `1` |
| Port | `5432` |
| CPU request/limit | `100m` / `500m` |
| Memory request/limit | `256Mi` / `512Mi` |

- Mounts the PVC at `/data/postgres` for data persistence.
- Mounts the init script ConfigMap at `/docker-entrypoint-initdb.d` (executable, mode `0755`).
- **Readiness probe:** `pg_isready -U hamza` — starts at 10s, every 5s.
- **Liveness probe:** same command — starts at 30s, every 10s.

#### Service — `postgresql`
| Field | Value |
|---|---|
| Type | `ClusterIP` (internal only) |
| Port | `5432 → 5432` |

Other pods connect via DNS name `postgresql:5432`.

---

### 3. Kafka — `k8-kafka.yaml`

**Resources defined:** `PersistentVolumeClaim`, `Deployment`, `Service`

#### PersistentVolumeClaim — `kafka-pvc`
| Field | Value |
|---|---|
| Access mode | `ReadWriteOnce` |
| Storage | `1Gi` |

Persists Kafka log segments across restarts.

#### Deployment — `kafka`
| Field | Value |
|---|---|
| Image | `apache/kafka:3.7.0` |
| Replicas | `1` |
| Ports | `9092` (broker), `9093` (controller) |
| CPU request/limit | `200m` / `1000m` |
| Memory request/limit | `512Mi` / `1Gi` |

Runs Kafka in **KRaft mode** (no ZooKeeper). Key environment variables:

| Variable | Value | Purpose |
|---|---|---|
| `KAFKA_NODE_ID` | `1` | Unique broker/controller ID |
| `KAFKA_PROCESS_ROLES` | `broker,controller` | Combined role (KRaft) |
| `KAFKA_LISTENERS` | `PLAINTEXT://0.0.0.0:9092, CONTROLLER://0.0.0.0:9093` | Bind addresses |
| `KAFKA_ADVERTISED_LISTENERS` | `PLAINTEXT://kafka:9092` | Address advertised to clients inside the cluster |
| `KAFKA_CONTROLLER_QUORUM_VOTERS` | `1@localhost:9093` | Single-node quorum |
| `KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR` | `1` | Single replica (dev) |
| `CLUSTER_ID` | `MkU3OEVBNTcwNTJENDM2Qk` | Fixed cluster ID for KRaft |
| `KAFKA_LOG_DIRS` | `/var/kafka-logs` | Persisted via PVC |

- **Readiness probe:** TCP on `9092` — starts at 30s, every 10s.
- **Liveness probe:** TCP on `9092` — starts at 60s, every 15s.

#### Service — `kafka`
| Field | Value |
|---|---|
| Type | `ClusterIP` |
| Ports | `9092` (broker), `9093` (controller) |

Microservices reach Kafka at `kafka:9092`.

---

### 4. Zipkin — `k8-zipkin.yaml`

**Resources defined:** `Deployment`, `Service`

#### Deployment — `zipkin`
| Field | Value |
|---|---|
| Image | `openzipkin/zipkin:3` |
| Replicas | `1` |
| Port | `9411` |
| CPU request/limit | `100m` / `500m` |
| Memory request/limit | `256Mi` / `512Mi` |

Provides distributed tracing. All microservices send spans to Zipkin (configured via the `management.zipkin.tracing.endpoint` in the shared `application.yml` ConfigMap).

- **Readiness probe:** `GET /health` on `9411` — starts at 15s.
- **Liveness probe:** same — starts at 30s.

#### Service — `zipkin`
| Field | Value |
|---|---|
| Type | `ClusterIP` |
| Port | `9411 → 9411` |

Services send traces to `http://zipkin:9411/api/v2/spans`.

---

### 5. MailDev — `k8-mailer-dev.yaml`

**Resources defined:** `Deployment`, `Service` (UI — LoadBalancer), `Service` (SMTP — ClusterIP)

#### Deployment — `mailer-dev`
| Field | Value |
|---|---|
| Image | `maildev/maildev:2` |
| Replicas | `1` |
| Ports | `1080` (web UI), `1025` (SMTP) |
| CPU request/limit | `50m` / `200m` |
| Memory request/limit | `64Mi` / `128Mi` |

A local SMTP trap for development. Catches all outgoing emails and displays them in a web UI — no real emails are sent.

- **Readiness probe:** `GET /healthz` on `1080`.

#### Service — `mailer-dev-ui` (LoadBalancer)
| Field | Value |
|---|---|
| Type | `LoadBalancer` (externally accessible) |
| Port | `1080 → 1080` |

Exposes the MailDev web UI so developers can view captured emails in a browser.

#### Service — `mailer-dev` (ClusterIP)
| Field | Value |
|---|---|
| Type | `ClusterIP` (internal only) |
| Port | `1025 → 1025` |

The notification service sends email via `mailer-dev:1025` (SMTP).

---

### 6. Kafka UI — `k8-kafka-ui.yaml`

**Resources defined:** `Deployment`, `Service`

#### Deployment — `kafka-ui`
| Field | Value |
|---|---|
| Image | `provectuslabs/kafka-ui:latest` |
| Replicas | `1` |
| Port | `8080` |
| CPU request/limit | `100m` / `500m` |
| Memory request/limit | `256Mi` / `512Mi` |

A web dashboard for inspecting Kafka topics, consumer groups, and messages.

| Env Variable | Value |
|---|---|
| `KAFKA_CLUSTERS_0_NAME` | `local` |
| `KAFKA_CLUSTERS_0_BOOTSTRAPSERVERS` | `kafka:9092` |
| `DYNAMIC_CONFIG_ENABLED` | `true` |

- **Readiness probe:** `GET /actuator/health` — starts at 30s.
- **Liveness probe:** `GET /actuator/health` — starts at 60s.

#### Service — `kafka-ui`
| Field | Value |
|---|---|
| Type | `LoadBalancer` (externally accessible) |
| External port | `8002` |
| Target port | `8080` |

Accessible from outside the cluster on port `8002`.

---

## Platform Services

### 7. Config Server

**Files:**
- `services/config-server/k8-configmap-config-server-root-configuration.yaml`
- `services/config-server/k8-configmap-config-server-configurations.yaml`
- `services/config-server/k8-config-service.yaml`

#### ConfigMap — `config-server-root-configuration`

Contains the config server's own `application.yml`. Key settings:

```yaml
server:
  port: 8888
spring:
  profiles:
    active: native          # reads config from the local filesystem
  cloud:
    config:
      server:
        native:
          search-locations: file:/config/configurations/
```

The `native` profile means Spring Cloud Config Server serves config files mounted from disk (the `configurations` ConfigMap below), not from a Git repo.

#### ConfigMap — `config-server-configurations`

This is the **central config store** for the entire platform. It contains one YAML file per service:

| File | Service | Port | Notes |
|---|---|---|---|
| `application.yml` | **All services (shared)** | — | Eureka URL, Zipkin endpoint, tracing probability = 100% |
| `customer-service.yml` | Customer | `8090` | PostgreSQL `customer` DB, JPA update |
| `discovery-service.yml` | Discovery | `8761` | Standalone Eureka (no self-registration) |
| `gateway-service.yml` | Gateway | `8222` | Spring Cloud Gateway routes to all 5 services via Eureka `lb://` URIs |
| `notification-service.yml` | Notification | `8040` | PostgreSQL `notification` DB, Kafka consumer, SMTP config |
| `order-service.yml` | Order | `8070` | PostgreSQL `order` DB, Kafka producer, URLs for customer/payment/product via gateway |
| `payment-service.yml` | Payment | `8060` | PostgreSQL `payment` DB, Kafka producer |
| `product-service.yml` | Product | `8050` | PostgreSQL `product` DB, Flyway migrations |

#### Deployment — `config-service-dep`
| Field | Value |
|---|---|
| Image | `config-server` (local) |
| `imagePullPolicy` | `IfNotPresent` |
| Port | `8888` |
| CPU request/limit | `100m` / `500m` |
| Memory request/limit | `256Mi` / `512Mi` |

**Volume mounts:**
- `/config/application.yml` — from `config-server-root-configuration` ConfigMap (single file via `subPath`)
- `/config/configurations/` — from `config-server-configurations` ConfigMap (entire directory of per-service YAMLs)

The env var `SPRING_CONFIG_ADDITIONAL_LOCATION=file:/config/` makes Spring Boot pick up the mounted config.

- **Readiness probe:** `GET /actuator/health` on `8888` — starts at 30s.
- **Liveness probe:** same — starts at 60s.

#### Service — `config-service-svc`
| Field | Value |
|---|---|
| Type | `ClusterIP` |
| Port | `8888 → 8888` |

All other services reach it at `http://config-service-svc:8888`.

---

### 8. Discovery Service

**File:** `services/discovery/k8-discovery-service.yaml`

#### ConfigMap — `discovery-server-configuration`

Bootstrap config that tells the discovery service to import from the Config Server:

```yaml
spring:
  config:
    import: optional:configserver:http://config-service-svc:8888
  application:
    name: discovery-service
```

The `discovery-service.yml` in the Config Server's ConfigMap provides the full Eureka configuration.

#### Deployment — `discovery-service-dep`
| Field | Value |
|---|---|
| Image | `discovery-server` (local) |
| `imagePullPolicy` | `IfNotPresent` |
| Port | `8761` |
| CPU request/limit | `100m` / `500m` |
| Memory request/limit | `256Mi` / `512Mi` |

Mounts its `application.yml` from the ConfigMap above. Same `SPRING_CONFIG_ADDITIONAL_LOCATION` pattern as the Config Server.

- **Readiness probe:** `GET /actuator/health` on `8761` — starts at 30s.
- **Liveness probe:** same — starts at 60s.

#### Service — `discovery-service-svc`
| Field | Value |
|---|---|
| Type | `ClusterIP` |
| Port | `8761 → 8761` |

All microservices register with Eureka at `http://discovery-service-svc:8761/eureka`.

---

## Business Microservices

All six business microservices follow the exact same structural pattern:

1. **ConfigMap** — bootstrap `application.yml` pointing to the Config Server.
2. **Service** — exposes the pod on its port.
3. **Deployment** — runs the Spring Boot app, mounts the ConfigMap, uses health probes.

The table below summarizes the differences:

| Service | File | Image | Port | Service Type | DB | Kafka Role |
|---|---|---|---|---|---|---|
| Customer | `k8-customer-service.yaml` | `customer-service` | `8090` | ClusterIP | `customer` | — |
| Gateway | `k8-gateway-service.yaml` | `gateway-service` | `8222` | **LoadBalancer** | — | — |
| Order | `k8-order-service.yaml` | `order-service` | `8070` | ClusterIP | `order` | Producer |
| Payment | `k8-payment-service.yaml` | `payment-service` | `8060` | ClusterIP | `payment` | Producer |
| Product | `k8-product-service.yaml` | `product-service` | `8050` | ClusterIP | `product` | — |
| Notification | `k8-notification-service.yaml` | `notification-service` | `8040` | ClusterIP | `notification` | Consumer |

### Shared Deployment Config (all business services)
| Field | Value |
|---|---|
| Replicas | `1` |
| `imagePullPolicy` | `IfNotPresent` |
| CPU request/limit | `100m` / `500m` |
| Memory request/limit | `256Mi` / `512Mi` |
| Readiness probe | `GET /actuator/health` — starts at 60s, every 10s |
| Liveness probe | `GET /actuator/health` — starts at 90s, every 15s |
| Config mount | `/config/application.yml` via `subPath` from own ConfigMap |
| Config env | `SPRING_CONFIG_ADDITIONAL_LOCATION=file:/config/` |

The higher `initialDelaySeconds` (60s readiness, 90s liveness) compared to infrastructure services accounts for the time Spring Boot needs to fetch config from the Config Server, register with Eureka, and complete application context startup.

---

### 9. Customer Service

- **ConfigMap name:** `customer-service-configuration`
- **Spring app name:** `customer-service`
- **Port:** `8090` (ClusterIP)
- **Database:** `customer` on PostgreSQL, JPA `ddl-auto: update`
- **DNS:** `customer-service-svc:8090`

---

### 10. Gateway Service

- **ConfigMap name:** `gateway-service-configuration`
- **Spring app name:** `gateway-service`
- **Port:** `8222` (**LoadBalancer** — externally accessible entry point)
- **Routes (from Config Server):**

| Route ID | URI | Path |
|---|---|---|
| `customer-service` | `lb://CUSTOMER-SERVICE` | `/api/v1/customers/**` |
| `order-service` | `lb://ORDER-SERVICE` | `/api/v1/orders/**` |
| `order-lines-service` | `lb://ORDER-SERVICE` | `/api/v1/order-lines/**` |
| `product-service` | `lb://PRODUCT-SERVICE` | `/api/v1/products/**` |
| `payment-service` | `lb://PAYMENT-SERVICE` | `/api/v1/payments/**` |

All external traffic enters through this single LoadBalancer. Service-to-service calls from `order-service` also route through the gateway.

---

### 11. Order Service

- **ConfigMap name:** `order-service-configuration`
- **Spring app name:** `order-service`
- **Port:** `8070` (ClusterIP)
- **Database:** `order` on PostgreSQL, JPA `ddl-auto: create`
- **Kafka:** Producer — sends `orderConfirmation` events to `kafka:9092`
- **Upstream calls via gateway:**
  - `http://gateway-service-svc:8222/api/v1/customers`
  - `http://gateway-service-svc:8222/api/v1/payments`
  - `http://gateway-service-svc:8222/api/v1/products`

---

### 12. Payment Service

- **ConfigMap name:** `payment-service-configuration`
- **Spring app name:** `payment-service`
- **Port:** `8060` (ClusterIP)
- **Database:** `payment` on PostgreSQL, JPA `ddl-auto: create`
- **Kafka:** Producer — sends `paymentConfirmation` events to `kafka:9092`

---

### 13. Product Service

- **ConfigMap name:** `product-service-configuration`
- **Spring app name:** `product-service`
- **Port:** `8050` (ClusterIP)
- **Database:** `product` on PostgreSQL, JPA `ddl-auto: validate` + **Flyway** migrations
- **Note:** Uses Flyway for schema management (`baseline-on-migrate: true`), unlike other services which use Hibernate DDL auto.

---

### 14. Notification Service

- **ConfigMap name:** `notification-service-configuration`
- **Spring app name:** `notification-service`
- **Port:** `8040` (ClusterIP)
- **Database:** `notification` on PostgreSQL, JPA `ddl-auto: update`
- **Kafka:** Consumer — listens to `orderConfirmation` and `paymentConfirmation` events
  - Consumer groups: `paymentGroup`, `orderGroup`
  - `auto-offset-reset: earliest`
- **Email:** Sends via SMTP to `mailer-dev:1025` (MailDev trap)

---

## Resource Summary

| Resource | Count |
|---|---|
| Namespace | 1 |
| Deployments | 11 |
| Services | 13 |
| ConfigMaps | 10 |
| PersistentVolumeClaims | 2 |
| Secrets | 1 |

---

## Network & Port Map

| Service | DNS Name | Port | External? |
|---|---|---|---|
| PostgreSQL | `postgresql` | `5432` | No |
| Kafka (broker) | `kafka` | `9092` | No |
| Kafka (controller) | `kafka` | `9093` | No |
| Zipkin | `zipkin` | `9411` | No |
| MailDev SMTP | `mailer-dev` | `1025` | No |
| MailDev UI | `mailer-dev-ui` | `1080` | **Yes (LoadBalancer)** |
| Kafka UI | `kafka-ui` | `8002` (→ 8080) | **Yes (LoadBalancer)** |
| Config Server | `config-service-svc` | `8888` | No |
| Discovery (Eureka) | `discovery-service-svc` | `8761` | No |
| Customer | `customer-service-svc` | `8090` | No |
| **Gateway** | `gateway-service-svc` | `8222` | **Yes (LoadBalancer)** |
| Order | `order-service-svc` | `8070` | No |
| Payment | `payment-service-svc` | `8060` | No |
| Product | `product-service-svc` | `8050` | No |
| Notification | `notification-service-svc` | `8040` | No |

**External entry points (LoadBalancer):**
- `:8222` — API Gateway (main client-facing entry point)
- `:1080` — MailDev UI (dev email viewer)
- `:8002` — Kafka UI (Kafka dashboard)

---

## Config Architecture

```
┌─────────────────────────────────────────────────────────────┐
│              ConfigMap: config-server-configurations         │
│  (one YAML file per service, mounted as a directory)        │
│                                                             │
│  application.yml          ← shared by ALL services         │
│  customer-service.yml                                       │
│  discovery-service.yml                                      │
│  gateway-service.yml                                        │
│  notification-service.yml                                   │
│  order-service.yml                                          │
│  payment-service.yml                                        │
│  product-service.yml                                        │
└────────────────────────────┬────────────────────────────────┘
                             │ mounted at /config/configurations/
                             ▼
                   ┌──────────────────┐
                   │  Config Server   │  :8888
                   │  (native mode)   │
                   └────────┬─────────┘
                            │ HTTP pull on startup
          ┌─────────────────┼─────────────────┐
          ▼                 ▼                 ▼
   discovery-svc     customer-svc      gateway-svc
   order-svc         payment-svc       product-svc
                  notification-svc
```

Each microservice carries only a minimal bootstrap `ConfigMap` (its `spring.application.name` and the Config Server URL). All real configuration — database URLs, Kafka settings, Eureka addresses, port numbers — lives centrally in the Config Server's ConfigMap and is fetched at runtime.
