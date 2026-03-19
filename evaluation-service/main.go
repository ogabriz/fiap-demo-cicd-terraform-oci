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
	IsReady             bool
}

func main() {
	_ = godotenv.Load() // Carrega .env para dev local

	// --- Configuração ---
	port := os.Getenv("PORT")
	if port == "" {
		port = "8004"
	}

	redisURL := os.Getenv("REDIS_URL")
	flagSvcURL := os.Getenv("FLAG_SERVICE_URL")
	targetingSvcURL := os.Getenv("TARGETING_SERVICE_URL")
	queueEndpoint := os.Getenv("OCI_QUEUE_ENDPOINT")
	queueID := os.Getenv("OCI_QUEUE_ID")

	// Cliente HTTP (com timeout)
	httpClient := &http.Client{
		Timeout: 5 * time.Second,
	}

	// Cria a instância da App (inicialmente não pronta)
	app := &App{
		HttpClient:          httpClient,
		FlagServiceURL:      flagSvcURL,
		TargetingServiceURL: targetingSvcURL,
		QueueID:             queueID,
		IsReady:             false,
	}

	// --- Rotas ---
	mux := http.NewServeMux()
	mux.HandleFunc("/health", app.healthHandler)
	mux.HandleFunc("/evaluate", app.evaluationHandler)

	// Inicia o servidor em uma goroutine para não bloquear a inicialização
	go func() {
		log.Printf("Serviço de Avaliação (Go) ouvindo na porta %s", port)
		if err := http.ListenAndServe(":"+port, mux); err != nil {
			log.Fatalf("Erro ao iniciar servidor HTTP: %v", err)
		}
	}()

	// --- Inicialização de Dependências em Background ---
	
	// 1. Cliente Redis com Retry Loop
	if redisURL != "" {
		opt, err := redis.ParseURL(redisURL)
		if err != nil {
			log.Printf("Erro ao parsear URL do Redis: %v", err)
		} else {
			rdb := redis.NewClient(opt)
			maxRetries := 20
			for i := 0; i < maxRetries; i++ {
				if _, err := rdb.Ping(ctx).Result(); err == nil {
					app.RedisClient = rdb
					log.Println("Conectado ao Redis com sucesso!")
					break
				}
				log.Printf("Tentando conectar ao Redis (%d/%d)...", i+1, maxRetries)
				time.Sleep(5 * time.Second)
			}
		}
	}

	// 2. Cliente OCI Queue
	if queueEndpoint != "" {
		var provider common.ConfigurationProvider
		var err error
		
		// Tenta usar Resource Principal (OKE), senão usa config default (local)
		provider, err = auth.ResourcePrincipalConfigurationProvider()
		if err != nil {
			log.Printf("Resource Principal não disponível, usando config default: %v", err)
			provider = common.DefaultConfigProvider()
		}

		// Tenta pegar a região do provider para logar
		if region, err := provider.Region(); err == nil {
			log.Printf("Região OCI detectada: %s", region)
		}

		c, err := queue.NewQueueClientWithConfigurationProvider(provider)
		if err == nil {
			// Define o endpoint da fila (cell endpoint)
			if queueEndpoint != "" {
				// O Host deve ser apenas o domínio, sem https://
				host := queueEndpoint
				if len(host) > 8 && host[:8] == "https://" {
					host = host[8:]
				}
				c.Host = host
				// No SDK v65, o Host é o campo correto para definir o endpoint do cliente
			}
			app.QueueClient = &c
			log.Printf("Cliente OCI Queue inicializado no endpoint: %s", queueEndpoint)
		} else {
			log.Printf("Erro ao criar cliente OCI Queue: %v", err)
		}
	}

	// Marca como pronto se as URLs obrigatórias estiverem presentes
	if flagSvcURL != "" && targetingSvcURL != "" {
		app.IsReady = true
		log.Println("Serviço pronto para processar requisições.")
		if app.RedisClient == nil {
			log.Println("Aviso: Redis não disponível, performance reduzida.")
		}
	} else {
		log.Println("ERRO: FLAG_SERVICE_URL ou TARGETING_SERVICE_URL ausentes. Serviço não ficará pronto.")
	}

	// Mantém o main rodando
	select {}
}
