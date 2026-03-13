package main

import (
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/joho/godotenv"
	_ "github.com/lib/pq"
)

var db *sql.DB

type CreateKeyRequest struct {
	Name string `json:"name"`
}

type CreateKeyResponse struct {
	Name    string `json:"name"`
	Key     string `json:"key"`
	Message string `json:"message"`
}

type HealthResponse struct {
	Status string `json:"status"`
}

type ValidateResponse struct {
	Message string `json:"message"`
}

func main() {
	_ = godotenv.Load()

	databaseURL := os.Getenv("DATABASE_URL")
	if databaseURL == "" {
		log.Fatal("DATABASE_URL is required")
	}

	port := os.Getenv("PORT")
	if port == "" {
		port = "8001"
	}

	masterKey := os.Getenv("MASTER_KEY")
	if masterKey == "" {
		log.Fatal("MASTER_KEY is required")
	}

	var err error
	db, err = sql.Open("postgres", databaseURL)
	if err != nil {
		log.Fatalf("Failed to connect to database: %v", err)
	}
	defer db.Close()

	db.SetMaxOpenConns(25)
	db.SetMaxIdleConns(5)
	db.SetConnMaxLifetime(5 * time.Minute)

	// Tentar conectar ao banco com retry
	maxRetries := 10
	var lastErr error
	for i := 0; i < maxRetries; i++ {
		err = db.Ping()
		if err == nil {
			log.Println("Connected to database successfully")
			break
		}
		lastErr = err
		log.Printf("Waiting for database... (%d/%d): %v", i+1, maxRetries, err)
		time.Sleep(5 * time.Second)
	}

	if lastErr != nil && err != nil {
		log.Fatalf("Failed to ping database after %d attempts: %v", maxRetries, lastErr)
	}

	mux := http.NewServeMux()

	mux.HandleFunc("/health", healthHandler)
	mux.HandleFunc("/validate", validateHandler)
	mux.HandleFunc("/admin/keys", adminKeysHandler(masterKey))

	log.Printf("Auth service starting on port %s", port)
	if err := http.ListenAndServe(":"+port, mux); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(HealthResponse{Status: "ok"})
}

func validateHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	apiKey := extractBearerToken(r)
	if apiKey == "" {
		http.Error(w, "Chave de API inválida ou inativa", http.StatusUnauthorized)
		return
	}

	keyHash := hashKey(apiKey)

	var id int
	err := db.QueryRow(
		"SELECT id FROM api_keys WHERE key_hash = $1 AND is_active = true",
		keyHash,
	).Scan(&id)

	if err != nil {
		http.Error(w, "Chave de API inválida ou inativa", http.StatusUnauthorized)
		return
	}

	_, _ = db.Exec(
		"UPDATE api_keys SET last_used_at = CURRENT_TIMESTAMP WHERE id = $1",
		id,
	)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(ValidateResponse{Message: "Chave válida"})
}

func adminKeysHandler(masterKey string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}

		token := extractBearerToken(r)
		if token != masterKey {
			http.Error(w, "Unauthorized: invalid master key", http.StatusUnauthorized)
			return
		}

		var req CreateKeyRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			http.Error(w, "Invalid request body", http.StatusBadRequest)
			return
		}

		if req.Name == "" {
			http.Error(w, "Name is required", http.StatusBadRequest)
			return
		}

		apiKey, err := generateAPIKey()
		if err != nil {
			log.Printf("Failed to generate API key: %v", err)
			http.Error(w, "Internal server error", http.StatusInternalServerError)
			return
		}

		keyHash := hashKey(apiKey)
		keyPrefix := apiKey[:16]

		_, err = db.Exec(
			"INSERT INTO api_keys (name, key_hash, key_prefix) VALUES ($1, $2, $3)",
			req.Name, keyHash, keyPrefix,
		)
		if err != nil {
			log.Printf("Failed to insert API key: %v", err)
			http.Error(w, "Internal server error", http.StatusInternalServerError)
			return
		}

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusCreated)
		json.NewEncoder(w).Encode(CreateKeyResponse{
			Name:    req.Name,
			Key:     apiKey,
			Message: "Guarde esta chave com segurança! Você não poderá vê-la novamente.",
		})
	}
}

func extractBearerToken(r *http.Request) string {
	auth := r.Header.Get("Authorization")
	if auth == "" {
		return ""
	}
	parts := strings.SplitN(auth, " ", 2)
	if len(parts) != 2 || !strings.EqualFold(parts[0], "Bearer") {
		return ""
	}
	return strings.TrimSpace(parts[1])
}

func generateAPIKey() (string, error) {
	bytes := make([]byte, 32)
	if _, err := rand.Read(bytes); err != nil {
		return "", fmt.Errorf("failed to generate random bytes: %w", err)
	}
	return "tm_key_" + hex.EncodeToString(bytes), nil
}

func hashKey(key string) string {
	hash := sha256.Sum256([]byte(key))
	return hex.EncodeToString(hash[:])
}
