package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/go-redis/redis/v8"
	"github.com/joho/godotenv"
	"github.com/oracle/oci-go-sdk/v65/common"
	"github.com/oracle/oci-go-sdk/v65/common/auth"
	"github.com/oracle/oci-go-sdk/v65/queue"
)

// Contexto global para o Redis
var ctx = context.Background()

// App struct para injeção de dependência
type App struct {
	RedisClient         *redis.Client
	QueueClient         *queue.QueueClient
	QueueID             string
	HttpClient          *http.Client
	FlagServiceURL      string
	TargetingServiceURL string
}

func main() {
	_ = godotenv.Load() // Carrega .env para dev local

	// --- Configuração ---
	port := os.Getenv("PORT")
	if port == "" {
		port = "8004"
	}

	redisURL := os.Getenv("REDIS_URL")
	if redisURL == "" {
		log.Fatal("REDIS_URL deve ser definida (ex: redis://localhost:6379)")
	}

	flagSvcURL := os.Getenv("FLAG_SERVICE_URL")
	if flagSvcURL == "" {
		log.Fatal("FLAG_SERVICE_URL deve ser definida")
	}

	targetingSvcURL := os.Getenv("TARGETING_SERVICE_URL")
	if targetingSvcURL == "" {
		log.Fatal("TARGETING_SERVICE_URL deve ser definida")
	}

	// OCI Queue Config
	queueEndpoint := os.Getenv("OCI_QUEUE_ENDPOINT")
	queueID := os.Getenv("OCI_QUEUE_ID")
	
	if queueEndpoint == "" {
		log.Println("Atenção: OCI_QUEUE_ENDPOINT não definida. Eventos não serão enviados.")
	}

	// --- Inicializa Clientes ---
	
	// Cliente Redis com Retry Loop
	opt, err := redis.ParseURL(redisURL)
	if err != nil {
		log.Fatalf("Não foi possível parsear a URL do Redis: %v", err)
	}
	rdb := redis.NewClient(opt)

	// Tenta conectar ao Redis por até 1 minuto
	maxRetries := 12
	connected := false
	for i := 0; i < maxRetries; i++ {
		if _, err := rdb.Ping(ctx).Result(); err == nil {
			connected = true
			break
		}
		log.Printf("Tentando conectar ao Redis (%d/%d)...", i+1, maxRetries)
		time.Sleep(5 * time.Second)
	}

	if !connected {
		log.Fatal("Não foi possível conectar ao Redis após várias tentativas.")
	}
	log.Println("Conectado ao Redis com sucesso!")

	// Cliente OCI Queue
	var queueClient *queue.QueueClient
	if queueEndpoint != "" {
		var provider common.ConfigurationProvider
		
		// Tenta usar Resource Principal (OKE), senão usa config default (local)
		provider, err = auth.ResourcePrincipalConfigurationProvider()
		if err != nil {
			log.Printf("Resource Principal não disponível, usando config default: %v", err)
			provider = common.DefaultConfigProvider()
		}

		c, err := queue.NewQueueClientWithConfigurationProvider(provider)
		if err != nil {
			log.Fatalf("Erro ao criar cliente OCI Queue: %v", err)
		}
		
		// O endpoint deve ser o da "Queue Message" API (cell endpoint)
		c.Host = queueEndpoint
		queueClient = &c
		log.Println("Cliente OCI Queue inicializado com sucesso.")
	}

	// Cliente HTTP (com timeout)
	httpClient := &http.Client{
		Timeout: 5 * time.Second,
	}

	// Cria a instância da App
	app := &App{
		RedisClient:         rdb,
		QueueClient:         queueClient,
		QueueID:             queueID,
		HttpClient:          httpClient,
		FlagServiceURL:      flagSvcURL,
		TargetingServiceURL: targetingSvcURL,
	}

	// --- Rotas ---
	mux := http.NewServeMux()
	mux.HandleFunc("/health", app.healthHandler)
	mux.HandleFunc("/evaluate", app.evaluationHandler)

	log.Printf("Serviço de Avaliação (Go) rodando na porta %s", port)
	if err := http.ListenAndServe(":"+port, mux); err != nil {
		log.Fatal(err)
	}
}
