package config

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strconv"
)

type discordFileConfig struct {
	BotToken string `json:"bot_token"`
	GuildID  string `json:"guild_id"`
	Webhooks struct {
		Devlog string `json:"devlog"`
		Status string `json:"status"`
		Kills  string `json:"kills"`
		Events string `json:"events"`
		Bugs   string `json:"bugs"`
		Clans  string `json:"clans"`
	} `json:"webhooks"`
}

type Config struct {
	Env         string
	Port        string
	DatabaseURL string
	JWTSecret   string
	ServerKey   string
	AdminKey    string
	GithubToken string
	GithubOwner string
	GithubRepo  string
	// Discord
	DiscordBotToken      string
	DiscordGuildID       string
	DiscordWebhookDevlog string
	DiscordWebhookStatus string
	DiscordWebhookKills  string
	DiscordWebhookEvents string
	DiscordWebhookBugs   string
	DiscordWebhookClans  string
}

func Load() *Config {
	// Load Discord config from discord.json file
	dc := loadDiscordFile()

	return &Config{
		Env:         getEnv("ENV", "development"),
		Port:        getEnv("PORT", "3000"),
		DatabaseURL: getEnv("DATABASE_URL", "postgres://imperion:imperion@localhost:5432/imperion?sslmode=disable"),
		JWTSecret:   getEnv("JWT_SECRET", "dev-jwt-secret-not-for-production-use-64-chars-minimum-padding"),
		ServerKey:   getEnv("SERVER_KEY", "dev-server-key"),
		AdminKey:    getEnv("ADMIN_KEY", "dev-admin-key"),
		GithubToken: getEnv("GITHUB_TOKEN", ""),
		GithubOwner: getEnv("GITHUB_OWNER", "OzanYDZ51"),
		GithubRepo:  getEnv("GITHUB_REPO", "ImperionOnline"),
		// Discord — file first, env var override
		DiscordBotToken:      getEnvOr("DISCORD_BOT_TOKEN", dc.BotToken),
		DiscordGuildID:       getEnvOr("DISCORD_GUILD_ID", dc.GuildID),
		DiscordWebhookDevlog: getEnvOr("DISCORD_WEBHOOK_DEVLOG", dc.Webhooks.Devlog),
		DiscordWebhookStatus: getEnvOr("DISCORD_WEBHOOK_STATUS", dc.Webhooks.Status),
		DiscordWebhookKills:  getEnvOr("DISCORD_WEBHOOK_KILLS", dc.Webhooks.Kills),
		DiscordWebhookEvents: getEnvOr("DISCORD_WEBHOOK_EVENTS", dc.Webhooks.Events),
		DiscordWebhookBugs:   getEnvOr("DISCORD_WEBHOOK_BUGS", dc.Webhooks.Bugs),
		DiscordWebhookClans:  getEnvOr("DISCORD_WEBHOOK_CLANS", dc.Webhooks.Clans),
	}
}

func loadDiscordFile() discordFileConfig {
	var dc discordFileConfig
	// Try discord.json next to the executable, then in working directory
	paths := []string{"discord.json"}
	if exe, err := os.Executable(); err == nil {
		paths = append([]string{filepath.Join(filepath.Dir(exe), "discord.json")}, paths...)
	}
	for _, p := range paths {
		data, err := os.ReadFile(p)
		if err != nil {
			continue
		}
		_ = json.Unmarshal(data, &dc)
		return dc
	}
	return dc
}

func getEnvOr(key, fileValue string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fileValue
}

func (c *Config) IsProduction() bool {
	return c.Env == "production"
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func getEnvInt(key string, fallback int) int {
	if v := os.Getenv(key); v != "" {
		if i, err := strconv.Atoi(v); err == nil {
			return i
		}
	}
	return fallback
}
