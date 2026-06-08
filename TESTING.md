# Guia de Testes e Validacao na OCI

Este guia explica como testar e validar todos os servicos da SolidaryTech diretamente na Oracle Cloud Infrastructure.

---

## Pre-requisitos

- OCI CLI configurado (`~/.oci/config`)
- `kubectl` configurado para o cluster OKE
- Acesso ao namespace `togglemaster` no cluster

### Configurar kubectl para OKE

```bash
# Obter kubeconfig do cluster OKE
oci ce cluster create-kubeconfig \
  --cluster-id <OCI_OKE_CLUSTER_ID> \
  --file ~/.kube/config \
  --region sa-saopaulo-1 \
  --token-version 2.0.0

# Verificar conexao
kubectl get nodes
kubectl get pods -n togglemaster
```

---

## 1. Validar Infraestrutura Terraform

```bash
cd terraform

# Verificar estado dos recursos
terraform state list

# Outputs importantes
terraform output queue_id
terraform output queue_messages_endpoint
terraform output nosql_table_id
terraform output oke_cluster_id
```

---

## 1.1 Deploy da Infraestrutura In-Cluster (PostgreSQL + Redis)

PostgreSQL e Redis rodam como pods dentro do cluster OKE (nao mais em VMs externas).

### Passo 1: Limpar servicos antigos

```bash
kubectl delete deployment analytics-service auth-service evaluation-service flag-service targeting-service -n togglemaster --ignore-not-found
kubectl delete svc analytics-service auth-service evaluation-service flag-service targeting-service -n togglemaster --ignore-not-found
kubectl delete job auth-db-init flag-db-init targeting-db-init -n togglemaster --ignore-not-found
```

### Passo 2: Criar Secret do OCIR (obrigatorio para pull de imagens privadas)

Os servicos usam imagens armazenadas no OCI Container Registry (OCIR) que e privado.
E necessario criar um `docker-registry` secret para que o Kubernetes consiga fazer pull das imagens.

```bash
# Substituir os valores com suas credenciais OCI:
#   TENANCY_NAMESPACE = namespace do tenancy (ex: grqkmwwimskh)
#   OCI_USERNAME      = usuario OCI (ex: oracleidentitycloudservice/seu@email.com)
#   AUTH_TOKEN         = Auth Token gerado no OCI Console (Identity > Users > Auth Tokens)

kubectl create secret docker-registry ocir-secret \
  --docker-server=sa-saopaulo-1.ocir.io \
  --docker-username="TENANCY_NAMESPACE/OCI_USERNAME" \
  --docker-password="AUTH_TOKEN" \
  --docker-email=noreply@oci.com \
  -n togglemaster
```

> **Nota:** Se o secret ja existir, delete e recrie:
> `kubectl delete secret ocir-secret -n togglemaster --ignore-not-found` antes de criar.

### Passo 3: Deploy PostgreSQL e Redis

```bash
kubectl apply -f k8s-infra/postgres.yaml
kubectl apply -f k8s-infra/redis.yaml

# Aguardar pods ficarem prontos
kubectl rollout status deployment/postgres -n togglemaster --timeout=120s
kubectl rollout status deployment/redis -n togglemaster --timeout=120s
```

### Passo 4: Inicializar bancos de dados

```bash
kubectl delete job db-init-ngo db-init-donation -n togglemaster --ignore-not-found
kubectl apply -f k8s-infra/db-init-job.yaml
kubectl wait --for=condition=complete job/db-init-ngo -n togglemaster --timeout=120s
kubectl wait --for=condition=complete job/db-init-donation -n togglemaster --timeout=120s
```

### Passo 5: Deploy dos servicos

```bash
kubectl apply -f k8s-common/ingress.yaml
kubectl apply -f ngo-service/k8s/manifests.yaml
kubectl apply -f donation-service/k8s/manifests.yaml
kubectl apply -f volunteer-service/k8s/manifests.yaml
```

### Passo 6: Verificar status

```bash
kubectl get pods -n togglemaster
# Todos os pods devem estar Running
# Se algum servico estiver em ImagePullBackOff, verifique o secret:
#   kubectl describe pod <nome-do-pod> -n togglemaster | grep -A5 Events
```

---

## 2. Verificar Pods e Servicos

```bash
# Status dos pods
kubectl get pods -n togglemaster -o wide

# Status dos servicos
kubectl get svc -n togglemaster

# Status dos ingress
kubectl get ingress -n togglemaster

# Verificar se todos os pods estao Running
kubectl get pods -n togglemaster --field-selector=status.phase!=Running
```

### Health Checks

```bash
# Obter IP do Load Balancer (Ingress)
export LB_IP=$(kubectl get ingress togglemaster-ingress -n togglemaster -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# NGO Service
curl -s http://$LB_IP/ngos/health | jq .

# Donation Service
curl -s http://$LB_IP/donations/health | jq .

# Volunteer Service
curl -s http://$LB_IP/volunteers/health | jq .
```

---

## 3. Testar NGO Service (PostgreSQL)

### Criar uma ONG

```bash
curl -X POST http://$LB_IP/ngos/ngos \
  -H "Content-Type: application/json" \
  -d '{
    "name": "ONG Teste SolidaryTech",
    "description": "Organizacao de teste",
    "contact_email": "teste@solidarytech.com"
  }' | jq .
```

### Listar ONGs

```bash
curl -s http://$LB_IP/ngos/ngos | jq .
```

### Validar no PostgreSQL

```bash
# Conectar no pod PostgreSQL
kubectl exec -it $(kubectl get pods -n togglemaster -l app=postgres -o jsonpath='{.items[0].metadata.name}') -n togglemaster -- psql -U togglemaster_user -d ngo_db

# Dentro do psql:
SELECT * FROM ngos;
\q
```

---

## 4. Testar Donation Service (PostgreSQL + OCI Queue)

### Criar uma Doacao

```bash
curl -X POST http://$LB_IP/donations/donations \
  -H "Content-Type: application/json" \
  -d '{
    "ngo_id": 1,
    "amount": 150.00,
    "donor_name": "Doador Teste"
  }' | jq .
```

### Listar Doacoes

```bash
curl -s http://$LB_IP/donations/donations | jq .
```

### Validar no PostgreSQL

```bash
kubectl exec -it $(kubectl get pods -n togglemaster -l app=postgres -o jsonpath='{.items[0].metadata.name}') -n togglemaster -- psql -U togglemaster_user -d donation_db

# Dentro do psql:
SELECT * FROM donations ORDER BY id DESC;
\q
```

### Validar OCI Queue (mensagens enviadas)

```bash
# Via OCI CLI - listar mensagens na fila
oci queue messages get-messages \
  --queue-id $(terraform -chdir=terraform output -raw queue_id) \
  --visibility-in-seconds 30 \
  --timeout-in-seconds 5 \
  --limit 10

# Verificar logs do donation-service para confirmar envio
kubectl logs -n togglemaster -l app=donation-service --tail=50 | grep -i "queue\|mensagem\|OCI"
```

---

## 5. Testar Volunteer Service (OCI NoSQL)

### Registrar um Voluntario

```bash
curl -X POST http://$LB_IP/volunteers/volunteers \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Voluntario Teste",
    "email": "voluntario@solidarytech.com",
    "ngo_id": 1
  }' | jq .
```

### Listar Voluntarios por ONG

```bash
curl -s http://$LB_IP/volunteers/volunteers/1 | jq .
```

### Validar no OCI NoSQL

```bash
# Via OCI CLI - consultar tabela NoSQL
oci nosql query execute \
  --compartment-id $(terraform -chdir=terraform output -raw nosql_table_id | sed 's/nosqltable/compartment/') \
  --statement "SELECT * FROM togglemaster_table" \
  --output table

# Ou verificar logs do volunteer-service
kubectl logs -n togglemaster -l app=volunteer-service --tail=50
```

---

## 6. Teste de Carga (Stress Test)

### Instalar hey (HTTP load generator)

```bash
# Linux
wget -q https://hey-release.s3.us-east-2.amazonaws.com/hey_linux_amd64 -O hey
chmod +x hey
```

### Executar teste de carga no Donation Service (Hot Path)

```bash
# 100 requests, 10 concorrentes
./hey -n 100 -c 10 -m POST \
  -H "Content-Type: application/json" \
  -d '{"ngo_id":1,"amount":50.00,"donor_name":"Load Test"}' \
  http://$LB_IP/donations/donations

# 500 requests, 20 concorrentes (stress)
./hey -n 500 -c 20 -m POST \
  -H "Content-Type: application/json" \
  -d '{"ngo_id":1,"amount":25.00,"donor_name":"Stress Test"}' \
  http://$LB_IP/donations/donations
```

### Teste de carga no NGO Service

```bash
./hey -n 200 -c 10 \
  http://$LB_IP/ngos/ngos
```

---

## 7. Monitoramento - Grafana

### Acessar Grafana

```bash
# Obter IP do Grafana (LoadBalancer)
kubectl get svc -n monitoring prometheus-stack-grafana -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

# Credenciais padrao:
# Usuario: admin
# Senha: prom-operator (ou obtida via secret)
kubectl get secret -n monitoring prometheus-stack-grafana -o jsonpath='{.data.admin-password}' | base64 -d; echo
```

### Dashboards Disponiveis

1. **Custom Dashboard (SolidaryTech)**
   - CPU Usage por namespace
   - Memory Usage por namespace
   - Network Traffic Rate (pods togglemaster)
   - Logs (Loki - namespace togglemaster)
   - Redis Memory e Commands/s
   - Pod Restarts

2. **Kubernetes / Compute Resources**
   - Dashboard padrao do kube-prometheus-stack

3. **Alertas Configurados**
   - PodCrashLooping (critical) - pod em restart loop
   - HighErrorRate (warning) - taxa de erros 5xx > 0.5/s
   - HighCPUUsage (warning) - CPU > 80% por 5min
   - PodNotReady (critical) - pod nao Ready por 5min

### Validar Alertas

```bash
# Ver alertas ativos no Prometheus
kubectl port-forward -n monitoring svc/prometheus-stack-kube-prom-prometheus 9090:9090 &

# Acessar http://localhost:9090/alerts
# Verificar se os alertas togglemaster estao configurados

# Ver alertas no Alertmanager
kubectl port-forward -n monitoring svc/prometheus-stack-kube-prom-alertmanager 9093:9093 &
# Acessar http://localhost:9093
```

### Testar Alerta (simular falha)

```bash
# Escalar para 0 replicas (simula PodNotReady)
kubectl scale deployment donation-service -n togglemaster --replicas=0

# Aguardar 5 minutos e verificar:
# 1. Alerta PodNotReady no Grafana
# 2. Notificacao no Discord

# Restaurar
kubectl scale deployment donation-service -n togglemaster --replicas=1
```

---

## 8. Monitoramento - New Relic

### Verificar Integracao

Os servicos Python (ngo-service, volunteer-service) enviam telemetria automaticamente via OpenTelemetry auto-instrumentacao.

```bash
# Verificar que os pods tem as variaveis OTEL configuradas
kubectl get pods -n togglemaster -l app=ngo-service -o jsonpath='{.items[0].spec.containers[0].env}' | jq .

# Verificar logs de instrumentacao OTel
kubectl logs -n togglemaster -l app=ngo-service --tail=20 | grep -i "otel\|opentelemetry\|trace"
```

### No Console New Relic

1. Acesse [one.newrelic.com](https://one.newrelic.com)
2. Va em **APM & Services**
3. Procure os servicos:
   - `ngo-service`
   - `donation-service`
   - `volunteer-service`
4. Verifique:
   - **Distributed Traces** - rastreamento das requests
   - **Errors** - erros capturados
   - **Metrics** - latencia, throughput
   - **Logs** - logs estruturados

### Testar Traces no New Relic

```bash
# Fazer algumas requests para gerar traces
for i in $(seq 1 10); do
  curl -s http://$LB_IP/ngos/ngos > /dev/null
  curl -s http://$LB_IP/donations/donations > /dev/null
  curl -s -X POST http://$LB_IP/volunteers/volunteers \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"Trace Test $i\",\"email\":\"trace$i@test.com\",\"ngo_id\":1}" > /dev/null
done

echo "Aguarde 1-2 minutos e verifique no New Relic > Distributed Tracing"
```

---

## 9. Monitoramento - Loki (Logs)

### Consultar Logs via Grafana

1. Acesse Grafana
2. Va em **Explore** > selecione **Loki**
3. Execute queries:

```logql
# Todos os logs do namespace togglemaster
{namespace="togglemaster"}

# Logs do donation-service
{namespace="togglemaster", app="donation-service"}

# Apenas erros
{namespace="togglemaster"} |= "error" or {namespace="togglemaster"} |= "Error"

# Logs do volunteer-service com OCI NoSQL
{namespace="togglemaster", app="volunteer-service"} |= "NoSQL"
```

---

## 10. Validacao Completa (Checklist)

```bash
#!/bin/bash
echo "=== Checklist de Validacao SolidaryTech OCI ==="

export LB_IP=$(kubectl get ingress togglemaster-ingress -n togglemaster -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

echo ""
echo "1. Pods Running:"
kubectl get pods -n togglemaster --no-headers | awk '{print "   " $1 " -> " $3}'

echo ""
echo "2. Health Checks:"
echo -n "   NGO Service:       "; curl -s -o /dev/null -w "%{http_code}" http://$LB_IP/ngos/health
echo ""
echo -n "   Donation Service:  "; curl -s -o /dev/null -w "%{http_code}" http://$LB_IP/donations/health
echo ""
echo -n "   Volunteer Service: "; curl -s -o /dev/null -w "%{http_code}" http://$LB_IP/volunteers/health
echo ""

echo ""
echo "3. Criar ONG:"
curl -s -X POST http://$LB_IP/ngos/ngos \
  -H "Content-Type: application/json" \
  -d '{"name":"Validacao OCI","description":"Teste completo","contact_email":"validacao@oci.com"}' | jq -r '.id // "ERRO"'

echo ""
echo "4. Criar Doacao:"
curl -s -X POST http://$LB_IP/donations/donations \
  -H "Content-Type: application/json" \
  -d '{"ngo_id":1,"amount":100.00,"donor_name":"Validacao OCI"}' | jq -r '.id // "ERRO"'

echo ""
echo "5. Criar Voluntario:"
curl -s -X POST http://$LB_IP/volunteers/volunteers \
  -H "Content-Type: application/json" \
  -d '{"name":"Validacao OCI","email":"vol@oci.com","ngo_id":"1"}' | jq -r '.id // "ERRO"'

echo ""
echo "6. Monitoring:"
GRAFANA_IP=$(kubectl get svc -n monitoring prometheus-stack-grafana -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
echo "   Grafana: http://${GRAFANA_IP:-NAO_DISPONIVEL}:80"
echo "   New Relic: https://one.newrelic.com"

echo ""
echo "=== Validacao completa ==="
```

---

## Troubleshooting

### Pod em ImagePullBackOff

Significa que o Kubernetes nao consegue baixar a imagem do OCIR (registro privado).

```bash
# Verificar o erro detalhado
kubectl describe pod <pod-name> -n togglemaster | grep -A10 Events

# Verificar se o secret ocir-secret existe
kubectl get secret ocir-secret -n togglemaster

# Se nao existir, criar (ver secao 1.1 Passo 2)
# Se existir mas com credenciais erradas, recriar:
kubectl delete secret ocir-secret -n togglemaster
# ... e criar novamente com as credenciais corretas

# Verificar se a imagem existe no OCIR
# OCI Console > Developer Services > Container Registry
```

### Pod em ImageInspectError

Geralmente e um problema no node do cluster. Solucoes:

```bash
# Deletar o pod para forcar re-scheduling
kubectl delete pod <pod-name> -n togglemaster

# Se persistir, verificar se o node tem espaco em disco
kubectl describe node <node-name> | grep -A5 "Conditions"

# Para postgres, se o PVC ja existia antes, pode ser necessario recriar:
kubectl delete pvc postgres-pvc -n togglemaster
kubectl apply -f k8s-infra/postgres.yaml
```

### Pod em CrashLoopBackOff

```bash
# Ver logs do pod com erro
kubectl logs -n togglemaster <pod-name> --previous

# Descrever pod para ver eventos
kubectl describe pod -n togglemaster <pod-name>
```

### Erro de conexao com PostgreSQL

```bash
# Verificar se o postgres esta acessivel
kubectl exec -it $(kubectl get pods -n togglemaster -l app=postgres -o jsonpath='{.items[0].metadata.name}') -n togglemaster -- pg_isready

# Verificar se o DATABASE_URL esta correto
kubectl get secret donation-service-secret -n togglemaster -o jsonpath='{.data.DATABASE_URL}' | base64 -d; echo
```

### Erro de conexao com OCI Queue

```bash
# Verificar se o pod tem acesso (Instance Principal)
kubectl exec -it $(kubectl get pods -n togglemaster -l app=donation-service -o jsonpath='{.items[0].metadata.name}') -n togglemaster -- env | grep OCI

# Verificar logs
kubectl logs -n togglemaster -l app=donation-service --tail=100 | grep -i "queue\|erro\|error"
```

### Erro de conexao com OCI NoSQL

```bash
# Verificar variaveis de ambiente
kubectl exec -it $(kubectl get pods -n togglemaster -l app=volunteer-service -o jsonpath='{.items[0].metadata.name}') -n togglemaster -- env | grep OCI

# Verificar logs
kubectl logs -n togglemaster -l app=volunteer-service --tail=100 | grep -i "nosql\|erro\|error"
```
