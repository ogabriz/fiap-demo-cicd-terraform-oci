import os
import psycopg2
import requests
from flask import Flask, request, jsonify
from datetime import datetime

app = Flask(__name__)

# Configurações via variáveis de ambiente
PORT = int(os.environ.get("PORT", 8002))
DATABASE_URL = os.environ.get("DATABASE_URL")
AUTH_SERVICE_URL = os.environ.get("AUTH_SERVICE_URL")

def get_db_connection():
    if not DATABASE_URL:
        return None
    return psycopg2.connect(DATABASE_URL)

@app.route('/health', methods=['GET'])
def health():
    return jsonify({"status": "ok", "service": "flag-service"})

def validate_token():
    auth_header = request.headers.get('Authorization')
    if not auth_header:
        return False
    
    try:
        # Chama o auth-service para validar o token
        response = requests.get(
            f"{AUTH_SERVICE_URL}/validate",
            headers={"Authorization": auth_header},
            timeout=5
        )
        return response.status_code == 200
    except Exception as e:
        print(f"Error validating token: {e}")
        return False

@app.route('/flags', methods=['GET'])
def get_flags():
    if not validate_token():
        return jsonify({"error": "Unauthorized"}), 401
    
    # Placeholder para demo
    return jsonify([
        {"id": 1, "name": "new-feature", "enabled": True},
        {"id": 2, "name": "dark-mode", "enabled": False}
    ])

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=PORT)
