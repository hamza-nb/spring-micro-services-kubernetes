# Microservices Full Code

A production-ready microservices application built with Spring Boot and Spring Cloud, deployable via Docker Compose (local development) or Kubernetes (production).

## Architecture Overview

```
                          ┌─────────────────┐
                          │   API Gateway   │
                          │   Port: 8222    │
                          └────────┬────────┘
                                   │
          ┌─────────┬──────────────┼──────────────┬──────────────┐
          │         │              │               │              │
    ┌─────┴──┐ ┌────┴───┐   ┌─────┴──┐     ┌─────┴──┐ ┌─────────┴───┐
    │Customer│ │Product │   │ Order  │     │Payment │ │Notification │
    │  8090  │ │  8050  │   │  8070  │     │  8060  │ │    8040     │
    └────────┘ └────────┘   └───┬────┘     └────┬───┘ └──────┬──────┘
                                │  Kafka         │            │
                                └────────────────┘            │
                                      │  topics               │
                                      └────────────────────────┘

Supporting: Config Server (8888) → Discovery/Eureka (8761) → Zipkin (9411) → MailDev (1080/1025)
```

### Communication Patterns

- **Synchronous**: OpenFeign HTTP clients (Order → Customer, Order → Payment, Order → Product)
- **Asynchronous**: Apache Kafka (Order → `order-confirmation`, Payment → `payment-confirmation`)
- **Event-Driven Flow**: Order created → Payment processed → Notification emails sent

## Services

| Service | Port | Description |
|---------|------|-------------|
| Config Server | 8888 | Centralized configuration for all services |
| Discovery (Eureka) | 8761 | Service registry and discovery |
| API Gateway | 8222 | Single entry point, routes all client requests |
| Customer | 8090 | Customer registration and management |
| Product | 8050 | Product catalog |
| Order | 8070 | Order processing, Kafka producer |
| Payment | 8060 | Payment processing, Kafka producer |
| Notification | 8040 | Email notifications, Kafka consumer |

## Tech Stack

| Category | Technology |
|----------|-----------|
| Language | Java 17 |
| Framework | Spring Boot 3.x |
| Service Mesh | Spring Cloud (Config, Eureka, Gateway, OpenFeign) |
| Database | PostgreSQL (one schema per service) |
| Migrations | Flyway (Product), Hibernate DDL auto (others) |
| Messaging | Apache Kafka (KRaft mode) |
| Tracing | Micrometer + Zipkin |
| Email | Spring Mail + Thymeleaf + MailDev |
| Build | Maven 3.9 |
| Containers | Docker (multi-stage builds), Kubernetes |

## API Endpoints

All requests go through the API Gateway at `http://localhost:8222`.

| Method | Path | Service |
|--------|------|---------|
| POST/GET | `/api/v1/customers/**` | Customer |
| GET | `/api/v1/products` | Product |
| POST/GET | `/api/v1/orders/**` | Order |
| GET | `/api/v1/order-lines/**` | Order |
| POST/GET | `/api/v1/payments/**` | Payment |

## Local Development (Docker Compose)

### Prerequisites

- Docker & Docker Compose
- Java 17+
- Maven 3.9+

### 1. Start Infrastructure

```bash
docker-compose up -d
```

This starts PostgreSQL, Kafka, Zipkin, and MailDev.

### 2. Build All Services

```bash
for svc in config-server discovery gateway customer product order payment notification; do
  (cd services/$svc && ./mvnw clean package -DskipTests)
done
```

### 3. Start Services (in order)

```bash
# 1. Config Server (must start first)
java -jar services/config-server/target/config-server-*.jar

# 2. Discovery Service
java -jar services/discovery/target/discovery-*.jar

# 3. All other services (any order)
java -jar services/gateway/target/gateway-*.jar
java -jar services/customer/target/customer-*.jar
java -jar services/product/target/product-*.jar
java -jar services/order/target/order-*.jar
java -jar services/payment/target/payment-*.jar
java -jar services/notification/target/notification-*.jar
```

### Local Infrastructure Ports

| Service | Port | Notes |
|---------|------|-------|
| PostgreSQL | 5432 | User: `hamza`, Password: `hamza` |
| Kafka | 9092 | KRaft mode |
| Zipkin UI | 9411 | Distributed tracing dashboard |
| MailDev Web | 1080 | View sent emails |
| MailDev SMTP | 1025 | SMTP server |

Databases (auto-created on startup): `customer`, `product`, `order`, `payment`, `notification`

## Kubernetes Deployment

### Prerequisites

- A running Kubernetes cluster (minikube, EKS, GKE, etc.)
- `kubectl` configured
- Docker images built and pushed to your registry

### 1. Deploy Infrastructure

```bash
kubectl apply -f k8-postgres.yaml
kubectl apply -f k8-kafka.yaml
kubectl apply -f k8-zipkin.yaml
kubectl apply -f k8-mailer-dev.yaml
kubectl apply -f k8-kafka-ui.yaml
```

### 2. Create Config Server ConfigMap

```bash
kubectl create configmap config-server-configurations \
  --from-file=services/config-server/src/main/resources/configurations
```

### 3. Verify Infrastructure

```bash
kubectl get pods
kubectl get svc
```

### 4. Deploy Microservices

Apply your service manifests (Config Server first, then Discovery, then the rest).

### Kubernetes Internal Service Names

| Resource | Kubernetes DNS |
|----------|---------------|
| PostgreSQL | `postgresql:5432` |
| Kafka | `kafka:9092` |
| Zipkin | `zipkin:9411` |
| Mail server | `mailer-dev:1025` |
| Kafka UI | `kafka-ui:8002` |

### Port Forwarding (for local access)

```bash
kubectl port-forward svc/zipkin 9411:9411
kubectl port-forward svc/kafka-ui 8002:8002
kubectl port-forward svc/mailer-dev 1080:1080
```

## Kafka Topics

| Topic | Producer | Consumer Group |
|-------|----------|---------------|
| `order-confirmation` | Order Service | `orderGroup` (Notification) |
| `payment-confirmation` | Payment Service | `paymentGroup` (Notification) |

## Architecture Patterns

- **API Gateway** — single ingress, Eureka-based load balancing (`lb://` routes)
- **Config Server** — externalized, centralized configuration
- **Service Discovery** — client-side discovery via Eureka
- **Database per Service** — isolated PostgreSQL schemas
- **Saga (informal)** — Order → Payment → Notification via Kafka events
- **Distributed Tracing** — 100% sampling with Sleuth + Zipkin

## Project Structure

```
microservices-full-code/
├── services/
│   ├── config-server/      # Spring Cloud Config Server
│   ├── discovery/          # Eureka Server
│   ├── gateway/            # Spring Cloud Gateway
│   ├── customer/           # Customer Service
│   ├── product/            # Product Service
│   ├── order/              # Order Service
│   ├── payment/            # Payment Service
│   └── notification/       # Notification Service
├── docker-compose.yml      # Local infrastructure
├── k8-kafka.yaml           # Kubernetes: Kafka
├── k8-kafka-ui.yaml        # Kubernetes: Kafka UI
├── k8-postgres.yaml        # Kubernetes: PostgreSQL
├── k8-zipkin.yaml          # Kubernetes: Zipkin
├── k8-mailer-dev.yaml      # Kubernetes: MailDev
├── diagrams/               # Architecture diagrams
└── resources/              # API docs & business requirements
```
