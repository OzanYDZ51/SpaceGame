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
	clanRepo   *repository.ClanRepository
	eventRepo  *repository.EventRepository
	wsHub      *service.WSHub
}

func NewPublicHandler(playerRepo *repository.PlayerRepository, clanRepo *repository.ClanRepository, eventRepo *repository.EventRepository, wsHub *service.WSHub) *PublicHandler {
	return &PublicHandler{
		playerRepo: playerRepo,
		clanRepo:   clanRepo,
		eventRepo:  eventRepo,
		wsHub:      wsHub,
	}
}

func (h *PublicHandler) Stats(c *fiber.Ctx) error {
	ctx, cancel := context.WithTimeout(c.Context(), 3*time.Second)
	defer cancel()

	totalPlayers, _ := h.playerRepo.CountTotal(ctx)
	totalClans, _ := h.clanRepo.CountTotal(ctx)
	online := h.wsHub.OnlineCount()

	result := fiber.Map{
		"players_total":  totalPlayers,
		"players_online": online,
		"clans_total":    totalClans,
		"server_status":  "online",
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
