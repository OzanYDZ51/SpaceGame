package repository

import (
	"context"
	"fmt"
	"strings"

	"spacegame-backend/internal/model"

	"github.com/jackc/pgx/v5/pgxpool"
)

type MarketRepository struct {
	pool *pgxpool.Pool
}

func NewMarketRepository(pool *pgxpool.Pool) *MarketRepository {
	return &MarketRepository{pool: pool}
}

func (r *MarketRepository) Create(ctx context.Context, listing *model.MarketListing) (*model.MarketListing, error) {
	err := r.pool.QueryRow(ctx, `
		INSERT INTO market_listings (
			seller_id, seller_name, system_id, station_id, station_name,
			item_category, item_id, item_name, quantity, unit_price,
			listing_fee, status, expires_at
		) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, 'active', $12)
		RETURNING id, created_at
	`,
		listing.SellerID, listing.SellerName, listing.SystemID, listing.StationID, listing.StationName,
		listing.ItemCategory, listing.ItemID, listing.ItemName, listing.Quantity, listing.UnitPrice,
		listing.ListingFee, listing.ExpiresAt,
	).Scan(&listing.ID, &listing.CreatedAt)
	if err != nil {
		return nil, err
	}
	listing.Status = "active"
	return listing, nil
}

func (r *MarketRepository) GetByID(ctx context.Context, id int64) (*model.MarketListing, error) {
	l := &model.MarketListing{}
	err := r.pool.QueryRow(ctx, `
		SELECT id, seller_id, seller_name, system_id, station_id, station_name,
		       item_category, item_id, item_name, quantity, unit_price, listing_fee,
		       status, created_at, expires_at, sold_to_id, sold_to_name, sold_at
		FROM market_listings WHERE id = $1
	`, id).Scan(
		&l.ID, &l.SellerID, &l.SellerName, &l.SystemID, &l.StationID, &l.StationName,
		&l.ItemCategory, &l.ItemID, &l.ItemName, &l.Quantity, &l.UnitPrice, &l.ListingFee,
		&l.Status, &l.CreatedAt, &l.ExpiresAt, &l.SoldToID, &l.SoldToName, &l.SoldAt,
	)
	if err != nil {
		return nil, err
	}
	return l, nil
}

func (r *MarketRepository) Search(ctx context.Context, req *model.SearchListingsRequest) ([]model.MarketListing, int, error) {
	var conditions []string
	var args []interface{}
	argIdx := 1

	conditions = append(conditions, "status = 'active'")

	if req.Category != "" && req.Category != "all" {
		conditions = append(conditions, fmt.Sprintf("item_category = $%d", argIdx))
		args = append(args, req.Category)
		argIdx++
	}

	if req.SearchText != "" {
		conditions = append(conditions, fmt.Sprintf("(LOWER(item_name) LIKE $%d OR LOWER(station_name) LIKE $%d)", argIdx, argIdx))
		args = append(args, "%"+strings.ToLower(req.SearchText)+"%")
		argIdx++
	}

	if req.SystemID != nil {
		conditions = append(conditions, fmt.Sprintf("system_id = $%d", argIdx))
		args = append(args, *req.SystemID)
		argIdx++
	}

	if req.MinPrice != nil {
		conditions = append(conditions, fmt.Sprintf("unit_price >= $%d", argIdx))
		args = append(args, *req.MinPrice)
		argIdx++
	}

	if req.MaxPrice != nil {
		conditions = append(conditions, fmt.Sprintf("unit_price <= $%d", argIdx))
		args = append(args, *req.MaxPrice)
		argIdx++
	}

	where := strings.Join(conditions, " AND ")

	// Count total
	var total int
	countQuery := "SELECT COUNT(*) FROM market_listings WHERE " + where
	err := r.pool.QueryRow(ctx, countQuery, args...).Scan(&total)
	if err != nil {
		return nil, 0, err
	}

	// Sort
	orderBy := "created_at DESC"
	switch req.SortBy {
	case "price_asc":
		orderBy = "unit_price ASC"
	case "price_desc":
		orderBy = "unit_price DESC"
	case "newest":
		orderBy = "created_at DESC"
	case "oldest":
		orderBy = "created_at ASC"
	case "name":
		orderBy = "item_name ASC"
	case "quantity":
		orderBy = "quantity DESC"
	}

	// Limit / offset
	limit := req.Limit
	if limit <= 0 || limit > 100 {
		limit = 50
	}
	offset := req.Offset
	if offset < 0 {
		offset = 0
	}

	query := fmt.Sprintf(`
		SELECT id, seller_id, seller_name, system_id, station_id, station_name,
		       item_category, item_id, item_name, quantity, unit_price, listing_fee,
		       status, created_at, expires_at, sold_to_id, sold_to_name, sold_at
		FROM market_listings
		WHERE %s
		ORDER BY %s
		LIMIT %d OFFSET %d
	`, where, orderBy, limit, offset)

	rows, err := r.pool.Query(ctx, query, args...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	var listings []model.MarketListing
	for rows.Next() {
		var l model.MarketListing
		if err := rows.Scan(
			&l.ID, &l.SellerID, &l.SellerName, &l.SystemID, &l.StationID, &l.StationName,
			&l.ItemCategory, &l.ItemID, &l.ItemName, &l.Quantity, &l.UnitPrice, &l.ListingFee,
			&l.Status, &l.CreatedAt, &l.ExpiresAt, &l.SoldToID, &l.SoldToName, &l.SoldAt,
		); err != nil {
			return nil, 0, err
		}
		listings = append(listings, l)
	}

	if listings == nil {
		listings = []model.MarketListing{}
	}

	return listings, total, nil
}

func (r *MarketRepository) GetBySellerID(ctx context.Context, sellerID string, status string) ([]model.MarketListing, error) {
	var query string
	var args []interface{}

	if status != "" && status != "all" {
		query = `
			SELECT id, seller_id, seller_name, system_id, station_id, station_name,
			       item_category, item_id, item_name, quantity, unit_price, listing_fee,
			       status, created_at, expires_at, sold_to_id, sold_to_name, sold_at
			FROM market_listings
			WHERE seller_id = $1 AND status = $2
			ORDER BY created_at DESC
		`
		args = []interface{}{sellerID, status}
	} else {
		query = `
			SELECT id, seller_id, seller_name, system_id, station_id, station_name,
			       item_category, item_id, item_name, quantity, unit_price, listing_fee,
			       status, created_at, expires_at, sold_to_id, sold_to_name, sold_at
			FROM market_listings
			WHERE seller_id = $1
			ORDER BY created_at DESC
		`
		args = []interface{}{sellerID}
	}

	rows, err := r.pool.Query(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var listings []model.MarketListing
	for rows.Next() {
		var l model.MarketListing
		if err := rows.Scan(
			&l.ID, &l.SellerID, &l.SellerName, &l.SystemID, &l.StationID, &l.StationName,
			&l.ItemCategory, &l.ItemID, &l.ItemName, &l.Quantity, &l.UnitPrice, &l.ListingFee,
			&l.Status, &l.CreatedAt, &l.ExpiresAt, &l.SoldToID, &l.SoldToName, &l.SoldAt,
		); err != nil {
			return nil, err
		}
		listings = append(listings, l)
	}

	if listings == nil {
		listings = []model.MarketListing{}
	}

	return listings, nil
}

func (r *MarketRepository) Buy(ctx context.Context, listingID int64, buyerID string, buyerName string) (*model.MarketListing, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)

	// Lock and verify listing is still active
	l := &model.MarketListing{}
	err = tx.QueryRow(ctx, `
		SELECT id, seller_id, seller_name, system_id, station_id, station_name,
		       item_category, item_id, item_name, quantity, unit_price, listing_fee,
		       status, created_at, expires_at
		FROM market_listings
		WHERE id = $1 AND status = 'active'
		FOR UPDATE
	`, listingID).Scan(
		&l.ID, &l.SellerID, &l.SellerName, &l.SystemID, &l.StationID, &l.StationName,
		&l.ItemCategory, &l.ItemID, &l.ItemName, &l.Quantity, &l.UnitPrice, &l.ListingFee,
		&l.Status, &l.CreatedAt, &l.ExpiresAt,
	)
	if err != nil {
		return nil, err
	}

	totalPrice := l.UnitPrice * int64(l.Quantity)

	// Debit buyer
	var buyerCredits int64
	err = tx.QueryRow(ctx, `
		UPDATE players SET credits = credits - $2, updated_at = NOW()
		WHERE id = $1 AND credits >= $2
		RETURNING credits
	`, buyerID, totalPrice).Scan(&buyerCredits)
	if err != nil {
		return nil, err
	}

	// Credit seller
	_, err = tx.Exec(ctx, `
		UPDATE players SET credits = credits + $2, updated_at = NOW()
		WHERE id = $1
	`, l.SellerID, totalPrice)
	if err != nil {
		return nil, err
	}

	// Mark listing as sold
	_, err = tx.Exec(ctx, `
		UPDATE market_listings
		SET status = 'sold', sold_to_id = $2, sold_to_name = $3, sold_at = NOW()
		WHERE id = $1
	`, listingID, buyerID, buyerName)
	if err != nil {
		return nil, err
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}

	l.Status = "sold"
	l.SoldToID = &buyerID
	l.SoldToName = &buyerName
	return l, nil
}

func (r *MarketRepository) Cancel(ctx context.Context, listingID int64, sellerID string) error {
	tag, err := r.pool.Exec(ctx, `
		UPDATE market_listings SET status = 'cancelled'
		WHERE id = $1 AND seller_id = $2 AND status = 'active'
	`, listingID, sellerID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return fmt.Errorf("listing not found or not active")
	}
	return nil
}

func (r *MarketRepository) GetAvgPrices(ctx context.Context) (map[string]int64, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT item_id, ROUND(AVG(unit_price))::bigint
		FROM market_listings
		WHERE status = 'active'
		GROUP BY item_id
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	result := make(map[string]int64)
	for rows.Next() {
		var itemID string
		var avg int64
		if err := rows.Scan(&itemID, &avg); err != nil {
			return nil, err
		}
		result[itemID] = avg
	}
	return result, nil
}


func (r *MarketRepository) ExpireOld(ctx context.Context) (int64, error) {
	tag, err := r.pool.Exec(ctx, `
		UPDATE market_listings SET status = 'expired'
		WHERE status = 'active' AND expires_at < NOW()
	`)
	if err != nil {
		return 0, err
	}
	return tag.RowsAffected(), nil
}
