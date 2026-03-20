package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
)

type EvaluationResponse struct {
	FlagName string `json:"flag_name"`
	UserID   string `json:"user_id"`
	Result   bool   `json:"result"`
}

func (a *App) writeJSON(w http.ResponseWriter, data any) {
	if err := json.NewEncoder(w).Encode(data); err != nil {
		log.Printf("erro ao escrever JSON: %v", err)
	}
}

func (a *App) healthHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	status := "ok"
	code := http.StatusOK

	if !a.IsReady {
		status = "initializing"
		code = http.StatusServiceUnavailable
	}

	w.WriteHeader(code)
	a.writeJSON(w, map[string]string{
		"status": status,
		"redis":  fmt.Sprintf("%v", a.RedisClient != nil),
	})
}

func (a *App) evaluationHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	userID := r.URL.Query().Get("user_id")
	flagName := r.URL.Query().Get("flag_name")

	if userID == "" || flagName == "" {
		http.Error(w, `{"error": "user_id e flag_name são obrigatórios"}`, http.StatusBadRequest)
		return
	}

	result, err := a.getDecision(userID, flagName)
	if err != nil {
		if _, ok := err.(*NotFoundError); ok {
			result = false
		} else {
			http.Error(w, `{"error": "Erro interno"}`, http.StatusBadGateway)
			return
		}
	}

	go a.sendEvaluationEvent(userID, flagName, result)

	w.WriteHeader(http.StatusOK)
	a.writeJSON(w, EvaluationResponse{
		FlagName: flagName,
		UserID:   userID,
		Result:   result,
	})
}