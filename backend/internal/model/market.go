package model

import "time"

type MarketListing struct {
	ID           int64      `json:"id"`
	SellerID     string     `json:"seller_id"`
	SellerName   string     `json:"seller_name"`
	SystemID     int        `json:"system_id"`
	StationID    string     `json:"station_id"`
	StationName  string     `json:"station_name"`
	ItemCategory string     `json:"item_category"`
	ItemID       string     `json:"item_id"`
	ItemName     string     `json:"item_name"`
	Quantity     int        `json:"quantity"`
	UnitPrice    int64      `json:"unit_price"`
	ListingFee   int64      `json:"listing_fee"`
	Status       string     `json:"status"`
	CreatedAt    time.Time  `json:"created_at"`
	ExpiresAt    time.Time  `json:"expires_at"`
	SoldToID     *string    `json:"sold_to_id,omitempty"`
	SoldToName   *string    `json:"sold_to_name,omitempty"`
	SoldAt       *time.Time `json:"sold_at,omitempty"`
}

type CreateListingRequest struct {
	ItemCategory  string `json:"item_category"`
	ItemID        string `json:"item_id"`
	ItemName      string `json:"item_name"`
	Quantity      int    `json:"quantity"`
	UnitPrice     int64  `json:"unit_price"`
	DurationHours int    `json:"duration_hours"`
	SystemID      int    `json:"system_id"`
	StationID     string `json:"station_id"`
	StationName   string `json:"station_name"`
}

type SearchListingsRequest struct {
	Category   string `json:"category"`
	SearchText string `json:"search_text"`
	SystemID   *int   `json:"system_id,omitempty"`
	MinPrice   *int64 `json:"min_price,omitempty"`
	MaxPrice   *int64 `json:"max_price,omitempty"`
	SortBy     string `json:"sort_by"`
	Limit      int    `json:"limit"`
	Offset     int    `json:"offset"`
}

type BuyListingRequest struct {
	Quantity int `json:"quantity"`
}
