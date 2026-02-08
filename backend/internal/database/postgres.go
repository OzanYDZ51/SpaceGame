package database

import (
	"context"
	"fmt"
	"log"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

func NewPool(ctx context.Context, databaseURL string) (*pgxpool.Pool, error) {
	config, err := pgxpool.ParseConfig(databaseURL)
	if err != nil {
		return nil, err
	}

	config.MaxConns = 20
	config.MinConns = 2
	config.MaxConnLifetime = 30 * time.Minute
	config.MaxConnIdleTime = 5 * time.Minute

	// Retry connection (Postgres may not be ready yet in Docker)
	var pool *pgxpool.Pool
	for attempt := 1; attempt <= 10; attempt++ {
		pool, err = pgxpool.NewWithConfig(ctx, config)
		if err != nil {
			log.Printf("DB connect attempt %d/10 failed: %v", attempt, err)
			time.Sleep(2 * time.Second)
			continue
		}
		if pingErr := pool.Ping(ctx); pingErr != nil {
			pool.Close()
			log.Printf("DB ping attempt %d/10 failed: %v", attempt, pingErr)
			time.Sleep(2 * time.Second)
			continue
		}
		log.Printf("Database connected (attempt %d)", attempt)
		return pool, nil
	}

	return nil, fmt.Errorf("failed to connect after 10 attempts: %w", err)
}
