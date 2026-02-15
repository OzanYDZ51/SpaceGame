package handler

import (
	"spacegame-backend/internal/model"
	"spacegame-backend/internal/repository"

	"github.com/gofiber/fiber/v2"
)

type FleetHandler struct {
	fleetRepo *repository.FleetRepository
}

func NewFleetHandler(fleetRepo *repository.FleetRepository) *FleetHandler {
	return &FleetHandler{fleetRepo: fleetRepo}
}

// GetDeployed returns all fleet ships with deployment_state=DEPLOYED across all players.
// GET /api/v1/server/fleet/deployed
func (h *FleetHandler) GetDeployed(c *fiber.Ctx) error {
	ships, err := h.fleetRepo.GetDeployedShips(c.Context())
	if err != nil {
		return c.Status(500).JSON(fiber.Map{"error": "failed to get deployed ships"})
	}
	if ships == nil {
		ships = []model.FleetShipDB{}
	}
	return c.JSON(fiber.Map{"ships": ships})
}

// SyncPositions batch-updates positions and health for deployed fleet ships.
// PUT /api/v1/server/fleet/sync
func (h *FleetHandler) SyncPositions(c *fiber.Ctx) error {
	var req struct {
		Updates []model.FleetSyncUpdate `json:"updates"`
	}
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "invalid request body"})
	}

	if err := h.fleetRepo.BatchUpdatePositions(c.Context(), req.Updates); err != nil {
		return c.Status(500).JSON(fiber.Map{"error": "failed to sync positions"})
	}

	return c.JSON(fiber.Map{"ok": true, "count": len(req.Updates)})
}

// ReportDeath marks a fleet ship as destroyed.
// POST /api/v1/server/fleet/death
func (h *FleetHandler) ReportDeath(c *fiber.Ctx) error {
	var req model.FleetDeathReport
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "invalid request body"})
	}

	if req.PlayerID == "" {
		return c.Status(400).JSON(fiber.Map{"error": "player_id is required"})
	}

	if err := h.fleetRepo.MarkDestroyed(c.Context(), req.PlayerID, req.FleetIndex); err != nil {
		return c.Status(500).JSON(fiber.Map{"error": "failed to mark destroyed"})
	}

	return c.JSON(fiber.Map{"ok": true})
}

// BulkUpsert inserts or updates fleet ships for a player (used by save system).
// PUT /api/v1/server/fleet/upsert
func (h *FleetHandler) BulkUpsert(c *fiber.Ctx) error {
	var req struct {
		Ships []model.FleetShipDB `json:"ships"`
	}
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "invalid request body"})
	}

	if err := h.fleetRepo.BulkUpsertFleetShips(c.Context(), req.Ships); err != nil {
		return c.Status(500).JSON(fiber.Map{"error": "failed to upsert fleet ships"})
	}

	return c.JSON(fiber.Map{"ok": true, "count": len(req.Ships)})
}
