package main

import (
	"context"
	"encoding/json"
	"log"
	"time"

	"github.com/oracle/oci-go-sdk/v65/common"
	"github.com/oracle/oci-go-sdk/v65/queue"
)

// Evento que será enviado para a fila
type EvaluationEvent struct {
	UserID    string    `json:"user_id"`
	FlagName  string    `json:"flag_name"`
	Result    bool      `json:"result"`
	Timestamp time.Time `json:"timestamp"`
}

// sendEvaluationEvent envia um evento para a fila OCI Queue
func (a *App) sendEvaluationEvent(userID, flagName string, result bool) {
	// Se o cliente ou ID da fila não foram configurados, apenas loga localmente e sai.
	if a.QueueClient == nil || a.QueueID == "" {
		log.Printf("[QUEUE_DISABLED] Evento: User '%s', Flag '%s', Result '%t'", userID, flagName, result)
		return
	}

	event := EvaluationEvent{
		UserID:    userID,
		FlagName:  flagName,
		Result:    result,
		Timestamp: time.Now().UTC(),
	}

	body, err := json.Marshal(event)
	if err != nil {
		log.Printf("Erro ao serializar evento OCI Queue: %v", err)
		return
	}

	// Executa o envio (deve ser chamado com 'go' pelo chamador para ser assíncrono)
	defer func() {
		if r := recover(); r != nil {
			log.Printf("Panic detectado no envio para fila: %v", r)
		}
	}()

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	log.Printf("Tentando enviar evento para fila %s no endpoint %s...", a.QueueID, a.QueueClient.Host)

	_, err = a.QueueClient.PutMessages(ctx, queue.PutMessagesRequest{
		QueueId: common.String(a.QueueID),
		PutMessagesDetails: queue.PutMessagesDetails{
			Messages: []queue.PutMessagesDetailsEntry{
				{
					Content: common.String(string(body)),
				},
			},
		},
	})

	if err != nil {
		log.Printf("Erro ao enviar mensagem para OCI Queue (%s): %v", a.QueueID, err)
	} else {
		log.Printf("Evento de avaliação enviado com sucesso para OCI Queue (Flag: %s)", flagName)
	}
}
