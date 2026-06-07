#!/bin/bash

# Script para testar os servicos SolidaryTech na OCI
# Usage: ./scripts/test-services.sh [LOAD_BALANCER_IP]

IP=${1:-"localhost"}
URL="http://$IP"

echo "=== Teste dos Servicos SolidaryTech ==="

echo -e "\n--- 1. Health Checks ---"
echo -n "NGO Service:       "
curl -s -o /dev/null -w "%{http_code}" "$URL/ngos/health" 2>/dev/null || echo "FAIL"
echo ""
echo -n "Donation Service:  "
curl -s -o /dev/null -w "%{http_code}" "$URL/donations/health" 2>/dev/null || echo "FAIL"
echo ""
echo -n "Volunteer Service: "
curl -s -o /dev/null -w "%{http_code}" "$URL/volunteers/health" 2>/dev/null || echo "FAIL"
echo ""

echo -e "\n--- 2. Criar ONG ---"
curl -s -X POST "$URL/ngos/ngos" \
  -H "Content-Type: application/json" \
  -d '{"name":"ONG Teste","description":"Teste automatizado","contact_email":"teste@solidarytech.com"}' | jq . 2>/dev/null || echo "FAIL"

echo -e "\n--- 3. Listar ONGs ---"
curl -s "$URL/ngos/ngos" | jq . 2>/dev/null || echo "FAIL"

echo -e "\n--- 4. Criar Doacao ---"
curl -s -X POST "$URL/donations/donations" \
  -H "Content-Type: application/json" \
  -d '{"ngo_id":1,"amount":100.00,"donor_name":"Doador Teste"}' | jq . 2>/dev/null || echo "FAIL"

echo -e "\n--- 5. Listar Doacoes ---"
curl -s "$URL/donations/donations" | jq . 2>/dev/null || echo "FAIL"

echo -e "\n--- 6. Registrar Voluntario ---"
curl -s -X POST "$URL/volunteers/volunteers" \
  -H "Content-Type: application/json" \
  -d '{"name":"Voluntario Teste","email":"vol@solidarytech.com","ngo_id":"1"}' | jq . 2>/dev/null || echo "FAIL"

echo -e "\n--- 7. Listar Voluntarios (ONG 1) ---"
curl -s "$URL/volunteers/volunteers/1" | jq . 2>/dev/null || echo "FAIL"

echo -e "\n=== Testes Completos ==="
