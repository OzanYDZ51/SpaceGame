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
	clanRepo := repository.NewClanRepository(db)
	sessionRepo := repository.NewSessionRepository(db)
	changelogRepo := repository.NewChangelogRepository(db)
	eventRepo := repository.NewEventRepository(db)
	discordRepo := repository.NewDiscordRepository(db)

	// Services
	authSvc := service.NewAuthService(playerRepo, sessionRepo, cfg.JWTSecret)
	playerSvc := service.NewPlayerService(playerRepo)
	clanSvc := service.NewClanService(clanRepo, playerRepo)
	wsHub := service.NewWSHub()

	// Discord webhook service
	webhookSvc := service.NewDiscordWebhookService(
		cfg.DiscordWebhookDevlog,
		cfg.DiscordWebhookStatus,
		cfg.DiscordWebhookKills,
		cfg.DiscordWebhookEvents,
		cfg.DiscordWebhookBugs,
		cfg.DiscordWebhookClans,
	)

	// Event service (records + dispatches to Discord)
	eventSvc := service.NewEventService(eventRepo, webhookSvc)

	// Discord bot (optional — starts only if token is configured)
	discordBot, err := discord.NewBot(
		cfg.DiscordBotToken,
		cfg.DiscordGuildID,
		playerRepo,
		clanRepo,
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
	serverH := handler.NewServerHandler(authSvc, playerSvc)
	server.Post("/validate-token", serverH.ValidateToken)
	server.Post("/save-state", serverH.SaveState)
	// Game server events
	eventH := handler.NewEventHandler(eventSvc)
	server.Post("/event", eventH.RecordEvent)

	// Admin — registered BEFORE protected group
	admin := v1.Group("/admin", middleware.AdminKey(cfg.AdminKey))
	adminH := handler.NewAdminHandler(playerRepo, clanRepo, wsHub)
	admin.Get("/stats", adminH.Stats)
	admin.Post("/announce", adminH.Announce)
	admin.Post("/changelog", changelogH.Create)

	// JWT-protected routes (catch-all — must be LAST)
	protected := v1.Group("", middleware.Auth(cfg.JWTSecret))

	// Player
	playerH := handler.NewPlayerHandler(playerSvc)
	protected.Get("/player/state", playerH.GetState)
	protected.Put("/player/state", playerH.SaveState)
	protected.Get("/player/profile/:id", playerH.GetProfile)

	// Player bug reports & Discord linking
	bugH := handler.NewBugReportHandler(eventSvc)
	protected.Post("/player/bug-report", bugH.Submit)
	discordH := handler.NewDiscordHandler(discordRepo)
	protected.Post("/player/discord-link", discordH.ConfirmLink)
	protected.Get("/player/discord-status", discordH.GetStatus)

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

	log.Printf("SpaceGame backend running on :%s (%s)", cfg.Port, cfg.Env)

	<-quit
	log.Println("Shutting down...")
	if discordBot != nil {
		discordBot.Stop()
	}
	_ = app.ShutdownWithTimeout(5 * time.Second)
	wsHub.Shutdown()
	log.Println("Server stopped")
}
