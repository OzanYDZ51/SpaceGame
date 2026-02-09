package handler

import (
	"fmt"

	"spacegame-backend/internal/model"
	"spacegame-backend/internal/service"

	"github.com/gofiber/fiber/v2"
)

type BugReportHandler struct {
	eventSvc *service.EventService
}

func NewBugReportHandler(eventSvc *service.EventService) *BugReportHandler {
	return &BugReportHandler{eventSvc: eventSvc}
}

// Submit receives a bug report from a player. (JWT protected)
func (h *BugReportHandler) Submit(c *fiber.Ctx) error {
	var req model.BugReportRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "invalid body"})
	}
	if req.Title == "" || req.Description == "" {
		return c.Status(400).JSON(fiber.Map{"error": "title and description required"})
	}
	if len(req.Title) > 100 {
		return c.Status(400).JSON(fiber.Map{"error": "title too long (max 100 chars)"})
	}
	if len(req.Description) > 2000 {
		return c.Status(400).JSON(fiber.Map{"error": "description too long (max 2000 chars)"})
	}

	username, _ := c.Locals("username").(string)
	system := "Inconnu"
	if req.SystemID > 0 {
		system = fmt.Sprintf("Système #%d", req.SystemID)
	}

	h.eventSvc.RecordBugReport(c.Context(), username, req.Title, req.Description, system, req.Position, req.SystemID, req.GameVersion, req.ScreenshotB64)

	return c.Status(201).JSON(fiber.Map{"status": "submitted"})
}
