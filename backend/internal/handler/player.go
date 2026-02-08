package handler

import (
	"spacegame-backend/internal/model"
	"spacegame-backend/internal/service"

	"github.com/gofiber/fiber/v2"
)

type PlayerHandler struct {
	playerSvc *service.PlayerService
}

func NewPlayerHandler(playerSvc *service.PlayerService) *PlayerHandler {
	return &PlayerHandler{playerSvc: playerSvc}
}

func (h *PlayerHandler) GetState(c *fiber.Ctx) error {
	playerID := c.Locals("player_id").(string)

	state, err := h.playerSvc.GetState(c.Context(), playerID)
	if err != nil {
		return c.Status(500).JSON(fiber.Map{"error": "failed to load player state"})
	}

	return c.JSON(state)
}

func (h *PlayerHandler) SaveState(c *fiber.Ctx) error {
	playerID := c.Locals("player_id").(string)

	var state model.PlayerState
	if err := c.BodyParser(&state); err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "invalid request body"})
	}

	if err := h.playerSvc.SaveState(c.Context(), playerID, &state); err != nil {
		return c.Status(500).JSON(fiber.Map{"error": "failed to save player state"})
	}

	return c.JSON(fiber.Map{"ok": true})
}

func (h *PlayerHandler) GetProfile(c *fiber.Ctx) error {
	profileID := c.Params("id")

	profile, err := h.playerSvc.GetProfile(c.Context(), profileID)
	if err != nil {
		return c.Status(404).JSON(fiber.Map{"error": "player not found"})
	}

	return c.JSON(profile)
}
