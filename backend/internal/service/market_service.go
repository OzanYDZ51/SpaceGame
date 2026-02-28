package service

import (
	"context"
	"errors"
	"time"

	"spacegame-backend/internal/model"
	"spacegame-backend/internal/repository"
)

var (
	ErrListingNotFound      = errors.New("listing not found")
	ErrListingNotActive     = errors.New("listing is not active")
	ErrInsufficientCredits  = errors.New("insufficient credits")
	ErrNotListingOwner      = errors.New("not the listing owner")
	ErrCannotBuyOwnListing  = errors.New("cannot buy your own listing")
	ErrInvalidQuantity      = errors.New("quantity must be greater than 0")
	ErrInvalidPrice         = errors.New("price must be greater than 0")
	ErrInvalidDuration      = errors.New("duration must be 24, 48, or 72 hours")
	ErrInvalidCategory      = errors.New("invalid item category")
)

var validCategories = map[string]bool{
	"ship": true, "weapon": true, "shield": true, "engine": true,
	"module": true, "ore": true, "refined": true, "cargo": true,
}

var validDurations = map[int]bool{24: true, 48: true, 72: true}

const listingFeeRate = 0.05 // 5%

type MarketService struct {
	marketRepo *repository.MarketRepository
	playerRepo *repository.PlayerRepository
}

func NewMarketService(marketRepo *repository.MarketRepository, playerRepo *repository.PlayerRepository) *MarketService {
	return &MarketService{marketRepo: marketRepo, playerRepo: playerRepo}
}

func (s *MarketService) CreateListing(ctx context.Context, playerID string, playerName string, req *model.CreateListingRequest) (*model.MarketListing, error) {
	// Validate
	if req.Quantity <= 0 {
		return nil, ErrInvalidQuantity
	}
	if req.UnitPrice <= 0 {
		return nil, ErrInvalidPrice
	}
	if !validCategories[req.ItemCategory] {
		return nil, ErrInvalidCategory
	}
	if !validDurations[req.DurationHours] {
		return nil, ErrInvalidDuration
	}

	// Calculate listing fee (5% of total value)
	totalValue := req.UnitPrice * int64(req.Quantity)
	fee := int64(float64(totalValue) * listingFeeRate)
	if fee < 1 {
		fee = 1
	}

	// Check player can afford fee
	player, err := s.playerRepo.GetByID(ctx, playerID)
	if err != nil {
		return nil, err
	}
	if player.Credits < fee {
		return nil, ErrInsufficientCredits
	}

	// Debit fee from player
	if err := s.playerRepo.AddCredits(ctx, playerID, -fee); err != nil {
		return nil, err
	}

	// Create listing
	listing := &model.MarketListing{
		SellerID:     playerID,
		SellerName:   playerName,
		SystemID:     req.SystemID,
		StationID:    req.StationID,
		StationName:  req.StationName,
		ItemCategory: req.ItemCategory,
		ItemID:       req.ItemID,
		ItemName:     req.ItemName,
		Quantity:     req.Quantity,
		UnitPrice:    req.UnitPrice,
		ListingFee:   fee,
		ExpiresAt:    time.Now().Add(time.Duration(req.DurationHours) * time.Hour),
	}

	return s.marketRepo.Create(ctx, listing)
}

func (s *MarketService) BuyListing(ctx context.Context, listingID int64, buyerID string, buyerName string) (*model.MarketListing, error) {
	// Get listing to verify
	listing, err := s.marketRepo.GetByID(ctx, listingID)
	if err != nil {
		return nil, ErrListingNotFound
	}

	if listing.Status != "active" {
		return nil, ErrListingNotActive
	}

	if listing.SellerID == buyerID {
		return nil, ErrCannotBuyOwnListing
	}

	totalPrice := listing.UnitPrice * int64(listing.Quantity)

	// Check buyer credits
	buyer, err := s.playerRepo.GetByID(ctx, buyerID)
	if err != nil {
		return nil, err
	}
	if buyer.Credits < totalPrice {
		return nil, ErrInsufficientCredits
	}

	// Atomic buy (debit buyer, credit seller, mark sold)
	return s.marketRepo.Buy(ctx, listingID, buyerID, buyerName)
}

func (s *MarketService) CancelListing(ctx context.Context, listingID int64, playerID string) error {
	listing, err := s.marketRepo.GetByID(ctx, listingID)
	if err != nil {
		return ErrListingNotFound
	}
	if listing.SellerID != playerID {
		return ErrNotListingOwner
	}
	if listing.Status != "active" {
		return ErrListingNotActive
	}
	return s.marketRepo.Cancel(ctx, listingID, playerID)
}

func (s *MarketService) SearchListings(ctx context.Context, req *model.SearchListingsRequest) ([]model.MarketListing, int, error) {
	return s.marketRepo.Search(ctx, req)
}

func (s *MarketService) GetListing(ctx context.Context, id int64) (*model.MarketListing, error) {
	listing, err := s.marketRepo.GetByID(ctx, id)
	if err != nil {
		return nil, ErrListingNotFound
	}
	return listing, nil
}

func (s *MarketService) GetMyListings(ctx context.Context, playerID string, status string) ([]model.MarketListing, error) {
	return s.marketRepo.GetBySellerID(ctx, playerID, status)
}

func (s *MarketService) GetAvgPrices(ctx context.Context) (map[string]int64, error) {
	return s.marketRepo.GetAvgPrices(ctx)
}

func (s *MarketService) ExpireListings(ctx context.Context) (int64, error) {
	return s.marketRepo.ExpireOld(ctx)
}
