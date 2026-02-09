package handler

import (
	"spacegame-backend/internal/model"
	"spacegame-backend/internal/repository"

	"github.com/gofiber/fiber/v2"
)

type DiscordHandler struct {
	discordRepo *repository.DiscordRepository
}

func NewDiscordHandler(discordRepo *repository.DiscordRepository) *DiscordHandler {
	return &DiscordHandler{discordRepo: discordRepo}
}

// ConfirmLink confirms a Discord link code submitted by a player. (JWT protected)
func (h *DiscordHandler) ConfirmLink(c *fiber.Ctx) error {
	var req model.DiscordLinkRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "invalid body"})
	}
	if req.Code == "" {
		return c.Status(400).JSON(fiber.Map{"error": "code required"})
	}

	playerID, _ := c.Locals("playerID").(string)

	if err := h.discordRepo.ConfirmLinkCode(c.Context(), playerID, req.Code); err != nil {
		return c.Status(400).JSON(fiber.Map{"error": err.Error()})
	}

	return c.JSON(fiber.Map{"status": "linked"})
}

// GetStatus returns whether the player's Discord account is linked. (JWT protected)
func (h *DiscordHandler) GetStatus(c *fiber.Ctx) error {
	playerID, _ := c.Locals("playerID").(string)

	discordID, err := h.discordRepo.GetDiscordID(c.Context(), playerID)
	if err != nil {
		return c.Status(500).JSON(fiber.Map{"error": "failed to check status"})
	}

	return c.JSON(model.DiscordLinkStatus{
		Linked:    discordID != "",
		DiscordID: discordID,
	})
}
