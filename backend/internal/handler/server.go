package handler

import (
	"spacegame-backend/internal/model"
	"spacegame-backend/internal/repository"
	"spacegame-backend/internal/service"

	"github.com/gofiber/fiber/v2"
)

type ServerHandler struct {
	authSvc    *service.AuthService
	playerSvc  *service.PlayerService
	playerRepo *repository.PlayerRepository
}

func NewServerHandler(authSvc *service.AuthService, playerSvc *service.PlayerService, playerRepo *repository.PlayerRepository) *ServerHandler {
	return &ServerHandler{authSvc: authSvc, playerSvc: playerSvc, playerRepo: playerRepo}
}

// ValidateToken is called by the game server when a player connects via ENet
func (h *ServerHandler) ValidateToken(c *fiber.Ctx) error {
	var req model.ValidateTokenRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "invalid request body"})
	}

	playerID, username, role, err := h.authSvc.ValidateAccessToken(req.Token)
	if err != nil {
		return c.JSON(model.ValidateTokenResponse{Valid: false})
	}

	return c.JSON(model.ValidateTokenResponse{
		Valid:    true,
		PlayerID: playerID,
		Username: username,
		Role:     role,
	})
}

// SaveState is called by the game server to save player state on disconnect
func (h *ServerHandler) SaveState(c *fiber.Ctx) error {
	type request struct {
		PlayerID string            `json:"player_id"`
		State    model.PlayerState `json:"state"`
	}

	var req request
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "invalid request body"})
	}

	if req.PlayerID == "" {
		return c.Status(400).JSON(fiber.Map{"error": "player_id is required"})
	}

	if err := h.playerSvc.SaveState(c.Context(), req.PlayerID, &req.State); err != nil {
		return c.Status(500).JSON(fiber.Map{"error": "failed to save state"})
	}

	return c.JSON(fiber.Map{"ok": true})
}

// Heartbeat is called periodically by the game server to update last_seen_at for connected players
func (h *ServerHandler) Heartbeat(c *fiber.Ctx) error {
	type request struct {
		PlayerIDs []string `json:"player_ids"`
	}

	var req request
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "invalid request body"})
	}

	if len(req.PlayerIDs) == 0 {
		return c.JSON(fiber.Map{"ok": true})
	}

	if err := h.playerRepo.UpdateLastSeen(c.Context(), req.PlayerIDs); err != nil {
		return c.Status(500).JSON(fiber.Map{"error": "failed to update last seen"})
	}

	return c.JSON(fiber.Map{"ok": true})
}
