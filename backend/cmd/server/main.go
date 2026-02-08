package main

import (
	"context"
	"log"
	"os"
	"os/signal"
	"syscall"
	"time"

	"spacegame-backend/internal/config"
	"spacegame-backend/internal/database"
	"spacegame-backend/internal/handler"
	"spacegame-backend/internal/middleware"
	"spacegame-backend/internal/repository"
	"spacegame-backend/internal/service"

	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/fiber/v2/middleware/recover"
)

func main() {
	cfg := config.Load()

	// Database
	db, err := database.NewPool(context.Background(), cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("Failed to connect to database: %v", err)
	}
	defer db.Close()

	if err := database.RunMigrations(context.Background(), db); err != nil {
		log.Fatalf("Failed to run migrations: %v", err)
	}
	log.Println("Migrations applied successfully")

	// Repositories
	playerRepo := repository.NewPlayerRepository(db)
	clanRepo := repository.NewClanRepository(db)
	sessionRepo := repository.NewSessionRepository(db)

	// Services
	authSvc := service.NewAuthService(playerRepo, sessionRepo, cfg.JWTSecret)
	playerSvc := service.NewPlayerService(playerRepo)
	clanSvc := service.NewClanService(clanRepo, playerRepo)
	wsHub := service.NewWSHub()

	// Fiber app
	app := fiber.New(fiber.Config{
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 10 * time.Second,
		IdleTimeout:  30 * time.Second,
		BodyLimit:    1 * 1024 * 1024, // 1MB
	})

	app.Use(recover.New())
	app.Use(middleware.Logger())
	app.Use(middleware.CORS())

	// Health
	healthH := handler.NewHealthHandler(db)
	app.Get("/health", healthH.Health)
	app.Get("/ready", healthH.Ready)

	// API v1
	v1 := app.Group("/api/v1")

	// Auth (public)
	authH := handler.NewAuthHandler(authSvc)
	auth := v1.Group("/auth")
	auth.Post("/register", middleware.RateLimit(5, time.Minute), authH.Register)
	auth.Post("/login", middleware.RateLimit(10, time.Minute), authH.Login)
	auth.Post("/refresh", middleware.RateLimit(20, time.Minute), authH.Refresh)
	auth.Post("/logout", authH.Logout)

	// Server-to-server (game server key auth) — registered BEFORE protected group
	server := v1.Group("/server", middleware.ServerKey(cfg.ServerKey))
	serverH := handler.NewServerHandler(authSvc, playerSvc)
	server.Post("/validate-token", serverH.ValidateToken)
	server.Post("/save-state", serverH.SaveState)

	// Admin — registered BEFORE protected group
	admin := v1.Group("/admin", middleware.AdminKey(cfg.AdminKey))
	adminH := handler.NewAdminHandler(playerRepo, clanRepo, wsHub)
	admin.Get("/stats", adminH.Stats)
	admin.Post("/announce", adminH.Announce)

	// JWT-protected routes (catch-all — must be LAST)
	protected := v1.Group("", middleware.Auth(cfg.JWTSecret))

	// Player
	playerH := handler.NewPlayerHandler(playerSvc)
	protected.Get("/player/state", playerH.GetState)
	protected.Put("/player/state", playerH.SaveState)
	protected.Get("/player/profile/:id", playerH.GetProfile)

	// Clans
	clanH := handler.NewClanHandler(clanSvc)
	clans := protected.Group("/clans")
	clans.Post("/", clanH.Create)
	clans.Get("/search", clanH.Search)
	clans.Get("/:id", clanH.Get)
	clans.Put("/:id", clanH.Update)
	clans.Delete("/:id", clanH.Delete)
	clans.Get("/:id/members", clanH.GetMembers)
	clans.Post("/:id/members", clanH.AddMember)
	clans.Delete("/:id/members/:pid", clanH.RemoveMember)
	clans.Put("/:id/members/:pid/rank", clanH.SetMemberRank)
	clans.Post("/:id/treasury/deposit", clanH.Deposit)
	clans.Post("/:id/treasury/withdraw", clanH.Withdraw)
	clans.Get("/:id/activity", clanH.GetActivity)
	clans.Get("/:id/diplomacy", clanH.GetDiplomacy)
	clans.Put("/:id/diplomacy", clanH.SetDiplomacy)

	// WebSocket
	wsH := handler.NewWSHandler(wsHub, cfg.JWTSecret)
	app.Get("/ws", wsH.Upgrade)

	// Start hub
	go wsHub.Run()

	// Graceful shutdown
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)

	go func() {
		if err := app.Listen(":" + cfg.Port); err != nil {
			log.Fatalf("Server error: %v", err)
		}
	}()

	log.Printf("SpaceGame backend running on :%s (%s)", cfg.Port, cfg.Env)

	<-quit
	log.Println("Shutting down...")
	_ = app.ShutdownWithTimeout(5 * time.Second)
	wsHub.Shutdown()
	log.Println("Server stopped")
}
