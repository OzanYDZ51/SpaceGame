package handler

import (
	"context"
	"time"

	"spacegame-backend/internal/repository"
	"spacegame-backend/internal/service"

	"github.com/gofiber/fiber/v2"
)

type PublicHandler struct {
	playerRepo *repository.PlayerRepository
	corpRepo   *repository.CorporationRepository
	eventRepo  *repository.EventRepository
	wsHub      *service.WSHub
}

func NewPublicHandler(playerRepo *repository.PlayerRepository, corpRepo *repository.CorporationRepository, eventRepo *repository.EventRepository, wsHub *service.WSHub) *PublicHandler {
	return &PublicHandler{
		playerRepo: playerRepo,
		corpRepo:   corpRepo,
		eventRepo:  eventRepo,
		wsHub:      wsHub,
	}
}

func (h *PublicHandler) Stats(c *fiber.Ctx) error {
	ctx, cancel := context.WithTimeout(c.Context(), 3*time.Second)
	defer cancel()

	totalPlayers, _ := h.playerRepo.CountTotal(ctx)
	totalCorporations, _ := h.corpRepo.CountTotal(ctx)
	online := h.wsHub.OnlineCount()

	result := fiber.Map{
		"players_total":       totalPlayers,
		"players_online":      online,
		"corporations_total":  totalCorporations,
		"server_status":       "online",
	}

	// Try to fetch the last notable event (kill)
	events, err := h.eventRepo.ListByType(ctx, "kill", 1)
	if err == nil && len(events) > 0 {
		e := events[0]
		result["last_event"] = fiber.Map{
			"event_type":  e.EventType,
			"actor_name":  e.ActorName,
			"target_name": e.TargetName,
			"system_id":   e.SystemID,
			"created_at":  e.CreatedAt,
		}
	}

	return c.JSON(result)
}
