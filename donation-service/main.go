package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/oracle/oci-go-sdk/v65/common"
	"github.com/oracle/oci-go-sdk/v65/common/auth"
	"github.com/oracle/oci-go-sdk/v65/queue"

	_ "github.com/jackc/pgx/v4/stdlib"
	"github.com/joho/godotenv"
)

type Donation struct {
	ID        int       `json:"id"`
	NgoID     int       `json:"ngo_id"`
	Amount    float64   `json:"amount"`
	DonorName string    `json:"donor_name"`
	Status    string    `json:"status"`
	CreatedAt time.Time `json:"created_at"`
}

type App struct {
	DB          *sql.DB
	QueueClient *queue.QueueClient
	QueueID     string
}

func getOCIConfigProvider() (common.ConfigurationProvider, error) {
	provider, err := auth.InstancePrincipalConfigurationProvider()
	if err == nil {
		return provider, nil
	}
	log.Println("Instance Principal indisponivel, usando config file (~/.oci/config)")
	return common.DefaultConfigProvider(), nil
}

func main() {
	_ = godotenv.Load()

	port := os.Getenv("PORT")
	if port == "" {
		port = "8082"
	}

	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		log.Fatal("DATABASE_URL e obrigatoria")
	}

	db, err := sql.Open("pgx", dbURL)
	if err != nil {
		log.Fatalf("Erro ao abrir conexao com banco de dados: %v", err)
	}

	for i := 1; i <= 30; i++ {
		if pingErr := db.Ping(); pingErr == nil {
			break
		} else if i == 30 {
			log.Fatalf("Erro ao conectar ao banco de dados apos 30 tentativas: %v", pingErr)
		} else {
			log.Printf("Tentativa %d/30 - aguardando banco de dados: %v", i, pingErr)
			time.Sleep(2 * time.Second)
		}
	}
	log.Println("Conectado ao PostgreSQL (donation-service).")

	var queueClient *queue.QueueClient
	queueID := os.Getenv("OCI_QUEUE_ID")
	queueEndpoint := os.Getenv("OCI_QUEUE_ENDPOINT")

	if queueID != "" && queueEndpoint != "" {
		provider, provErr := getOCIConfigProvider()
		if provErr != nil {
			log.Printf("Aviso: nao foi possivel configurar OCI auth: %v", provErr)
		} else {
			client, clientErr := queue.NewQueueClientWithConfigurationProvider(provider)
			if clientErr != nil {
				log.Printf("Aviso: nao foi possivel criar OCI Queue client: %v", clientErr)
			} else {
				client.Host = queueEndpoint
				queueClient = &client
				log.Println("Integracao com OCI Queue ativada.")
			}
		}
	}

	app := &App{DB: db, QueueClient: queueClient, QueueID: queueID}

	mux := http.NewServeMux()
	mux.HandleFunc("/health", app.HealthHandler)
	mux.HandleFunc("/donations", app.DonationHandler)

	log.Printf("donation-service rodando na porta %s", port)
	log.Fatal(http.ListenAndServe(":"+port, mux))
}

func (a *App) HealthHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte(`{"status":"ok","service":"donation-service"}`))
}

func (a *App) DonationHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	if r.Method == http.MethodPost {
		var d Donation
		if err := json.NewDecoder(r.Body).Decode(&d); err != nil {
			http.Error(w, `{"error":"Payload invalido"}`, http.StatusBadRequest)
			return
		}

		d.Status = "APPROVED"
		err := a.DB.QueryRow(
			"INSERT INTO donations (ngo_id, amount, donor_name, status) VALUES ($1, $2, $3, $4) RETURNING id, created_at",
			d.NgoID, d.Amount, d.DonorName, d.Status,
		).Scan(&d.ID, &d.CreatedAt)

		if err != nil {
			log.Printf("Erro ao salvar doacao: %v", err)
			http.Error(w, `{"error":"Erro interno"}`, http.StatusInternalServerError)
			return
		}

		if a.QueueClient != nil {
			go a.sendNotificationEvent(d)
		}

		w.WriteHeader(http.StatusCreated)
		_ = json.NewEncoder(w).Encode(d)
		return
	}

	if r.Method == http.MethodGet {
		rows, err := a.DB.Query("SELECT id, ngo_id, amount, donor_name, status, created_at FROM donations ORDER BY id DESC")
		if err != nil {
			http.Error(w, `{"error":"Erro interno"}`, http.StatusInternalServerError)
			return
		}
		defer rows.Close()

		donations := []Donation{}
		for rows.Next() {
			var d Donation
			_ = rows.Scan(&d.ID, &d.NgoID, &d.Amount, &d.DonorName, &d.Status, &d.CreatedAt)
			donations = append(donations, d)
		}

		_ = json.NewEncoder(w).Encode(donations)
		return
	}

	http.Error(w, `{"error":"Metodo nao permitido"}`, http.StatusMethodNotAllowed)
}

func (a *App) sendNotificationEvent(d Donation) {
	body, _ := json.Marshal(d)
	content := string(body)

	_, err := a.QueueClient.PutMessages(context.Background(), queue.PutMessagesRequest{
		QueueId: &a.QueueID,
		PutMessagesDetails: queue.PutMessagesDetails{
			Messages: []queue.PutMessagesDetailsEntry{
				{Content: &content},
			},
		},
	})
	if err != nil {
		log.Printf("Falha ao enviar mensagem para OCI Queue: %v", err)
	}
}


