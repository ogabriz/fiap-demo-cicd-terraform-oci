import os
import psycopg2
import requests
from flask import Flask, request, jsonify

app = Flask(__name__)

# Configurações via variáveis de ambiente
PORT = int(os.environ.get("PORT", 8003))
DATABASE_URL = os.environ.get("DATABASE_URL")
AUTH_SERVICE_URL = os.environ.get("AUTH_SERVICE_URL")

@app.route('/health', methods=['GET'])
def health():
    return jsonify({"status": "ok", "service": "targeting-service"})

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

@app.route('/target', methods=['POST'])
def check_targeting():
    if not validate_token():
        return jsonify({"error": "Unauthorized"}), 401
    
    data = request.json
    user_id = data.get("user_id")
    # Placeholder para demo: target users with ID ending in even numbers
    is_targeted = int(user_id) % 2 == 0 if user_id and user_id.isdigit() else False
    return jsonify({"targeted": is_targeted})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=PORT)
