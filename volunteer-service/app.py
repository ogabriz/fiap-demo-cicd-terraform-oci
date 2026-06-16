import os
import uuid
import time
import logging

import oci
from flask import Flask, request, jsonify
from dotenv import load_dotenv

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
log = logging.getLogger(__name__)

load_dotenv()

app = Flask(__name__)

OCI_REGION = os.getenv("OCI_REGION", "sa-saopaulo-1")
NOSQL_COMPARTMENT_ID = os.getenv("OCI_NOSQL_COMPARTMENT_ID")
NOSQL_TABLE_NAME = os.getenv("OCI_NOSQL_TABLE_NAME", "togglemaster_table")


def get_nosql_client():
    if not NOSQL_COMPARTMENT_ID:
        log.warning("OCI_NOSQL_COMPARTMENT_ID nao definida. NoSQL desabilitado.")
        return None

    try:
        signer = oci.auth.signers.InstancePrincipalsSecurityTokenSigner()
        return oci.nosql.NosqlClient(config={}, signer=signer)
    except Exception:
        log.info("Instance Principal indisponivel, tentando config file (~/.oci/config)")

    try:
        config = oci.config.from_file()
        return oci.nosql.NosqlClient(config)
    except Exception as e:
        log.warning(f"OCI NoSQL indisponivel (servico continua sem NoSQL): {e}")
        return None


nosql_client = get_nosql_client()
if nosql_client:
    log.info(f"Conectado ao OCI NoSQL - Tabela: {NOSQL_TABLE_NAME}")
else:
    log.info("Servico iniciado sem OCI NoSQL (modo degradado)")


@app.route('/health')
def health():
    return jsonify({"status": "ok", "service": "volunteer-service"})


@app.route('/volunteers', methods=['POST'])
def register_volunteer():
    data = request.get_json()
    if not data or not all(k in data for k in ('name', 'email', 'ngo_id')):
        return jsonify({"error": "Campos obrigatorios ausentes"}), 400

    if not nosql_client:
        return jsonify({"error": "OCI NoSQL nao configurado"}), 503

    volunteer_id = str(uuid.uuid4())
    row_value = {
        'id': volunteer_id,
        'name': data['name'],
        'email': data['email'],
        'ngo_id': str(data['ngo_id']),
        'registered_at': str(int(time.time()))
    }

    try:
        nosql_client.update_row(
            table_name_or_id=NOSQL_TABLE_NAME,
            update_row_details=oci.nosql.models.UpdateRowDetails(
                value=row_value,
                compartment_id=NOSQL_COMPARTMENT_ID
            )
        )
        return jsonify(row_value), 201
    except Exception as e:
        log.error(f"Erro ao salvar voluntario no OCI NoSQL: {e}")
        return jsonify({"error": "Erro interno ao processar dados"}), 500


@app.route('/volunteers/<int:ngo_id>', methods=['GET'])
def get_volunteers_by_ngo(ngo_id):
    if not nosql_client:
        return jsonify({"error": "OCI NoSQL nao configurado"}), 503

    try:
        statement = "SELECT * FROM {} WHERE ngo_id = '{}'".format(  # nosec B608
            NOSQL_TABLE_NAME, ngo_id)
        response = nosql_client.query(
            query_details=oci.nosql.models.QueryDetails(
                compartment_id=NOSQL_COMPARTMENT_ID,
                statement=statement,
                consistency="EVENTUAL"
            )
        )
        items = [row for row in (response.data.items or [])]
        return jsonify(items), 200
    except Exception as e:
        log.error(f"Erro ao buscar dados no OCI NoSQL: {e}")
        return jsonify({"error": "Erro interno"}), 500


if __name__ == '__main__':
    port = int(os.getenv("PORT", 8083))
    app.run(host='0.0.0.0', port=port)  # nosec B104
