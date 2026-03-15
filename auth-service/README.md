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

- `GET /health`: Health check simples da aplicação.
- `GET /health/db`: Health check que verifica a conexão e conectividade com o banco de dados (Smoke Test).
- `POST /admin/keys`: Cria uma nova chave de API (requer `MASTER_KEY` no header `Authorization: Bearer <key>`).
- `GET /validate`: Valida uma chave de API (requer a chave no header `Authorization: Bearer <key>`).

### Testando os Endpoints

Você pode testar os endpoints de várias formas:

1. **REST Client (VS Code):** Use o arquivo `tests/api-tests.http` na raiz do projeto. Basta clicar em "Send Request" acima de cada endpoint.
2. **Script Python Automatizado:** Use o script `tests/smoke_test.py`. Ele testa todo o fluxo: Health -> DB Health -> Gerar Chave -> Validar Chave.
   ```bash
   # Configure a URL e a Master Key (opcional, defaults: localhost:8001 e mymasterkey)
   export AUTH_SERVICE_URL=http://<IP_DO_LB>:8001
   export MASTER_KEY=mymasterkey
   python tests/smoke_test.py
   ```
3. **Script Shell:** Use o script `scripts/test-services.sh <IP_DO_LB>`.
4. **Testes Unitários (Go):** Para testar a lógica interna sem precisar do servidor rodando:
   ```bash
   cd auth-service
   go test -v
   ```

Exemplo via curl para gerar chave:
```bash
curl -X POST http://<IP_DO_LB>:8001/admin/keys \
  -H "Authorization: Bearer mymasterkey" \
  -H "Content-Type: application/json" \
  -d '{"name": "Nova Chave"}'
```

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
