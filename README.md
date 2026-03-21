ToggleMaster é uma plataforma de Feature Flags construída com microsserviços, provisionada na Oracle Cloud Infrastructure (OCI) via Terraform, com pipelines CI/CD automatizados no GitHub Actions.

📑 Índice
Visão Geral da Arquitetura
Diagrama de Arquitetura
Estrutura do Projeto
Microsserviços
Infraestrutura Terraform (OCI)
Pipelines Separadas — GitHub Actions
Fluxo Visual das Pipelines
Configuração do GitHub Environment
Testes Locais
Segurança
1. Visão Geral da Arquitetura
O sistema ToggleMaster é composto por 5 microsserviços independentes que se comunicam via HTTP e fila de mensagens:

Serviço	Linguagem	Porta	Função
auth-service	Go	8001	Gerencia e valida chaves de API (API Keys)
flag-service	Python (Flask)	8002	CRUD de Feature Flags (PostgreSQL)
targeting-service	Python (Flask)	8003	CRUD de Regras de Segmentação (PostgreSQL)
evaluation-service	Go	8004	Avalia se uma flag está ativa para um usuário (Redis Cache + OCI Queue)
analytics-service	Python	8005	Consome eventos da OCI Queue e persiste no OCI NoSQL
Fluxo de uma avaliação de flag
Cliente (SDK/App)
      │
      ▼
evaluation-service  ──── Redis Cache ────► [HIT] → retorna decisão
      │                                    [MISS] ↓
      ├──── flag-service      (busca flag)
      └──── targeting-service (busca regra)
      │
      ▼
 Lógica de Decisão (PERCENTAGE bucket / enabled)
      │
      ├──► Resposta HTTP (true/false)
      └──► OCI Queue → analytics-service → OCI NoSQL
2. Diagrama de Arquitetura
Infraestrutura OCI
┌──────────────────────────────────────────────────────────────────────┐
│                          OCI Tenancy                                 │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐    │
│  │                 VCN ToggleMaster (10.0.0.0/16)               │    │
│  │                                                              │    │
│  │  ┌──────────────────────────────┐  ┌─────────────────────┐  │    │
│  │  │      Subnets Públicas        │  │    Subnet DB        │  │    │
│  │  │  Workers:   10.0.3.0/24      │  │    10.0.5.0/24      │  │    │
│  │  │  OKE Nodes: 10.0.10.0/24    │  │                     │  │    │
│  │  │  LB:        10.0.20.0/24    │  │  ┌────────────────┐ │  │    │
│  │  │                             │  │  │  Postgres (VM) │ │  │    │
│  │  │  ┌───────────────────────┐  │  │  └────────────────┘ │  │    │
│  │  │  │     OKE Cluster       │  │  │  ┌────────────────┐ │  │    │
│  │  │  │   (Kubernetes v1.34)  │  │  │  │  Redis (VM)    │ │  │    │
│  │  │  │  ┌─────────────────┐  │  │  │  └────────────────┘ │  │    │
│  │  │  │  │  auth-service   │  │  │  └─────────────────────┘  │    │
│  │  │  │  │  flag-service   │  │  │                            │    │
│  │  │  │  │ target-service  │  │  │                            │    │
│  │  │  │  │  eval-service   │  │  │                            │    │
│  │  │  │  │ analytics-svc   │  │  │                            │    │
│  │  │  │  │    ArgoCD       │  │  │                            │    │
│  │  │  │  └─────────────────┘  │  │                            │    │
│  │  │  └───────────────────────┘  │                            │    │
│  │  └──────────────────────────────┘                           │    │
│  └──────────────────────────────────────────────────────────────┘    │
│                                                                      │
│   ┌──────────────┐   ┌──────────────┐   ┌──────────────────────┐    │
│   │  OCI Queue   │   │  OCI NoSQL   │   │    OCIR (Registry)   │    │
│   │  (SQS-like)  │   │(DynamoDB-like│   │  5 repos de imagens  │    │
│   └──────────────┘   └──────────────┘   └──────────────────────┘    │
└──────────────────────────────────────────────────────────────────────┘
Subnets e CIDRs
Subnet	CIDR	Tipo	Uso
workers	10.0.3.0/24	Pública	Nodes OKE (worker pool)
db	10.0.5.0/24	Pública*	PostgreSQL + Redis VMs
oke-nodes	10.0.10.0/24	Pública	OKE nodes (pool principal)
oke-lb	10.0.20.0/24	Pública	Load Balancers do OKE
*Recomendado mover para subnet privada em ambientes de produção.

3. Estrutura do Projeto
📁 fiap-demo-cicd-terraform-oci/
│
├── 📁 .github/
│   └── 📁 workflows/
│       ├── terraform-plan.yml          # Pipeline 1: Plan (auto no push)
│       ├── terraform-apply.yml         # Pipeline 2: Apply (manual + aprovação)
│       ├── terraform-destroy.yml       # Pipeline 3: Destroy (manual + aprovação)
│       ├── auth-service-deploy.yml     # Pipeline 4: Deploy auth-service
│       ├── flag-service-deploy.yml     # Pipeline 5: Deploy flag-service
│       ├── targeting-service-deploy.yml# Pipeline 6: Deploy targeting-service
│       ├── evaluation-service-deploy.yml# Pipeline 7: Deploy evaluation-service
│       └── analytics-service-deploy.yml # Pipeline 8: Deploy analytics-service
│
├── 📁 terraform/
│   ├── backend.tf                      # Backend OCI Object Storage
│   ├── provider.tf                     # Providers: OCI, Kubernetes, Helm
│   ├── main.tf                         # Módulo raiz (orquestra todos os módulos)
│   ├── variables.tf                    # Variáveis sensíveis (via GitHub Secrets)
│   └── 📁 envs/
│       └── dev.tfvars                  # Configuração do ambiente dev (commitado)
│   └── 📁 modules/
│       ├── 📁 networking/              # VCN, Subnets, Gateways, Route Tables
│       ├── 📁 oke/                     # Cluster Kubernetes + Node Pool + ArgoCD
│       ├── 📁 postgres/                # VM com PostgreSQL (cloud-init)
│       ├── 📁 redis/                   # VM com Redis (cloud-init)
│       ├── 📁 nosql/                   # Tabela OCI NoSQL (analytics)
│       ├── 📁 queue/                   # OCI Queue (eventos de avaliação)
│       └── 📁 ocir/                    # Container Image Registry (5 repos)
│
├── 📁 auth-service/                    # Go: Gerencia API Keys
│   ├── main.go
│   ├── Dockerfile
│   ├── go.mod / go.sum
│   └── 📁 k8s/                        # Manifests Kubernetes
│
├── 📁 flag-service/                    # Python/Flask: CRUD de Feature Flags
│   ├── app.py
│   ├── requirements.txt
│   ├── Dockerfile
│   └── 📁 k8s/
│
├── 📁 targeting-service/               # Python/Flask: Regras de Segmentação
│   ├── app.py
│   ├── requirements.txt
│   ├── Dockerfile
│   └── 📁 k8s/
│
├── 📁 evaluation-service/              # Go: Motor de Avaliação de Flags
│   ├── main.go / evaluator.go / handlers.go / types.go
│   ├── Dockerfile
│   ├── go.mod / go.sum
│   └── 📁 k8s/
│
├── 📁 analytics-service/               # Python: Consumidor de eventos (Queue → NoSQL)
│   ├── app.py
│   ├── requirements.txt
│   ├── Dockerfile
│   └── 📁 k8s/
│
├── 📁 k8s-common/
│   └── ingress.yaml                    # NGINX Ingress compartilhado
│
├── 📁 scripts/
│   └── test-services.sh                # Script para testes manuais
│
├── ToggleMaster_Postman_Collection.json # Collection Postman para testes de API
├── README.md
├── HANDS-ON.md
├── BACKEND-OCI.md
└── DOCUMENTATION.md                    # Este arquivo
4. Microsserviços
4.1 auth-service (Go)
Responsabilidade: Geração e validação de API Keys.

Endpoints:

Método	Rota	Auth	Descrição
GET	/health	—	Health check básico
GET	/health/db	—	Health check do PostgreSQL
GET	/validate	Bearer API_KEY	Valida se a chave é ativa
POST	/admin/keys	Bearer MASTER_KEY	Cria nova API Key
Variáveis de ambiente:

Variável	Descrição
DATABASE_URL	Connection string PostgreSQL
MASTER_KEY	Chave mestra para criar novas API Keys
PORT	Porta do servidor (default: 8001)
Funções principais:

Função	Descrição
generateAPIKey()	Gera uma chave aleatória com prefixo tm_key_ usando 32 bytes criptográficos
hashKey(key)	Gera SHA-256 da chave para armazenamento seguro no banco
extractBearerToken(r)	Extrai o token do header Authorization: Bearer <token>
initDatabase(db)	Cria a tabela api_keys se não existir
validateHandler	Verifica se a chave existe e está ativa; atualiza last_used_at
adminKeysHandler(masterKey)	Cria nova chave com validação do MASTER_KEY
4.2 flag-service (Python/Flask)
Responsabilidade: CRUD de Feature Flags no PostgreSQL.

Endpoints:

Método	Rota	Descrição
GET	/health	Health check
POST	/flags	Cria nova flag
GET	/flags	Lista todas as flags
GET	/flags/<name>	Busca flag por nome
PUT	/flags/<name>	Atualiza flag (description, is_enabled)
DELETE	/flags/<name>	Remove flag
Funções principais:

Função	Descrição
init_db()	Cria tabela flags e índice por nome se não existirem
require_auth(f)	Decorator que valida a API Key via chamada ao auth-service
create_flag()	Insere nova flag no banco; retorna 409 em duplicata
update_flag(name)	Atualiza dinamicamente os campos enviados
delete_flag(name)	Remove flag; retorna 404 se não encontrada
4.3 targeting-service (Python/Flask)
Responsabilidade: CRUD de Regras de Segmentação (armazenadas como JSONB).

Endpoints:

Método	Rota	Descrição
GET	/health	Health check
POST	/rules	Cria nova regra de segmentação
GET	/rules/<flag_name>	Busca regra pelo nome da flag
PUT	/rules/<flag_name>	Atualiza regra (rules JSONB, is_enabled)
DELETE	/rules/<flag_name>	Remove regra
Exemplo de regra JSONB (PERCENTAGE):

{
  "flag_name": "minha-feature",
  "is_enabled": true,
  "rules": {
    "type": "PERCENTAGE",
    "value": 50
  }
}
4.4 evaluation-service (Go)
Responsabilidade: Avalia se uma feature flag está ativa para um usuário específico, com cache Redis e envio de eventos de analytics.

Endpoints:

Método	Rota	Descrição
GET	/health	Health check (inclui status do Redis)
GET	/evaluate?user_id=X&flag_name=Y	Retorna true/false para o par usuário/flag
Lógica de avaliação:

Busca CombinedFlagInfo (flag + regra) do Redis com TTL de 30s (flagInfoCacheTTL)
Se MISS, busca concorrentemente do flag-service e targeting-service
Se flag desabilitada → false
Se sem regra → true (100% dos usuários)
Se regra PERCENTAGE → calcula bucket determinístico via SHA-1 do userID + flagName
Envia evento de avaliação para OCI Queue (assíncrono)
Funções principais:

Função	Descrição
getDecision(userID, flagName)	Orquestra busca de dados e execução da lógica de avaliação
getCombinedFlagInfo(flagName)	Busca flag + regra do Redis (cache) ou dos serviços
fetchFromServices(flagName)	Busca concorrente de flag-service e targeting-service
runEvaluationLogic(flagInfo, userID)	Executa a lógica PERCENTAGE e retorna decisão booleana
getDeterministicBucket(input)	Gera bucket [0–99] via SHA-1 para rollout determinístico
sendEvaluationEvent(...)	Envia evento para OCI Queue (goroutine assíncrona)
4.5 analytics-service (Python)
Responsabilidade: Consome eventos de avaliação da OCI Queue e persiste no OCI NoSQL.

Funções principais:

Função	Descrição
queue_worker_loop()	Loop infinito que faz long-polling na OCI Queue
process_message(message)	Parseia mensagem JSON, salva no NoSQL e deleta da fila
start_worker()	Inicia queue_worker_loop como thread daemon em background
5. Infraestrutura Terraform (OCI)
5.1 Módulos
Módulo	Arquivo	Recursos criados
networking	modules/networking/	VCN, 4 Subnets, Internet Gateway, Route Table, Security List
oke	modules/oke/	Cluster OKE, Node Pool (VM.Standard.A1.Flex), ArgoCD
postgres	modules/postgres/	VM Oracle Linux ARM + PostgreSQL via cloud-init
redis	modules/redis/	VM Oracle Linux ARM + Redis via cloud-init
nosql	modules/nosql/	Tabela OCI NoSQL para analytics
queue	modules/queue/	OCI Queue para eventos de avaliação
ocir	modules/ocir/	5 repositórios no OCI Container Registry
5.2 Variáveis de configuração
Variáveis sensíveis (passadas via TF_VAR_* nos secrets do GitHub):

Variável	Tipo	Descrição
tenancy_ocid	string	OCID do tenancy OCI
user_ocid	string	OCID do usuário OCI para autenticação via API
fingerprint	string	Fingerprint da API Key OCI
region	string	Região OCI (ex: sa-vinhedo-1)
compartment_id	string	OCID do compartment onde os recursos serão criados
ssh_public_key	string	Chave SSH pública para acesso às VMs
image_id	string	OCID da imagem OCI para instâncias compute
availability_domain	string	AD onde os recursos serão alocados
oke_image	string	OCID da imagem para os nodes do OKE
Variáveis de projeto (terraform/envs/dev.tfvars — commitado no repositório):

project_name = "fiap-demo-oci"
environment  = "dev"

# Networking
vcn_cidr    = "10.0.0.0/16"
subnet_cidr = "10.0.1.0/24"

# OKE
oke_kubernetes_version = "v1.34.1"
oke_node_shape         = "VM.Standard.A1.Flex"
oke_node_count         = 2

# NoSQL (FREE)
nosql_read_units  = 50
nosql_write_units = 50
nosql_storage_gb  = 1
6. Pipelines Separadas — GitHub Actions
O projeto possui 8 pipelines independentes organizadas em dois grupos:

Grupo 1: Pipelines de Infraestrutura (Terraform)
Pipeline 1 — terraform-plan.yml (Automática)
Trigger: Push na branch main em arquivos terraform/** + manual
Jobs: terraform-plan
Etapas: Checkout → Setup Terraform → Configure OCI Credentials → Debug Fingerprint → Install OCI CLI → terraform init → terraform validate → terraform plan
Ambiente: Nenhum (sem proteção/aprovação)
Objetivo: Validar e revisar mudanças antes do apply
Pipeline 2 — terraform-apply.yml (Manual + Aprovação)
Trigger: Manual (workflow_dispatch)
Jobs: terraform-apply
Etapas: Checkout → Setup → Credentials → terraform init → terraform plan -out=tfplan → terraform apply -auto-approve tfplan → terraform output → Upload Outputs
Ambiente: dev (requer aprovação de reviewer configurado)
Objetivo: Provisionar/atualizar infraestrutura na OCI
Pipeline 3 — terraform-destroy.yml (Manual + Aprovação)
Trigger: Manual (workflow_dispatch)
Jobs: terraform-destroy
Etapas: Checkout → Setup → Credentials → terraform init → terraform destroy -target=module.oke
Ambiente: dev (requer aprovação)
Objetivo: Remover recursos da OCI (destruição controlada)
Grupo 2: Pipelines de Microsserviços (Service Deploy)
Cada microsserviço possui sua própria pipeline com 4 jobs encadeados:

Pipeline 4-8 — <service>-deploy.yml
Estrutura comum de cada pipeline de serviço:

Job 1: lint-and-test        Job 2: security-scan
   └─ Checkout                 └─ Checkout
   └─ Setup Language            └─ SAST (Gosec/Bandit)
   └─ Install deps              └─ SCA (Trivy - filesystem)
   └─ Lint
   └─ Unit Tests
           │                            │
           └────────────┬───────────────┘
                        ▼
               Job 3: build-and-push
                  └─ Checkout
                  └─ QEMU (ARM64)
                  └─ Docker Buildx
                  └─ Login OCIR
                  └─ Build image
                  └─ Trivy (container scan)
                  └─ Push image + :latest tag
                        │
                        ▼
               Job 4: update-gitops
                  └─ Checkout
                  └─ Atualiza deployment.yaml com novo SHA
                  └─ git commit + push (ArgoCD detecta e faz deploy)
Triggers por serviço:

Pipeline	Arquivo monitorado	Linguagem
auth-service-deploy.yml	auth-service/**	Go
flag-service-deploy.yml	flag-service/**	Python
targeting-service-deploy.yml	targeting-service/**	Python
evaluation-service-deploy.yml	evaluation-service/**	Go
analytics-service-deploy.yml	analytics-service/**	Python
7. Fluxo Visual das Pipelines
Fluxo de Infraestrutura
Developer
   │
   ├─── git push main (terraform/**)
   │           │
   │           ▼
   │    ┌─────────────────┐
   │    │  Pipeline Plan  │  ← Automático
   │    │  terraform plan │
   │    └────────┬────────┘
   │             │ ✅ Revisar output do plan
   │             ▼
   └─── GitHub Actions → Terraform Apply → Run workflow
               │
        ┌──────▼──────┐
        │ ⏸️ Aprovação  │ ← Environment: dev
        │  Reviewer   │   (Settings → Environments → dev)
        └──────┬──────┘
               │ 👍 Aprovado
               ▼
        ┌─────────────┐
        │ terraform   │
        │   apply     │ ← Recursos criados na OCI!
        └─────────────┘

   Quando necessário:
   GitHub Actions → Terraform Destroy → Run workflow
               │
        ┌──────▼──────┐
        │ ⏸️ Aprovação  │ ← Environment: dev (mesma proteção)
        └──────┬──────┘
               │ 👍 Aprovado
               ▼
        ┌─────────────┐
        │ terraform   │
        │  destroy    │ ← Recursos removidos da OCI
        └─────────────┘
Fluxo de Deploy de Microsserviço
Developer
   │
   ├─── git push main (auth-service/**)
   │
   ▼
┌────────────────────────────────────────────────────────┐
│               Pipeline: auth-service-deploy             │
│                                                        │
│  ┌──────────────┐    ┌──────────────┐                  │
│  │ lint-and-test│    │security-scan │                  │
│  │  • golangci  │    │  • gosec     │                  │
│  │  • go test   │    │  • trivy fs  │                  │
│  └──────┬───────┘    └──────┬───────┘                  │
│         │                  │                           │
│         └─────────┬─────────┘                          │
│                   │ ✅ Ambos passam                     │
│                   ▼                                    │
│          ┌─────────────────┐                           │
│          │ build-and-push  │                           │
│          │  • docker build │                           │
│          │  • trivy image  │                           │
│          │  • docker push  │  → OCIR (region.ocir.io)  │
│          └────────┬────────┘                           │
│                   │                                    │
│                   ▼                                    │
│          ┌─────────────────┐                           │
│          │  update-gitops  │                           │
│          │  • sed image tag│                           │
│          │  • git push     │  → main branch            │
│          └─────────────────┘                           │
└────────────────────────────────────────────────────────┘
               │
               │ ArgoCD detecta mudança no deployment.yaml
               ▼
        ┌─────────────┐
        │  OKE Cluster │
        │  kubectl     │ ← Nova versão deployada!
        │  rolling     │
        └─────────────┘
8. Configuração do GitHub Environment
Passo a Passo: Criar Environment dev com aprovação obrigatória
No repositório GitHub, acesse Settings → Environments
Clique em New environment
Nome: dev
Clique em Configure environment
Em Deployment protection rules, ative Required reviewers
Adicione pelo menos 1 reviewer (seu usuário ou um collaborator)
Clique em Save protection rules
GitHub Repository
   └── Settings
        └── Environments
             └── New environment: "dev"
                  └── Protection Rules
                       └── ✅ Required reviewers
                            └── [@seu-usuario]
Secrets Necessários (GitHub → Settings → Secrets → Actions)
Secrets de Infraestrutura (Terraform):

Secret	Descrição	Como Obter
OCI_TENANCY_OCID	OCID do tenancy	OCI Console → Profile → Tenancy
OCI_USER_OCID	OCID do usuário	OCI Console → Profile → User Settings
OCI_FINGERPRINT	Fingerprint da API Key	OCI Console → User → API Keys
OCI_PRIVATE_KEY	Chave privada em base64	cat key.pem | base64 | tr -d '\n'
OCI_REGION	Região OCI	Ex: sa-vinhedo-1
OCI_COMPARTMENT_ID	OCID do compartment	OCI Console → Identity → Compartments
OCI_SSH_PUBLIC_KEY	Chave pública SSH	cat ~/.ssh/id_rsa.pub
Secrets de Deploy de Serviços:

Secret	Descrição
OCI_AUTH_TOKEN	Token de autenticação do OCIR (gerado em User → Auth Tokens)
OCI_TENANCY_NAMESPACE	Namespace do tenancy para o OCIR
OCI_USERNAME	Username OCI para login no registry
Diagrama de Secrets por Pipeline
terraform-plan.yml
terraform-apply.yml    ──► OCI_TENANCY_OCID, OCI_USER_OCID, OCI_FINGERPRINT,
terraform-destroy.yml      OCI_PRIVATE_KEY, OCI_REGION, OCI_COMPARTMENT_ID,
                           OCI_SSH_PUBLIC_KEY

*-deploy.yml           ──► OCI_REGION, OCI_AUTH_TOKEN,
                           OCI_TENANCY_NAMESPACE, OCI_USERNAME
9. Testes Locais
9.1 Pré-requisitos
# Ferramentas necessárias
terraform >= 1.10.0
go >= 1.21
python >= 3.11
docker
kubectl
jq
curl
9.2 Testes da Infraestrutura Terraform
# 1. Configurar credenciais OCI locais
mkdir -p ~/.oci
cp oci_api_key.pem ~/.oci/
chmod 600 ~/.oci/oci_api_key.pem

cat > ~/.oci/config << EOF
[DEFAULT]
user=ocid1.user.oc1..aaaaaaaa...
fingerprint=aa:bb:cc:dd:ee:ff:...
tenancy=ocid1.tenancy.oc1..aaaaaaaa...
region=sa-vinhedo-1
key_file=~/.oci/oci_api_key.pem
EOF

# 2. Exportar variáveis sensíveis
export TF_VAR_tenancy_ocid="ocid1.tenancy.oc1..aaaaaaaa..."
export TF_VAR_user_ocid="ocid1.user.oc1..aaaaaaaa..."
export TF_VAR_fingerprint="aa:bb:cc:dd:ee:ff:..."
export TF_VAR_region="sa-vinhedo-1"
export TF_VAR_compartment_id="ocid1.compartment.oc1..aaaaaaaa..."
export TF_VAR_ssh_public_key="$(cat ~/.ssh/id_rsa.pub)"
export TF_VAR_image_id="ocid1.image.oc1..."
export TF_VAR_availability_domain="AD-1"
export TF_VAR_oke_image="ocid1.image.oc1..."

# 3. Executar Terraform
cd terraform
terraform init
terraform validate
terraform plan -var-file=envs/dev.tfvars
terraform apply -var-file=envs/dev.tfvars

# 4. Destruir recursos quando não precisar
terraform destroy -var-file=envs/dev.tfvars
9.3 Testes do auth-service (Go)
cd auth-service

# Executar lint
go vet ./...

# Executar testes unitários
go test -v ./...

# Executar localmente (requer PostgreSQL rodando)
export DATABASE_URL="postgres://user:password@localhost:5432/authdb?sslmode=disable"
export MASTER_KEY="mymasterkey"
go run main.go

# Em outro terminal, testar os endpoints
./scripts/test-services.sh localhost 8001
9.4 Testes do flag-service (Python)
cd flag-service

# Instalar dependências
pip install -r requirements.txt
pip install flake8 pytest bandit

# Lint
flake8 . --count --select=E9,F63,F7,F82 --show-source --statistics

# Análise de segurança estática
bandit -r .

# Executar localmente (requer PostgreSQL e auth-service rodando)
export DATABASE_URL="postgres://user:password@localhost:5432/flagdb?sslmode=disable"
export AUTH_SERVICE_URL="http://localhost:8001"
python app.py
9.5 Testes com Docker Compose (Todos os serviços)
# Na raiz do projeto — crie um docker-compose.yml de desenvolvimento
# ou use o script de teste:

# 1. Subir PostgreSQL + Redis localmente
docker run -d --name postgres -e POSTGRES_PASSWORD=secret -p 5432:5432 postgres:15
docker run -d --name redis -p 6379:6379 redis:7

# 2. Testar a API com o script de testes
./scripts/test-services.sh localhost 8001
9.6 Testes com Postman
Importe o arquivo ToggleMaster_Postman_Collection.json no Postman:

Abra o Postman
Import → selecione ToggleMaster_Postman_Collection.json
Configure as variáveis de coleção:
base_url: http://localhost:8001
master_key: mymasterkey
Execute as requests na ordem: Create Key → Validate Key → Create Flag → Evaluate
9.7 Fluxo de Teste End-to-End Manual
AUTH_URL="http://localhost:8001"
FLAG_URL="http://localhost:8002"
TARGET_URL="http://localhost:8003"
EVAL_URL="http://localhost:8004"

# 1. Criar uma API Key via admin
API_KEY=$(curl -s -X POST "$AUTH_URL/admin/keys" \
  -H "Authorization: Bearer mymasterkey" \
  -H "Content-Type: application/json" \
  -d '{"name": "test-key"}' | jq -r '.key')

echo "API Key gerada: $API_KEY"

# 2. Criar uma feature flag
curl -s -X POST "$FLAG_URL/flags" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"name": "minha-feature", "description": "Teste", "is_enabled": true}'

# 3. Criar regra de segmentação (50% dos usuários)
curl -s -X POST "$TARGET_URL/rules" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"flag_name": "minha-feature", "rules": {"type": "PERCENTAGE", "value": 50}}'

# 4. Avaliar a flag para um usuário
curl -s "$EVAL_URL/evaluate?user_id=user-123&flag_name=minha-feature"
# Retorna: {"flag_name":"minha-feature","user_id":"user-123","result":true}
10. Segurança
10.1 Modelo de Segurança
┌─────────────────────────────────────────────────────────┐
│                   Camadas de Segurança                   │
│                                                         │
│  1. Secrets Management                                  │
│     └─ GitHub Secrets (7 secrets OCI + 3 deploy)       │
│     └─ Nunca expostos em código ou logs                 │
│                                                         │
│  2. Autenticação de APIs                                │
│     └─ API Keys com hash SHA-256 (armazenado no banco)  │
│     └─ Master Key para administração                    │
│     └─ Validação centralizada no auth-service           │
│                                                         │
│  3. Aprovação Manual (Environment Protection)           │
│     └─ Apply e Destroy exigem aprovação humana          │
│     └─ GitHub Environment: dev (Required reviewers)     │
│                                                         │
│  4. Segurança de Contêineres (SAST + SCA + Scan)       │
│     └─ Gosec / Bandit: análise estática de código       │
│     └─ Trivy (filesystem): vulnerabilidades em deps     │
│     └─ Trivy (container): vulnerabilidades na imagem    │
│     └─ Build falha em vulnerabilidades CRITICAL         │
│                                                         │
│  5. Infraestrutura                                      │
│     └─ Remote state no OCI Object Storage (criptografado)│
│     └─ Módulos Terraform oficiais da Oracle versionados │
│     └─ Zero valores hardcoded no código Terraform       │
│     └─ sensitive = true para variáveis sensíveis        │
│                                                         │
└─────────────────────────────────────────────────────────┘
10.2 Gerenciamento de Segredos
Nunca commite no repositório:

Chaves privadas OCI (*.pem)
Valores de API Keys
Strings de conexão com banco de dados
Tokens de autenticação
O que é seguro commitar:

terraform/envs/dev.tfvars — apenas CIDRs, nomes e configurações não-sensíveis
.env.example — apenas exemplos sem valores reais
10.3 Armazenamento Seguro de API Keys
O auth-service armazena apenas o hash SHA-256 da chave, nunca o valor original:

API Key gerada: tm_key_<64-hex-chars>
                │
                ▼ SHA-256
Hash armazenado no banco: <64-hex-chars>
                │
Chave original: exibida apenas na criação (não recuperável)
10.4 Pipeline de Segurança (por serviço)
Código fonte
     │
     ▼ SAST (análise estática)
  Gosec (Go) / Bandit (Python)
     │ Bloqueia se vulnerabilidade encontrada
     ▼ SCA (análise de dependências)
  Trivy filesystem scan
     │ Bloqueia em CRITICAL
     ▼ Container scan
  Trivy image scan
     │ Bloqueia em CRITICAL
     ▼
  Push para OCIR + Deploy
10.5 Boas Práticas Implementadas
Prática	Implementação
Secrets isolados	GitHub Secrets com acesso restrito
Hashing de chaves	SHA-256 (auth-service)
Aprovação manual	GitHub Environment dev com Required reviewers
SAST	Gosec (Go), Bandit (Python) em todas as pipelines
SCA	Trivy filesystem em todas as pipelines
Container scan	Trivy image após build
Terraform state remoto	OCI Object Storage (criptografado em repouso)
Módulos versionados	version = ">= 5.0.0" nos providers
Zero hardcoded secrets	Todas as credenciais via TF_VAR_* e GitHub Secrets
Pool de conexões DB	Limite máximo configurado (psycopg2 pool, sql.DB)
Timeout em chamadas HTTP	timeout=3 nos requests Python
10.6 Checklist de Segurança para Deploy
 Todos os 7 GitHub Secrets de OCI configurados
 Secrets de deploy configurados (OCI_AUTH_TOKEN, OCI_TENANCY_NAMESPACE, OCI_USERNAME)
 Environment dev criado com Required reviewers
 Nenhum segredo em dev.tfvars ou em código-fonte
 Trivy CRITICAL está bloqueando builds
 Chave privada OCI convertida para base64 sem quebras de linha
 MASTER_KEY definida como secret no Kubernetes (não em texto claro)
📚 Referências
Terraform OCI Provider
Terraform OCI Backend
Oracle Terraform Modules
OCI Free Tier
ArgoCD Documentation
GitHub Actions Environments
Trivy Security Scanner
