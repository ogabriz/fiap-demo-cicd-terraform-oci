import os
import sys
import threading
import json
import uuid
import time
import logging
import oci
from flask import Flask, jsonify
from dotenv import load_dotenv

# Configura o logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
log = logging.getLogger(__name__)

# Carrega .env para desenvolvimento local
load_dotenv()

# --- Configuração ---
OCI_REGION           = os.getenv("OCI_REGION")
OCI_QUEUE_ENDPOINT   = os.getenv("OCI_QUEUE_ENDPOINT")
OCI_QUEUE_ID         = os.getenv("OCI_QUEUE_ID")
OCI_NOSQL_TABLE      = os.getenv("OCI_NOSQL_TABLE", "ToggleMasterAnalytics")
OCI_COMPARTMENT_ID   = os.getenv("OCI_COMPARTMENT_ID")

if not all([OCI_QUEUE_ENDPOINT, OCI_QUEUE_ID, OCI_COMPARTMENT_ID]):
    log.critical("Erro: OCI_QUEUE_ENDPOINT, OCI_QUEUE_ID e OCI_COMPARTMENT_ID devem ser definidos.")
    sys.exit(1)

# --- Clientes OCI ---
# Tenta Resource Principal (OKE), senão usa config padrão (local).
try:
    signer = oci.auth.signers.get_resource_principals_signer()
    oci_config = {}
    log.info("Autenticação via Resource Principal (OKE).")
except Exception as e:
    log.warning(f"Resource Principal não disponível, usando config padrão: {e}")
    oci_config = oci.config.from_file()
    signer = None

try:
    if signer:
        queue_client = oci.queue.QueueClient(config={}, signer=signer, service_endpoint=OCI_QUEUE_ENDPOINT)
        nosql_client = oci.nosql.NosqlClient(config={}, signer=signer)
    else:
        queue_client = oci.queue.QueueClient(config=oci_config, service_endpoint=OCI_QUEUE_ENDPOINT)
        nosql_client = oci.nosql.NosqlClient(config=oci_config)
    log.info("Clientes OCI Queue e NoSQL inicializados.")
except Exception as e:
    log.critical(f"Erro ao inicializar clientes OCI: {e}")
    sys.exit(1)


# --- Queue Worker ---

def process_message(message):
    """Processa uma única mensagem OCI Queue e a insere no NoSQL."""
    try:
        log.info(f"Processando mensagem ID: {message.id}")
        body = json.loads(message.content)

        event_id = str(uuid.uuid4())

        # Insere no OCI NoSQL
        nosql_client.put_row(
            table_name_or_id=OCI_NOSQL_TABLE,
            put_row_details=oci.nosql.models.PutRowDetails(
                compartment_id=OCI_COMPARTMENT_ID,
                value={
                    "event_id":  event_id,
                    "user_id":   body["user_id"],
                    "flag_name": body["flag_name"],
                    "result":    body["result"],
                    "timestamp": body["timestamp"],
                }
            )
        )

        log.info(f"Evento {event_id} (Flag: {body['flag_name']}) salvo no OCI NoSQL.")

        # Deleta a mensagem da fila após processamento bem-sucedido
        queue_client.delete_message(
            queue_id=OCI_QUEUE_ID,
            message_receipt=message.receipt
        )

    except json.JSONDecodeError:
        log.error(f"Erro ao decodificar JSON da mensagem ID: {message.id}")
        # Não deleta — mensagem volta para a fila após visibility timeout
    except oci.exceptions.ServiceError as e:
        log.error(f"Erro OCI (NoSQL ou Queue) ao processar {message.id}: {e}")
    except Exception as e:
        log.error(f"Erro inesperado ao processar {message.id}: {e}")


def queue_worker_loop():
    """Loop principal do worker que consome a OCI Queue."""
    log.info("Iniciando o worker OCI Queue...")
    while True:
        try:
            response = queue_client.get_messages(
                queue_id=OCI_QUEUE_ID,
                visibility_in_seconds=30,
                timeout_in_seconds=20,
                max_messages=10
            )

            messages = response.data.messages
            if not messages:
                continue

            log.info(f"Recebidas {len(messages)} mensagens.")
            for message in messages:
                process_message(message)

        except oci.exceptions.ServiceError as e:
            log.error(f"Erro OCI no loop principal do worker: {e}")
            time.sleep(10)
        except Exception as e:
            log.error(f"Erro inesperado no loop principal do worker: {e}")
            time.sleep(10)


# --- Servidor Flask (apenas Health Check) ---

app = Flask(__name__)

@app.route('/health')
def health():
    return jsonify({"status": "ok"})


# --- Inicialização ---

def start_worker():
    worker_thread = threading.Thread(target=queue_worker_loop, daemon=True)
    worker_thread.start()

# Inicia o worker em background (funciona com 'flask run' e 'gunicorn')
start_worker()

if __name__ == '__main__':
    port = int(os.getenv("PORT", 8005))
    host = os.getenv("HOST", "127.0.0.1")
    app.run(host=host, port=port, debug=False)
