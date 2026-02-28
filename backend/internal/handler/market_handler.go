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

type MarketHandler struct {
	marketSvc *service.MarketService
}

func NewMarketHandler(marketSvc *service.MarketService) *MarketHandler {
	return &MarketHandler{marketSvc: marketSvc}
}

// GET /api/v1/market/listings
func (h *MarketHandler) Search(c *fiber.Ctx) error {
	req := &model.SearchListingsRequest{
		Category:   c.Query("category", ""),
		SearchText: c.Query("search", ""),
		SortBy:     c.Query("sort_by", "newest"),
	}

	if limitStr := c.Query("limit"); limitStr != "" {
		if v, err := strconv.Atoi(limitStr); err == nil {
			req.Limit = v
		}
	}
	if offsetStr := c.Query("offset"); offsetStr != "" {
		if v, err := strconv.Atoi(offsetStr); err == nil {
			req.Offset = v
		}
	}
	if sysStr := c.Query("system_id"); sysStr != "" {
		if v, err := strconv.Atoi(sysStr); err == nil {
			req.SystemID = &v
		}
	}
	if minStr := c.Query("min_price"); minStr != "" {
		if v, err := strconv.ParseInt(minStr, 10, 64); err == nil {
			req.MinPrice = &v
		}
	}
	if maxStr := c.Query("max_price"); maxStr != "" {
		if v, err := strconv.ParseInt(maxStr, 10, 64); err == nil {
			req.MaxPrice = &v
		}
	}

	listings, total, err := h.marketSvc.SearchListings(c.Context(), req)
	if err != nil {
		log.Printf("[MARKET] search error: %v", err)
		return c.Status(500).JSON(fiber.Map{"error": "failed to search listings"})
	}

	return c.JSON(fiber.Map{
		"listings": listings,
		"total":    total,
	})
}

// POST /api/v1/market/listings
func (h *MarketHandler) Create(c *fiber.Ctx) error {
	playerID := c.Locals("player_id").(string)
	playerName := c.Locals("username").(string)

	var req model.CreateListingRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "invalid request body"})
	}

	if req.ItemID == "" || req.ItemName == "" || req.ItemCategory == "" {
		return c.Status(400).JSON(fiber.Map{"error": "item_id, item_name, and item_category are required"})
	}

	listing, err := h.marketSvc.CreateListing(c.Context(), playerID, playerName, &req)
	if err != nil {
		return marketError(c, err)
	}

	return c.Status(201).JSON(listing)
}

// GET /api/v1/market/listings/:id
func (h *MarketHandler) GetByID(c *fiber.Ctx) error {
	id, err := strconv.ParseInt(c.Params("id"), 10, 64)
	if err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "invalid listing id"})
	}

	listing, err := h.marketSvc.GetListing(c.Context(), id)
	if err != nil {
		return marketError(c, err)
	}

	return c.JSON(listing)
}

// POST /api/v1/market/listings/:id/buy
func (h *MarketHandler) Buy(c *fiber.Ctx) error {
	playerID := c.Locals("player_id").(string)
	playerName := c.Locals("username").(string)

	id, err := strconv.ParseInt(c.Params("id"), 10, 64)
	if err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "invalid listing id"})
	}

	listing, err := h.marketSvc.BuyListing(c.Context(), id, playerID, playerName)
	if err != nil {
		return marketError(c, err)
	}

	return c.JSON(listing)
}

// DELETE /api/v1/market/listings/:id
func (h *MarketHandler) Cancel(c *fiber.Ctx) error {
	playerID := c.Locals("player_id").(string)

	id, err := strconv.ParseInt(c.Params("id"), 10, 64)
	if err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "invalid listing id"})
	}

	if err := h.marketSvc.CancelListing(c.Context(), id, playerID); err != nil {
		return marketError(c, err)
	}

	return c.JSON(fiber.Map{"ok": true})
}

// GET /api/v1/market/my-listings
func (h *MarketHandler) MyListings(c *fiber.Ctx) error {
	playerID := c.Locals("player_id").(string)
	status := c.Query("status", "all")

	listings, err := h.marketSvc.GetMyListings(c.Context(), playerID, status)
	if err != nil {
		log.Printf("[MARKET] my-listings error: %v", err)
		return c.Status(500).JSON(fiber.Map{"error": "failed to get listings"})
	}

	return c.JSON(fiber.Map{"listings": listings})
}

func marketError(c *fiber.Ctx, err error) error {
	switch {
	case errors.Is(err, service.ErrListingNotFound):
		return c.Status(404).JSON(fiber.Map{"error": "listing not found"})
	case errors.Is(err, service.ErrListingNotActive):
		return c.Status(409).JSON(fiber.Map{"error": "listing is no longer active"})
	case errors.Is(err, service.ErrInsufficientCredits):
		return c.Status(400).JSON(fiber.Map{"error": "insufficient credits"})
	case errors.Is(err, service.ErrNotListingOwner):
		return c.Status(403).JSON(fiber.Map{"error": "not the listing owner"})
	case errors.Is(err, service.ErrCannotBuyOwnListing):
		return c.Status(400).JSON(fiber.Map{"error": "cannot buy your own listing"})
	case errors.Is(err, service.ErrInvalidQuantity):
		return c.Status(400).JSON(fiber.Map{"error": "quantity must be greater than 0"})
	case errors.Is(err, service.ErrInvalidPrice):
		return c.Status(400).JSON(fiber.Map{"error": "price must be greater than 0"})
	case errors.Is(err, service.ErrInvalidDuration):
		return c.Status(400).JSON(fiber.Map{"error": "duration must be 24, 48, or 72 hours"})
	case errors.Is(err, service.ErrInvalidCategory):
		return c.Status(400).JSON(fiber.Map{"error": "invalid item category"})
	default:
		errStr := err.Error()
		if strings.Contains(errStr, "no rows") {
			return c.Status(404).JSON(fiber.Map{"error": "listing not found"})
		}
		log.Printf("[MARKET ERROR] %v", err)
		return c.Status(500).JSON(fiber.Map{"error": "internal server error"})
	}
}
