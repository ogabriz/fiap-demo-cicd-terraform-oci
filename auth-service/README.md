# auth-service (Go)

Servico de autenticacao do projeto ToggleMaster. Responsavel por criar e validar chaves de API.

## Pre-requisitos (Local)

* [Go](https://go.dev/doc/install) (versao 1.21 ou superior)
* [PostgreSQL](https://www.postgresql.org/download/) (rodando localmente ou em um container Docker)

## Rodando Localmente

1. **Prepare o Banco de Dados:**
   ```bash
   psql -U seu_usuario -d auth_db -f db/init.sql
   ```

2. **Configure as Variaveis de Ambiente:**
   ```bash
   cp .env.example .env
   # Edite o arquivo .env com suas credenciais
   ```

3. **Instale as Dependencias:**
   ```bash
   go mod tidy
   ```

4. **Inicie o Servico:**
   ```bash
   go run .
   ```
   O servidor estara rodando em `http://localhost:8001`.

## Endpoints

| Metodo | Endpoint       | Descricao                     | Autenticacao       |
|--------|----------------|-------------------------------|--------------------|
| GET    | `/health`      | Health check                  | Nenhuma            |
| POST   | `/admin/keys`  | Criar nova chave de API       | Bearer MASTER_KEY  |
| GET    | `/validate`    | Validar chave de API          | Bearer API_KEY     |

## Deploy no OKE

Os manifests Kubernetes estao em `k8s/`:

```bash
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/secret.yaml      # Editar com credenciais reais
kubectl apply -f k8s/db-init-job.yaml
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
```

## CI/CD

O workflow `.github/workflows/auth-service-deploy.yml` faz build da imagem Docker, push para o OCIR, e deploy no OKE automaticamente quando houver push na `main` com alteracoes em `auth-service/**`.

### Secrets adicionais necessarios

| Secret           | Descricao                                     |
|------------------|-----------------------------------------------|
| `OCI_AUTH_TOKEN` | Auth token do usuario OCI para login no OCIR  |
| `OCI_USERNAME`   | Username OCI (email) para login no OCIR       |
