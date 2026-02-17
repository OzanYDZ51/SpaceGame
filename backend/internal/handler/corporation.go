package handler

import (
	"errors"
	"log"
	"strconv"
	"strings"

	"spacegame-backend/internal/model"
	"spacegame-backend/internal/service"

	"github.com/gofiber/fiber/v2"
)

type CorporationHandler struct {
	corpSvc *service.CorporationService
}

func NewCorporationHandler(corpSvc *service.CorporationService) *CorporationHandler {
	return &CorporationHandler{corpSvc: corpSvc}
}

func (h *CorporationHandler) Create(c *fiber.Ctx) error {
	playerID := c.Locals("player_id").(string)

	var req model.CreateCorporationRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "invalid request body"})
	}

	if req.CorporationName == "" || req.CorporationTag == "" {
		return c.Status(400).JSON(fiber.Map{"error": "corporation_name and corporation_tag are required"})
	}

	corporation, err := h.corpSvc.Create(c.Context(), playerID, &req)
	if err != nil {
		return corporationError(c, err)
	}

	return c.Status(201).JSON(corporation)
}

func (h *CorporationHandler) Get(c *fiber.Ctx) error {
	corporationID := c.Params("id")

	corporation, err := h.corpSvc.Get(c.Context(), corporationID)
	if err != nil {
		return c.Status(404).JSON(fiber.Map{"error": "corporation not found"})
	}

	return c.JSON(corporation)
}

func (h *CorporationHandler) Search(c *fiber.Ctx) error {
	query := c.Query("q", "")
	corporations, err := h.corpSvc.Search(c.Context(), query)
	if err != nil {
		return c.Status(500).JSON(fiber.Map{"error": "search failed"})
	}
	if corporations == nil {
		corporations = []*model.Corporation{}
	}
	return c.JSON(corporations)
}

func (h *CorporationHandler) Update(c *fiber.Ctx) error {
	playerID := c.Locals("player_id").(string)
	corporationID := c.Params("id")

	var req model.UpdateCorporationRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "invalid request body"})
	}

	if err := h.corpSvc.Update(c.Context(), playerID, corporationID, &req); err != nil {
		return corporationError(c, err)
	}

	return c.JSON(fiber.Map{"ok": true})
}

func (h *CorporationHandler) Delete(c *fiber.Ctx) error {
	playerID := c.Locals("player_id").(string)
	corporationID := c.Params("id")

	if err := h.corpSvc.Delete(c.Context(), playerID, corporationID); err != nil {
		return corporationError(c, err)
	}

	return c.JSON(fiber.Map{"ok": true})
}

func (h *CorporationHandler) GetMembers(c *fiber.Ctx) error {
	corporationID := c.Params("id")

	members, err := h.corpSvc.GetMembers(c.Context(), corporationID)
	if err != nil {
		return c.Status(500).JSON(fiber.Map{"error": "failed to get members"})
	}
	if members == nil {
		members = []*model.CorporationMember{}
	}
	return c.JSON(members)
}

func (h *CorporationHandler) AddMember(c *fiber.Ctx) error {
	playerID := c.Locals("player_id").(string)
	corporationID := c.Params("id")

	var req model.AddMemberRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "invalid request body"})
	}

	if err := h.corpSvc.AddMember(c.Context(), playerID, corporationID, req.PlayerID); err != nil {
		return corporationError(c, err)
	}

	return c.Status(201).JSON(fiber.Map{"ok": true})
}

func (h *CorporationHandler) RemoveMember(c *fiber.Ctx) error {
	playerID := c.Locals("player_id").(string)
	corporationID := c.Params("id")
	targetID := c.Params("pid")

	if err := h.corpSvc.RemoveMember(c.Context(), playerID, corporationID, targetID); err != nil {
		return corporationError(c, err)
	}

	return c.JSON(fiber.Map{"ok": true})
}

func (h *CorporationHandler) SetMemberRank(c *fiber.Ctx) error {
	playerID := c.Locals("player_id").(string)
	corporationID := c.Params("id")
	targetID := c.Params("pid")

	var req model.SetRankRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "invalid request body"})
	}

	if err := h.corpSvc.SetMemberRank(c.Context(), playerID, corporationID, targetID, req.RankPriority); err != nil {
		return corporationError(c, err)
	}

	return c.JSON(fiber.Map{"ok": true})
}

func (h *CorporationHandler) Deposit(c *fiber.Ctx) error {
	playerID := c.Locals("player_id").(string)
	corporationID := c.Params("id")

	var req model.TreasuryRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "invalid request body"})
	}

	newBalance, err := h.corpSvc.Deposit(c.Context(), playerID, corporationID, req.Amount)
	if err != nil {
		return corporationError(c, err)
	}

	return c.JSON(fiber.Map{"treasury": newBalance})
}

func (h *CorporationHandler) Withdraw(c *fiber.Ctx) error {
	playerID := c.Locals("player_id").(string)
	corporationID := c.Params("id")

	var req model.TreasuryRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "invalid request body"})
	}

	newBalance, err := h.corpSvc.Withdraw(c.Context(), playerID, corporationID, req.Amount)
	if err != nil {
		return corporationError(c, err)
	}

	return c.JSON(fiber.Map{"treasury": newBalance})
}

func (h *CorporationHandler) GetActivity(c *fiber.Ctx) error {
	corporationID := c.Params("id")
	limit, _ := strconv.Atoi(c.Query("limit", "50"))

	activity, err := h.corpSvc.GetActivity(c.Context(), corporationID, limit)
	if err != nil {
		return c.Status(500).JSON(fiber.Map{"error": "failed to get activity"})
	}
	if activity == nil {
		activity = []*model.CorporationActivity{}
	}
	return c.JSON(activity)
}

func (h *CorporationHandler) GetDiplomacy(c *fiber.Ctx) error {
	corporationID := c.Params("id")

	diplomacy, err := h.corpSvc.GetDiplomacy(c.Context(), corporationID)
	if err != nil {
		return c.Status(500).JSON(fiber.Map{"error": "failed to get diplomacy"})
	}
	if diplomacy == nil {
		diplomacy = []*model.CorporationDiplomacy{}
	}
	return c.JSON(diplomacy)
}

func (h *CorporationHandler) SetDiplomacy(c *fiber.Ctx) error {
	playerID := c.Locals("player_id").(string)
	corporationID := c.Params("id")

	var req model.SetDiplomacyRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "invalid request body"})
	}

	if err := h.corpSvc.SetDiplomacy(c.Context(), playerID, corporationID, req.TargetCorporationID, req.Relation); err != nil {
		return corporationError(c, err)
	}

	return c.JSON(fiber.Map{"ok": true})
}

func (h *CorporationHandler) GetRanks(c *fiber.Ctx) error {
	corporationID := c.Params("id")

	ranks, err := h.corpSvc.GetRanks(c.Context(), corporationID)
	if err != nil {
		return c.Status(500).JSON(fiber.Map{"error": "failed to get ranks"})
	}
	if ranks == nil {
		ranks = []*model.CorporationRank{}
	}
	return c.JSON(ranks)
}

func (h *CorporationHandler) AddRank(c *fiber.Ctx) error {
	playerID := c.Locals("player_id").(string)
	corporationID := c.Params("id")

	var req model.CreateRankRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "invalid request body"})
	}

	if req.RankName == "" {
		return c.Status(400).JSON(fiber.Map{"error": "rank_name is required"})
	}

	rank, err := h.corpSvc.AddRank(c.Context(), playerID, corporationID, req.RankName, req.Priority, req.Permissions)
	if err != nil {
		return corporationError(c, err)
	}

	return c.Status(201).JSON(rank)
}

func (h *CorporationHandler) UpdateRank(c *fiber.Ctx) error {
	playerID := c.Locals("player_id").(string)
	corporationID := c.Params("id")
	rankID, err := strconv.ParseInt(c.Params("rid"), 10, 64)
	if err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "invalid rank id"})
	}

	var req model.UpdateRankRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "invalid request body"})
	}

	if err := h.corpSvc.UpdateRank(c.Context(), playerID, corporationID, rankID, req.RankName, req.Permissions); err != nil {
		return corporationError(c, err)
	}

	return c.JSON(fiber.Map{"ok": true})
}

func (h *CorporationHandler) RemoveRank(c *fiber.Ctx) error {
	playerID := c.Locals("player_id").(string)
	corporationID := c.Params("id")
	rankID, err := strconv.ParseInt(c.Params("rid"), 10, 64)
	if err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "invalid rank id"})
	}

	if err := h.corpSvc.RemoveRank(c.Context(), playerID, corporationID, rankID); err != nil {
		return corporationError(c, err)
	}

	return c.JSON(fiber.Map{"ok": true})
}

func corporationError(c *fiber.Ctx, err error) error {
	switch {
	case errors.Is(err, service.ErrCorporationNotFound):
		return c.Status(404).JSON(fiber.Map{"error": "corporation not found"})
	case errors.Is(err, service.ErrNotCorporationMember):
		return c.Status(403).JSON(fiber.Map{"error": "not a corporation member"})
	case errors.Is(err, service.ErrNotCorporationLeader):
		return c.Status(403).JSON(fiber.Map{"error": "insufficient permissions"})
	case errors.Is(err, service.ErrAlreadyInCorporation):
		return c.Status(409).JSON(fiber.Map{"error": "player is already in a corporation"})
	case errors.Is(err, service.ErrCorporationFull):
		return c.Status(409).JSON(fiber.Map{"error": "corporation is full"})
	case errors.Is(err, service.ErrInvalidAmount):
		return c.Status(400).JSON(fiber.Map{"error": "invalid amount"})
	case errors.Is(err, service.ErrInsufficientFunds):
		return c.Status(400).JSON(fiber.Map{"error": "insufficient funds"})
	default:
		errStr := err.Error()
		// Handle PostgreSQL unique constraint violations
		if strings.Contains(errStr, "duplicate key") || strings.Contains(errStr, "unique constraint") {
			if strings.Contains(errStr, "corporation_name") {
				return c.Status(409).JSON(fiber.Map{"error": "corporation name already taken"})
			}
			if strings.Contains(errStr, "corporation_tag") {
				return c.Status(409).JSON(fiber.Map{"error": "corporation tag already taken"})
			}
			return c.Status(409).JSON(fiber.Map{"error": "duplicate entry"})
		}
		log.Printf("[CORPORATION ERROR] %v", err)
		return c.Status(500).JSON(fiber.Map{"error": "internal server error"})
	}
}
