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

type ClanHandler struct {
	clanSvc *service.ClanService
}

func NewClanHandler(clanSvc *service.ClanService) *ClanHandler {
	return &ClanHandler{clanSvc: clanSvc}
}

func (h *ClanHandler) Create(c *fiber.Ctx) error {
	playerID := c.Locals("player_id").(string)

	var req model.CreateClanRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "invalid request body"})
	}

	if req.ClanName == "" || req.ClanTag == "" {
		return c.Status(400).JSON(fiber.Map{"error": "clan_name and clan_tag are required"})
	}

	clan, err := h.clanSvc.Create(c.Context(), playerID, &req)
	if err != nil {
		return clanError(c, err)
	}

	return c.Status(201).JSON(clan)
}

func (h *ClanHandler) Get(c *fiber.Ctx) error {
	clanID := c.Params("id")

	clan, err := h.clanSvc.Get(c.Context(), clanID)
	if err != nil {
		return c.Status(404).JSON(fiber.Map{"error": "clan not found"})
	}

	return c.JSON(clan)
}

func (h *ClanHandler) Search(c *fiber.Ctx) error {
	query := c.Query("q", "")
	clans, err := h.clanSvc.Search(c.Context(), query)
	if err != nil {
		return c.Status(500).JSON(fiber.Map{"error": "search failed"})
	}
	if clans == nil {
		clans = []*model.Clan{}
	}
	return c.JSON(clans)
}

func (h *ClanHandler) Update(c *fiber.Ctx) error {
	playerID := c.Locals("player_id").(string)
	clanID := c.Params("id")

	var req model.UpdateClanRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "invalid request body"})
	}

	if err := h.clanSvc.Update(c.Context(), playerID, clanID, &req); err != nil {
		return clanError(c, err)
	}

	return c.JSON(fiber.Map{"ok": true})
}

func (h *ClanHandler) Delete(c *fiber.Ctx) error {
	playerID := c.Locals("player_id").(string)
	clanID := c.Params("id")

	if err := h.clanSvc.Delete(c.Context(), playerID, clanID); err != nil {
		return clanError(c, err)
	}

	return c.JSON(fiber.Map{"ok": true})
}

func (h *ClanHandler) GetMembers(c *fiber.Ctx) error {
	clanID := c.Params("id")

	members, err := h.clanSvc.GetMembers(c.Context(), clanID)
	if err != nil {
		return c.Status(500).JSON(fiber.Map{"error": "failed to get members"})
	}
	if members == nil {
		members = []*model.ClanMember{}
	}
	return c.JSON(members)
}

func (h *ClanHandler) AddMember(c *fiber.Ctx) error {
	playerID := c.Locals("player_id").(string)
	clanID := c.Params("id")

	var req model.AddMemberRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "invalid request body"})
	}

	if err := h.clanSvc.AddMember(c.Context(), playerID, clanID, req.PlayerID); err != nil {
		return clanError(c, err)
	}

	return c.Status(201).JSON(fiber.Map{"ok": true})
}

func (h *ClanHandler) RemoveMember(c *fiber.Ctx) error {
	playerID := c.Locals("player_id").(string)
	clanID := c.Params("id")
	targetID := c.Params("pid")

	if err := h.clanSvc.RemoveMember(c.Context(), playerID, clanID, targetID); err != nil {
		return clanError(c, err)
	}

	return c.JSON(fiber.Map{"ok": true})
}

func (h *ClanHandler) SetMemberRank(c *fiber.Ctx) error {
	playerID := c.Locals("player_id").(string)
	clanID := c.Params("id")
	targetID := c.Params("pid")

	var req model.SetRankRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "invalid request body"})
	}

	if err := h.clanSvc.SetMemberRank(c.Context(), playerID, clanID, targetID, req.RankPriority); err != nil {
		return clanError(c, err)
	}

	return c.JSON(fiber.Map{"ok": true})
}

func (h *ClanHandler) Deposit(c *fiber.Ctx) error {
	playerID := c.Locals("player_id").(string)
	clanID := c.Params("id")

	var req model.TreasuryRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "invalid request body"})
	}

	newBalance, err := h.clanSvc.Deposit(c.Context(), playerID, clanID, req.Amount)
	if err != nil {
		return clanError(c, err)
	}

	return c.JSON(fiber.Map{"treasury": newBalance})
}

func (h *ClanHandler) Withdraw(c *fiber.Ctx) error {
	playerID := c.Locals("player_id").(string)
	clanID := c.Params("id")

	var req model.TreasuryRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "invalid request body"})
	}

	newBalance, err := h.clanSvc.Withdraw(c.Context(), playerID, clanID, req.Amount)
	if err != nil {
		return clanError(c, err)
	}

	return c.JSON(fiber.Map{"treasury": newBalance})
}

func (h *ClanHandler) GetActivity(c *fiber.Ctx) error {
	clanID := c.Params("id")
	limit, _ := strconv.Atoi(c.Query("limit", "50"))

	activity, err := h.clanSvc.GetActivity(c.Context(), clanID, limit)
	if err != nil {
		return c.Status(500).JSON(fiber.Map{"error": "failed to get activity"})
	}
	if activity == nil {
		activity = []*model.ClanActivity{}
	}
	return c.JSON(activity)
}

func (h *ClanHandler) GetDiplomacy(c *fiber.Ctx) error {
	clanID := c.Params("id")

	diplomacy, err := h.clanSvc.GetDiplomacy(c.Context(), clanID)
	if err != nil {
		return c.Status(500).JSON(fiber.Map{"error": "failed to get diplomacy"})
	}
	if diplomacy == nil {
		diplomacy = []*model.ClanDiplomacy{}
	}
	return c.JSON(diplomacy)
}

func (h *ClanHandler) SetDiplomacy(c *fiber.Ctx) error {
	playerID := c.Locals("player_id").(string)
	clanID := c.Params("id")

	var req model.SetDiplomacyRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "invalid request body"})
	}

	if err := h.clanSvc.SetDiplomacy(c.Context(), playerID, clanID, req.TargetClanID, req.Relation); err != nil {
		return clanError(c, err)
	}

	return c.JSON(fiber.Map{"ok": true})
}

func (h *ClanHandler) GetRanks(c *fiber.Ctx) error {
	clanID := c.Params("id")

	ranks, err := h.clanSvc.GetRanks(c.Context(), clanID)
	if err != nil {
		return c.Status(500).JSON(fiber.Map{"error": "failed to get ranks"})
	}
	if ranks == nil {
		ranks = []*model.ClanRank{}
	}
	return c.JSON(ranks)
}

func (h *ClanHandler) AddRank(c *fiber.Ctx) error {
	playerID := c.Locals("player_id").(string)
	clanID := c.Params("id")

	var req model.CreateRankRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "invalid request body"})
	}

	if req.RankName == "" {
		return c.Status(400).JSON(fiber.Map{"error": "rank_name is required"})
	}

	rank, err := h.clanSvc.AddRank(c.Context(), playerID, clanID, req.RankName, req.Priority, req.Permissions)
	if err != nil {
		return clanError(c, err)
	}

	return c.Status(201).JSON(rank)
}

func (h *ClanHandler) UpdateRank(c *fiber.Ctx) error {
	playerID := c.Locals("player_id").(string)
	clanID := c.Params("id")
	rankID, err := strconv.ParseInt(c.Params("rid"), 10, 64)
	if err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "invalid rank id"})
	}

	var req model.UpdateRankRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "invalid request body"})
	}

	if err := h.clanSvc.UpdateRank(c.Context(), playerID, clanID, rankID, req.RankName, req.Permissions); err != nil {
		return clanError(c, err)
	}

	return c.JSON(fiber.Map{"ok": true})
}

func (h *ClanHandler) RemoveRank(c *fiber.Ctx) error {
	playerID := c.Locals("player_id").(string)
	clanID := c.Params("id")
	rankID, err := strconv.ParseInt(c.Params("rid"), 10, 64)
	if err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "invalid rank id"})
	}

	if err := h.clanSvc.RemoveRank(c.Context(), playerID, clanID, rankID); err != nil {
		return clanError(c, err)
	}

	return c.JSON(fiber.Map{"ok": true})
}

func clanError(c *fiber.Ctx, err error) error {
	switch {
	case errors.Is(err, service.ErrClanNotFound):
		return c.Status(404).JSON(fiber.Map{"error": "clan not found"})
	case errors.Is(err, service.ErrNotClanMember):
		return c.Status(403).JSON(fiber.Map{"error": "not a clan member"})
	case errors.Is(err, service.ErrNotClanLeader):
		return c.Status(403).JSON(fiber.Map{"error": "insufficient permissions"})
	case errors.Is(err, service.ErrAlreadyInClan):
		return c.Status(409).JSON(fiber.Map{"error": "player is already in a clan"})
	case errors.Is(err, service.ErrClanFull):
		return c.Status(409).JSON(fiber.Map{"error": "clan is full"})
	case errors.Is(err, service.ErrInvalidAmount):
		return c.Status(400).JSON(fiber.Map{"error": "invalid amount"})
	case errors.Is(err, service.ErrInsufficientFunds):
		return c.Status(400).JSON(fiber.Map{"error": "insufficient funds"})
	default:
		errStr := err.Error()
		// Handle PostgreSQL unique constraint violations
		if strings.Contains(errStr, "duplicate key") || strings.Contains(errStr, "unique constraint") {
			if strings.Contains(errStr, "clan_name") {
				return c.Status(409).JSON(fiber.Map{"error": "clan name already taken"})
			}
			if strings.Contains(errStr, "clan_tag") {
				return c.Status(409).JSON(fiber.Map{"error": "clan tag already taken"})
			}
			return c.Status(409).JSON(fiber.Map{"error": "duplicate entry"})
		}
		log.Printf("[CLAN ERROR] %v", err)
		return c.Status(500).JSON(fiber.Map{"error": "internal server error"})
	}
}
