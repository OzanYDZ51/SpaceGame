package handler

import (
	"encoding/json"

	"spacegame-backend/internal/model"
	"spacegame-backend/internal/repository"
	"spacegame-backend/internal/service"

	"github.com/gofiber/fiber/v2"
)

type AdminHandler struct {
	playerRepo *repository.PlayerRepository
	clanRepo   *repository.ClanRepository
	wsHub      *service.WSHub
}

func NewAdminHandler(playerRepo *repository.PlayerRepository, clanRepo *repository.ClanRepository, wsHub *service.WSHub) *AdminHandler {
	return &AdminHandler{playerRepo: playerRepo, clanRepo: clanRepo, wsHub: wsHub}
}

func (h *AdminHandler) Stats(c *fiber.Ctx) error {
	totalPlayers, _ := h.playerRepo.CountTotal(c.Context())
	totalClans, _ := h.clanRepo.CountTotal(c.Context())
	online := h.wsHub.OnlineCount()

	return c.JSON(fiber.Map{
		"players_total":  totalPlayers,
		"players_online": online,
		"clans_total":    totalClans,
	})
}

func (h *AdminHandler) Announce(c *fiber.Ctx) error {
	var req model.WSAnnounce
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "invalid request body"})
	}

	if req.Message == "" {
		return c.Status(400).JSON(fiber.Map{"error": "message is required"})
	}

	data, _ := json.Marshal(req)
	h.wsHub.Broadcast(&model.WSEvent{
		Type: "server:announce",
		Data: data,
	})

	return c.JSON(fiber.Map{"ok": true, "online": h.wsHub.OnlineCount()})
}
