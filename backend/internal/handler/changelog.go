package handler

import (
	"strconv"

	"spacegame-backend/internal/model"
	"spacegame-backend/internal/repository"
	"spacegame-backend/internal/service"

	"github.com/gofiber/fiber/v2"
)

type ChangelogHandler struct {
	repo     *repository.ChangelogRepository
	webhooks *service.DiscordWebhookService
}

func NewChangelogHandler(repo *repository.ChangelogRepository, webhooks *service.DiscordWebhookService) *ChangelogHandler {
	return &ChangelogHandler{repo: repo, webhooks: webhooks}
}

// Create stores a new changelog entry and sends it to Discord. (Admin-key protected)
func (h *ChangelogHandler) Create(c *fiber.Ctx) error {
	var req model.CreateChangelogRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "invalid body"})
	}
	if req.Version == "" || req.Summary == "" {
		return c.Status(400).JSON(fiber.Map{"error": "version and summary required"})
	}

	entry, err := h.repo.Create(c.Context(), req.Version, req.Summary, req.IsMajor)
	if err != nil {
		return c.Status(500).JSON(fiber.Map{"error": "failed to create changelog"})
	}

	// Fire-and-forget Discord webhook
	h.webhooks.SendDevlog(req.Version, req.Summary)

	return c.Status(201).JSON(entry)
}

// List returns recent changelog entries. (Public)
func (h *ChangelogHandler) List(c *fiber.Ctx) error {
	limit, _ := strconv.Atoi(c.Query("limit", "20"))
	entries, err := h.repo.List(c.Context(), limit)
	if err != nil {
		return c.Status(500).JSON(fiber.Map{"error": "failed to list changelogs"})
	}
	if entries == nil {
		entries = []model.Changelog{}
	}
	return c.JSON(entries)
}
