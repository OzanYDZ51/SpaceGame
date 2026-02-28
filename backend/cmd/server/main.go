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
	"spacegame-backend/internal/discord"
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
	corpRepo := repository.NewCorporationRepository(db)
	sessionRepo := repository.NewSessionRepository(db)
	changelogRepo := repository.NewChangelogRepository(db)
	eventRepo := repository.NewEventRepository(db)
	discordRepo := repository.NewDiscordRepository(db)
	fleetRepo := repository.NewFleetRepository(db)
	chatRepo := repository.NewChatRepository(db)
	marketRepo := repository.NewMarketRepository(db)

	// Services
	authSvc := service.NewAuthService(playerRepo, sessionRepo, cfg.JWTSecret)
	playerSvc := service.NewPlayerService(playerRepo)
	corpSvc := service.NewCorporationService(corpRepo, playerRepo)
	wsHub := service.NewWSHub()

	marketSvc := service.NewMarketService(marketRepo, playerRepo)

	// Discord webhook service
	webhookSvc := service.NewDiscordWebhookService(
		cfg.DiscordWebhookDevlog,
		cfg.DiscordWebhookStatus,
		cfg.DiscordWebhookKills,
		cfg.DiscordWebhookEvents,
		cfg.DiscordWebhookBugs,
		cfg.DiscordWebhookCorporations,
	)

	// Event service (records + dispatches to Discord)
	eventSvc := service.NewEventService(eventRepo, webhookSvc)

	// Discord bot (optional — starts only if token is configured)
	discordBot, err := discord.NewBot(
		cfg.DiscordBotToken,
		cfg.DiscordGuildID,
		playerRepo,
		corpRepo,
		discordRepo,
		wsHub,
		webhookSvc,
	)
	if err != nil {
		log.Printf("Warning: Discord bot failed to initialize: %v", err)
	}

	// Fiber app
	app := fiber.New(fiber.Config{
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 10 * time.Second,
		IdleTimeout:  30 * time.Second,
		BodyLimit:    2 * 1024 * 1024, // 2MB (for bug report screenshots)
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

	// Updates (public — launcher calls this)
	updatesH := handler.NewUpdatesHandler(cfg.GithubOwner, cfg.GithubRepo, cfg.GithubToken)
	v1.Get("/updates", updatesH.GetUpdates)
	v1.Post("/updates/refresh", updatesH.RefreshCache)

	// Public stats (no auth — website server pulse)
	publicH := handler.NewPublicHandler(playerRepo, corpRepo, eventRepo, wsHub)
	pub := v1.Group("/public")
	pub.Get("/stats", publicH.Stats)

	// Changelog (public GET, admin POST)
	changelogH := handler.NewChangelogHandler(changelogRepo, webhookSvc)
	v1.Get("/changelog", changelogH.List)

	// Auth (public)
	authH := handler.NewAuthHandler(authSvc)
	auth := v1.Group("/auth")
	auth.Post("/register", middleware.RateLimit(5, time.Minute), authH.Register)
	auth.Post("/login", middleware.RateLimit(10, time.Minute), authH.Login)
	auth.Post("/refresh", middleware.RateLimit(20, time.Minute), authH.Refresh)
	auth.Post("/logout", authH.Logout)

	// Server-to-server (game server key auth) — registered BEFORE protected group
	server := v1.Group("/server", middleware.ServerKey(cfg.ServerKey))
	serverH := handler.NewServerHandler(authSvc, playerSvc, playerRepo)
	server.Post("/validate-token", serverH.ValidateToken)
	server.Post("/save-state", serverH.SaveState)
	server.Post("/heartbeat", serverH.Heartbeat)
	// Game server events
	eventH := handler.NewEventHandler(eventSvc)
	server.Post("/event", eventH.RecordEvent)
	// Fleet management (server-to-server)
	fleetH := handler.NewFleetHandler(fleetRepo)
	server.Get("/fleet/deployed", fleetH.GetDeployed)
	server.Put("/fleet/sync", fleetH.SyncPositions)
	server.Post("/fleet/death", fleetH.ReportDeath)
	server.Put("/fleet/upsert", fleetH.BulkUpsert)
	// Chat persistence (server-to-server)
	chatH := handler.NewChatHandler(chatRepo)
	server.Post("/chat/messages", chatH.PostMessage)
	server.Get("/chat/history", chatH.GetHistory)

	// Admin — registered BEFORE protected group
	admin := v1.Group("/admin", middleware.AdminKey(cfg.AdminKey))
	adminH := handler.NewAdminHandler(playerRepo, corpRepo, wsHub)
	admin.Get("/stats", adminH.Stats)
	admin.Post("/announce", adminH.Announce)
	admin.Post("/changelog", changelogH.Create)

	// JWT-protected routes — use explicit groups per resource instead of a
	// catch-all Group("") which in Fiber acts like Use() and blocks public routes.
	authMw := middleware.Auth(cfg.JWTSecret)

	// Player
	playerH := handler.NewPlayerHandler(playerSvc)
	player := v1.Group("/player", authMw)
	player.Get("/state", playerH.GetState)
	player.Put("/state", playerH.SaveState)
	player.Get("/profile/:id", playerH.GetProfile)

	// Player bug reports & Discord linking
	bugH := handler.NewBugReportHandler(eventSvc)
	player.Post("/bug-report", bugH.Submit)
	discordH := handler.NewDiscordHandler(discordRepo)
	player.Post("/discord-link", discordH.ConfirmLink)
	player.Get("/discord-status", discordH.GetStatus)

	// Corporations
	corpH := handler.NewCorporationHandler(corpSvc)
	corporations := v1.Group("/corporations", authMw)
	corporations.Post("/", corpH.Create)
	corporations.Get("/search", corpH.Search)
	corporations.Get("/my-applications", corpH.GetMyApplications)
	corporations.Delete("/my-applications/:aid", corpH.CancelApplication)
	corporations.Get("/:id", corpH.Get)
	corporations.Put("/:id", corpH.Update)
	corporations.Delete("/:id", corpH.Delete)
	corporations.Get("/:id/members", corpH.GetMembers)
	corporations.Post("/:id/members", corpH.AddMember)
	corporations.Delete("/:id/members/:pid", corpH.RemoveMember)
	corporations.Put("/:id/members/:pid/rank", corpH.SetMemberRank)
	corporations.Post("/:id/treasury/deposit", corpH.Deposit)
	corporations.Post("/:id/treasury/withdraw", corpH.Withdraw)
	corporations.Get("/:id/activity", corpH.GetActivity)
	corporations.Get("/:id/ranks", corpH.GetRanks)
	corporations.Post("/:id/ranks", corpH.AddRank)
	corporations.Put("/:id/ranks/:rid", corpH.UpdateRank)
	corporations.Delete("/:id/ranks/:rid", corpH.RemoveRank)
	corporations.Get("/:id/diplomacy", corpH.GetDiplomacy)
	corporations.Put("/:id/diplomacy", corpH.SetDiplomacy)
	corporations.Get("/:id/applications", corpH.GetApplications)
	corporations.Post("/:id/applications", corpH.Apply)
	corporations.Put("/:id/applications/:aid", corpH.HandleApplication)

	// Market (HDV)
	marketH := handler.NewMarketHandler(marketSvc)
	market := v1.Group("/market", authMw)
	market.Get("/avg-prices", marketH.AvgPrices)
	market.Get("/listings", marketH.Search)
	market.Post("/listings", marketH.Create)
	market.Get("/my-listings", marketH.MyListings)
	market.Get("/listings/:id", marketH.GetByID)
	market.Post("/listings/:id/buy", marketH.Buy)
	market.Delete("/listings/:id", marketH.Cancel)

	// WebSocket
	wsH := handler.NewWSHandler(wsHub, cfg.JWTSecret)
	app.Get("/ws", wsH.Upgrade)

	// Start hub
	go wsHub.Run()

	// Background: purge chat messages older than 7 days (runs hourly)
	go func() {
		ticker := time.NewTicker(1 * time.Hour)
		defer ticker.Stop()
		for range ticker.C {
			deleted, err := chatRepo.DeleteOlderThan(context.Background(), 7)
			if err != nil {
				log.Printf("Chat cleanup error: %v", err)
			} else if deleted > 0 {
				log.Printf("Chat cleanup: deleted %d old messages", deleted)
			}
		}
	}()

	// Background: expire old market listings (runs every 10 minutes)
	go func() {
		ticker := time.NewTicker(10 * time.Minute)
		defer ticker.Stop()
		for range ticker.C {
			expired, err := marketSvc.ExpireListings(context.Background())
			if err != nil {
				log.Printf("Market expiry error: %v", err)
			} else if expired > 0 {
				log.Printf("Market expiry: expired %d listings", expired)
			}
		}
	}()

	// Start Discord bot
	if discordBot != nil {
		if err := discordBot.Start(); err != nil {
			log.Printf("Warning: Discord bot failed to start: %v", err)
		}
	}

	// Graceful shutdown
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)

	go func() {
		if err := app.Listen(":" + cfg.Port); err != nil {
			log.Fatalf("Server error: %v", err)
		}
	}()

	log.Printf("Imperion Online backend running on :%s (%s)", cfg.Port, cfg.Env)

	<-quit
	log.Println("Shutting down...")
	if discordBot != nil {
		discordBot.Stop()
	}
	_ = app.ShutdownWithTimeout(5 * time.Second)
	wsHub.Shutdown()
	log.Println("Server stopped")
}
