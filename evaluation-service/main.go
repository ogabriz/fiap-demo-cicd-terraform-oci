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
	serviceApiKey := os.Getenv("SERVICE_API_KEY")

	if serviceApiKey == "" || serviceApiKey == "CHANGE_ME" {
		log.Println("AVISO: SERVICE_API_KEY não configurada ou com valor padrão. As chamadas aos outros serviços irão falhar (401).")
	}

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
	// Marcamos como pronto IMEDIATAMENTE para que o Kubernetes aceite o pod.
	// As conexões serão estabelecidas em segundo plano.
	if flagSvcURL != "" && targetingSvcURL != "" {
		app.IsReady = true
		log.Println("Serviço marcado como READY (inicializando dependências em background...)")
	}

	// 1. Cliente Redis com Retry Loop (em Goroutine)
	go func() {
		if redisURL != "" {
			opt, err := redis.ParseURL(redisURL)
			if err != nil {
				log.Printf("Erro ao parsear URL do Redis: %v", err)
				return
			}
			rdb := redis.NewClient(opt)
			maxRetries := 30
			for i := 0; i < maxRetries; i++ {
				if _, err := rdb.Ping(ctx).Result(); err == nil {
					app.RedisClient = rdb
					log.Println("Conexão com Redis estabelecida com sucesso!")
					return
				}
				log.Printf("Tentando conectar ao Redis (%d/%d)...", i+1, maxRetries)
				time.Sleep(5 * time.Second)
			}
			log.Println("Aviso: Não foi possível conectar ao Redis após 30 tentativas. O serviço continuará sem cache.")
		}
	}()

	// 2. Cliente OCI Queue (em Goroutine)
	go func() {
		if queueEndpoint != "" {
			var provider common.ConfigurationProvider
			var err error

			// Tenta Resource Principal (ideal para OKE com Workload Identity)
			provider, err = auth.ResourcePrincipalConfigurationProvider()
			if err != nil {
				log.Printf("Resource Principal não disponível, tentando Instance Principal: %v", err)
				// Fallback para Instance Principal (comum em workers OKE)
				provider, err = auth.InstancePrincipalConfigurationProvider()
				if err != nil {
					log.Printf("Instance Principal também não disponível, usando config default: %v", err)
					provider = common.DefaultConfigProvider()
				} else {
					log.Println("Usando Instance Principal para autenticação OCI")
				}
			} else {
				log.Println("Usando Resource Principal para autenticação OCI")
			}

			c, err := queue.NewQueueClientWithConfigurationProvider(provider)
			if err == nil {
				// No SDK v65, configuramos o Host diretamente. O Host deve ser apenas o domínio, sem https://
				if queueEndpoint != "" {
					host := queueEndpoint
					if len(host) > 8 && host[:8] == "https://" {
						host = host[8:]
					}
					c.Host = host
					log.Printf("OCI Queue Client configurado com Host: %s", host)
				}
				app.QueueClient = &c
				log.Printf("Cliente OCI Queue inicializado com sucesso.")
			} else {
				log.Printf("Erro ao criar cliente OCI Queue: %v", err)
			}
		}
	}()

	// Mantém o main rodando
	select {}
}
