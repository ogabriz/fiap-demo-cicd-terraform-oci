# SolidaryTech — Hackathon Fase 5

Bem-vindo ao repositorio oficial da **SolidaryTech**.

Este monorepo contem os microsservicos que compoem a plataforma da ONG e servira como base para os desafios do Hackathon Fase 5.

O objetivo principal deste projeto e aplicar conceitos modernos de:

- SRE (Site Reliability Engineering)
- FinOps
- Multicloud (Oracle Cloud Infrastructure - OCI)
- ITSM
- Observabilidade
- Resiliencia
- Kubernetes & GitOps
- Infraestrutura como Codigo (IaC)

---

# Arquitetura dos Microsservicos

O ecossistema e composto por **3 microsservicos independentes**, desenvolvidos com tecnologias diferentes para simular um ambiente corporativo distribuido.

Toda a infraestrutura roda na **Oracle Cloud Infrastructure (OCI)**.

---

## 1. NGO Service — Cadastro de ONGs

| Item | Valor |
|---|---|
| Linguagem | Python 3.9+ |
| Framework | Flask |
| Banco de Dados | PostgreSQL (in-cluster OKE) |
| Porta Local | `8081` |

### Descricao
Responsavel pelo gerenciamento e cadastro das ONGs parceiras da plataforma.

---

## 2. Donation Service — Processamento de Doacoes

| Item | Valor |
|---|---|
| Linguagem | Go 1.21+ |
| Banco de Dados | PostgreSQL (in-cluster OKE) |
| Mensageria | OCI Queue |
| Porta Local | `8082` |

### Descricao
Este e o **Hot Path** da aplicacao.

Responsavel pelo processamento das doacoes e publicacao de eventos assincronos na **OCI Queue** para processamento posterior.

---

## 3. Volunteer Service — Gestao de Voluntarios

| Item | Valor |
|---|---|
| Linguagem | Python 3.9+ |
| Framework | Flask |
| Banco de Dados | OCI NoSQL |
| Porta Local | `8083` |

### Descricao
Gerencia o cadastro e inscricao de voluntarios interessados em apoiar as ONGs parceiras.

Utiliza armazenamento NoSQL nativo da OCI (OCI NoSQL Database) com foco em escalabilidade.

---

# Estrutura do Repositorio

```text
.
├── ngo-service/            # Python/Flask - Servico de ONGs (PostgreSQL)
├── donation-service/       # Go - Servico de Doacoes (PostgreSQL + OCI Queue)
├── volunteer-service/      # Python/Flask - Servico de Voluntarios (OCI NoSQL)
├── terraform/              # Infraestrutura como Codigo (OCI)
│   ├── modules/
│   │   ├── networking/     # VCN, Subnets, Gateways
│   │   ├── oke/            # Oracle Kubernetes Engine
│   │   ├── nosql/          # OCI NoSQL Table
│   │   ├── queue/          # OCI Queue
│   │   ├── ocir/           # Oracle Container Image Registry
│   │   └── observability/  # Prometheus, Grafana, Loki
│   ├── envs/dev.tfvars     # Configuracoes do ambiente dev
│   ├── backend.tf          # Backend OCI Object Storage
│   ├── provider.tf         # Provider OCI
│   └── main.tf             # Modulo raiz
├── k8s-infra/              # Manifests de infraestrutura K8s
├── k8s-common/             # Ingress compartilhado
├── .github/workflows/      # CI/CD pipelines
└── scripts/                # Scripts auxiliares
```

---

# Executando Localmente

Antes de realizar deploy em Kubernetes e automatizacoes CI/CD, recomenda-se validar todo o ambiente localmente.

---

# Pre-requisitos

Certifique-se de possuir os seguintes itens instalados:

- Python 3.9+
- Go 1.21+
- Docker (opcional, mas recomendado)
- PostgreSQL
- OCI CLI configurado (`~/.oci/config`)
- Credenciais OCI validas (API Key)

---

# Passo 1 — Preparacao da Infraestrutura

## PostgreSQL

Crie dois bancos de dados independentes:

### Banco `ngo_db`

Execute:

```sql
ngo-service/db/init.sql
```

### Banco `donation_db`

Execute:

```sql
donation-service/db/init.sql
```

---

## OCI NoSQL

A tabela e provisionada automaticamente pelo Terraform (`terraform/modules/nosql`).

| Configuracao | Valor |
|---|---|
| Nome da Tabela | `togglemaster_table` |
| Chave Primaria | `id` (STRING) |
| Read Units | 50 |
| Write Units | 50 |

---

## OCI Queue

A fila e provisionada automaticamente pelo Terraform (`terraform/modules/queue`).

| Configuracao | Valor |
|---|---|
| Nome da Fila | `togglemaster-queue` |
| Visibilidade | 30s |
| Timeout | 30s |
| Retencao | 7 dias |

Apos o `terraform apply`, copie os outputs:
- `queue_id` (OCID da fila)
- `queue_messages_endpoint` (endpoint para envio de mensagens)

---

# Passo 2 — Variaveis de Ambiente

Crie um arquivo `.env` dentro de cada microsservico.

---

## ngo-service/.env

```env
PORT=8081
DATABASE_URL="postgres://SEU_USUARIO:SUA_SENHA@localhost:5432/ngo_db"
```

---

## donation-service/.env

```env
PORT=8082
DATABASE_URL="postgres://SEU_USUARIO:SUA_SENHA@localhost:5432/donation_db"

OCI_QUEUE_ID="ocid1.queue.oc1.sa-saopaulo-1.EXEMPLO"
OCI_QUEUE_ENDPOINT="https://cell-1.queue.messaging.sa-saopaulo-1.oci.oraclecloud.com"
```

---

## volunteer-service/.env

```env
PORT=8083

OCI_REGION="sa-saopaulo-1"
OCI_NOSQL_COMPARTMENT_ID="ocid1.compartment.oc1..EXEMPLO"
OCI_NOSQL_TABLE_NAME="togglemaster_table"
```

---

# Passo 3 — Inicializando os Servicos

Abra **3 terminais separados**.

---

## Terminal 1 — NGO Service

```bash
cd ngo-service

pip install -r requirements.txt

gunicorn --bind 0.0.0.0:8081 app:app
```

---

## Terminal 2 — Donation Service

```bash
cd donation-service

go mod tidy

go run .
```

---

## Terminal 3 — Volunteer Service

```bash
cd volunteer-service

pip install -r requirements.txt

gunicorn --bind 0.0.0.0:8083 app:app
```

---

# Portas Locais

| Servico | URL |
|---|---|
| NGO Service | http://localhost:8081 |
| Donation Service | http://localhost:8082 |
| Volunteer Service | http://localhost:8083 |

---

# Infraestrutura OCI (Terraform)

Toda a infraestrutura e provisionada via Terraform na Oracle Cloud:

| Recurso | Modulo Terraform |
|---|---|
| VCN + Subnets + Gateways | `modules/networking` |
| Oracle Kubernetes Engine (OKE) | `modules/oke` |
| OCI NoSQL Table | `modules/nosql` |
| OCI Queue | `modules/queue` |
| Oracle Container Image Registry | `modules/ocir` |
| Prometheus + Grafana + Loki + OTel | `modules/observability` |
| PostgreSQL (in-cluster) | `k8s-infra/postgres.yaml` |
| Redis (in-cluster) | `k8s-infra/redis.yaml` |

### Deploy da Infraestrutura

```bash
cd terraform

terraform init
terraform plan -var-file=envs/dev.tfvars
terraform apply -var-file=envs/dev.tfvars
```

---

# CI/CD & GitOps

Pipelines automatizadas via GitHub Actions:

| Pipeline | Trigger | Descricao |
|---|---|---|
| `terraform-plan.yml` | Push em `terraform/**` | Terraform Plan |
| `terraform-apply.yml` | Manual | Terraform Apply (requer aprovacao) |
| `terraform-destroy.yml` | Manual | Terraform Destroy |
| `ngo-service-deploy.yml` | Push em `ngo-service/**` | Build + Deploy NGO Service |
| `donation-service-deploy.yml` | Push em `donation-service/**` | Build + Deploy Donation Service |
| `volunteer-service-deploy.yml` | Push em `volunteer-service/**` | Build + Deploy Volunteer Service |

Cada pipeline inclui:
- Lint e testes unitarios
- Scan de seguranca (SAST + SCA via Bandit/Gosec + Trivy)
- Build de imagem Docker (ARM64)
- Push para OCIR (Oracle Container Image Registry)
- Deploy no OKE (Oracle Kubernetes Engine)

---

# Observabilidade

Instrumentacao dos servicos utilizando:

- OpenTelemetry
- Distributed Tracing
- Metricas
- Logs estruturados

Ferramentas provisionadas via Terraform:

- Grafana
- Prometheus
- Loki
- New Relic (via OTLP exporter)

---

# SRE & Resiliencia

Definir:

- SLIs
- SLOs
- Error Budgets
- Estrategias de Disaster Recovery
- Alertas inteligentes
- Health Checks
- Auto Healing

## Foco Principal

O `donation-service` deve ser tratado como componente critico da plataforma.

---

# GitHub Secrets Necessarios

| Secret | Descricao |
|---|---|
| `OCI_TENANCY_OCID` | OCID do Tenancy |
| `OCI_USER_OCID` | OCID do usuario OCI |
| `OCI_FINGERPRINT` | Fingerprint da API Key |
| `OCI_PRIVATE_KEY` | Chave privada OCI (base64) |
| `OCI_REGION` | Regiao OCI (ex: sa-saopaulo-1) |
| `OCI_COMPARTMENT_ID` | OCID do Compartment |

| `OCI_AUTH_TOKEN` | Auth Token para OCIR |
| `OCI_TENANCY_NAMESPACE` | Namespace do Tenancy |
| `OCI_USERNAME` | Username OCI para OCIR |
| `OCI_OKE_CLUSTER_ID` | OCID do cluster OKE |

---

# Tecnologias Envolvidas

- Python / Flask
- Go
- PostgreSQL
- OCI NoSQL
- OCI Queue
- Docker
- Kubernetes (OKE)
- Terraform
- GitHub Actions
- ArgoCD
- OpenTelemetry
- Prometheus / Grafana / Loki
- New Relic

---

# Contribuicao

Este projeto foi criado exclusivamente para fins educacionais e execucao do Hackathon Fase 5.

Sinta-se livre para evoluir a arquitetura, melhorar a observabilidade e implementar boas praticas de engenharia de plataforma.

---

# Boa sorte!

Bom Hackathon!

Faca a diferenca com a **SolidaryTech**
