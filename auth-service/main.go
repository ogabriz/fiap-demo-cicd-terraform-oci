package main

import (
	"context"
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
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
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

	// OpenTelemetry init.
	shutdown := initTracer()
	defer func() {
		if err := shutdown(context.Background()); err != nil {
			log.Printf("Error shutting down tracer: %v", err)
		}
	}()

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

	if err := initDatabase(db); err != nil {
		log.Fatalf("Failed to initialize database: %v", err)
	}

	mux := http.NewServeMux()
	mux.Handle("/health", otelhttp.NewHandler(http.HandlerFunc(healthHandler), "health"))
	mux.Handle("/health/db", otelhttp.NewHandler(http.HandlerFunc(dbHealthHandler), "db-health"))
	mux.Handle("/validate", otelhttp.NewHandler(http.HandlerFunc(validateHandler), "validate"))
	mux.Handle("/admin/keys", otelhttp.NewHandler(http.HandlerFunc(adminKeysHandler(masterKey)), "admin-keys"))

	log.Printf("Auth service starting on port %s", port)
	if err := http.ListenAndServe(":"+port, mux); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}

func initDatabase(db *sql.DB) error {
	schema := `
    CREATE TABLE IF NOT EXISTS api_keys (
        id SERIAL PRIMARY KEY,
        name VARCHAR(255) NOT NULL,
        key_hash VARCHAR(255) NOT NULL UNIQUE,
        key_prefix VARCHAR(20) NOT NULL,
        is_active BOOLEAN DEFAULT TRUE,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        last_used_at TIMESTAMP
    );
    `

	_, err := db.Exec(schema)
	if err != nil {
		return fmt.Errorf("failed to execute schema: %w", err)
	}

	return nil
}

func writeJSON(w http.ResponseWriter, data any) {
	if err := json.NewEncoder(w).Encode(data); err != nil {
		log.Printf("erro ao escrever JSON: %v", err)
	}
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	writeJSON(w, HealthResponse{Status: "ok"})
}

func dbHealthHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	w.Header().Set("Content-Type", "application/json")

	if err := db.Ping(); err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		writeJSON(w, map[string]string{
			"status": "error",
			"error":  fmt.Sprintf("Database connection failed: %v", err),
		})
		return
	}

	var count int
	if err := db.QueryRow("SELECT COUNT(*) FROM api_keys").Scan(&count); err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		writeJSON(w, map[string]string{
			"status": "error",
			"error":  fmt.Sprintf("Query failed: %v", err),
		})
		return
	}

	writeJSON(w, map[string]interface{}{
		"status":    "ok",
		"db_ping":   "success",
		"key_count": count,
	})
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

	var keyID int
	err := db.QueryRow(
		"SELECT id FROM api_keys WHERE key_hash = $1 AND is_active = true",
		keyHash,
	).Scan(&keyID)

	if err != nil {
		http.Error(w, "Chave de API inválida ou inativa", http.StatusUnauthorized)
		return
	}

	_, _ = db.Exec(
		"UPDATE api_keys SET last_used_at = CURRENT_TIMESTAMP WHERE id = $1",
		keyID,
	)

	w.Header().Set("Content-Type", "application/json")
	writeJSON(w, ValidateResponse{Message: "Chave válida"})
}

func adminKeysHandler(masterKey string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}

		token := extractBearerToken(r)
		if token != masterKey {
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}

		var req CreateKeyRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			http.Error(w, "Invalid body", http.StatusBadRequest)
			return
		}

		apiKey, err := generateAPIKey()
		if err != nil {
			http.Error(w, "Internal error", http.StatusInternalServerError)
			return
		}

		keyHash := hashKey(apiKey)
		keyPrefix := apiKey[:16]

		_, err = db.Exec(
			"INSERT INTO api_keys (name, key_hash, key_prefix) VALUES ($1, $2, $3)",
			req.Name, keyHash, keyPrefix,
		)
		if err != nil {
			http.Error(w, "Internal error", http.StatusInternalServerError)
			return
		}

		w.WriteHeader(http.StatusCreated)
		writeJSON(w, CreateKeyResponse{
			Name:    req.Name,
			Key:     apiKey,
			Message: "Guarde esta chave com segurança!",
		})
	}
}

// utils

func extractBearerToken(r *http.Request) string {
	auth := r.Header.Get("Authorization")
	parts := strings.SplitN(auth, " ", 2)
	if len(parts) != 2 {
		return ""
	}
	return strings.TrimSpace(parts[1])
}

func generateAPIKey() (string, error) {
	randomBytes := make([]byte, 32)
	_, err := rand.Read(randomBytes)
	return "tm_key_" + hex.EncodeToString(randomBytes), err
}

func hashKey(key string) string {
	hash := sha256.Sum256([]byte(key))
	return hex.EncodeToString(hash[:])
}
