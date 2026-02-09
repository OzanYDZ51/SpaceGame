package handler

import (
	"spacegame-backend/internal/model"
	"spacegame-backend/internal/service"

	"github.com/gofiber/fiber/v2"
)

type EventHandler struct {
	eventSvc *service.EventService
}

func NewEventHandler(eventSvc *service.EventService) *EventHandler {
	return &EventHandler{eventSvc: eventSvc}
}

// RecordEvent receives a game event from the game server. (Server-key protected)
func (h *EventHandler) RecordEvent(c *fiber.Ctx) error {
	var req model.GameEventRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "invalid body"})
	}
	if req.Type == "" {
		return c.Status(400).JSON(fiber.Map{"error": "type required"})
	}

	ctx := c.Context()

	switch req.Type {
	case "kill":
		h.eventSvc.RecordKill(ctx, req.Killer, req.Victim, req.Weapon, req.System, req.SystemID)
	case "discovery":
		h.eventSvc.RecordDiscovery(ctx, req.ActorName, req.TargetName, req.System, req.SystemID)
	case "economy":
		details := ""
		if req.Details != nil {
			details = string(req.Details)
		}
		h.eventSvc.RecordEconomyEvent(ctx, req.Type, details)
	case "clan_created", "clan_deleted", "clan_alliance", "clan_war":
		details := ""
		if req.Details != nil {
			details = string(req.Details)
		}
		h.eventSvc.RecordClanEvent(ctx, req.Type, req.ActorName, details)
	default:
		return c.Status(400).JSON(fiber.Map{"error": "unknown event type: " + req.Type})
	}

	return c.JSON(fiber.Map{"status": "recorded"})
}
