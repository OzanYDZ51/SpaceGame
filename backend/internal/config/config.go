package config

import (
	"os"
	"strconv"
)

type Config struct {
	Env         string
	Port        string
	DatabaseURL string
	JWTSecret   string
	ServerKey   string
	AdminKey    string
}

func Load() *Config {
	return &Config{
		Env:         getEnv("ENV", "development"),
		Port:        getEnv("PORT", "3000"),
		DatabaseURL: getEnv("DATABASE_URL", "postgres://spacegame:spacegame@localhost:5432/spacegame?sslmode=disable"),
		JWTSecret:   getEnv("JWT_SECRET", "dev-jwt-secret-not-for-production-use-64-chars-minimum-padding"),
		ServerKey:   getEnv("SERVER_KEY", "dev-server-key"),
		AdminKey:    getEnv("ADMIN_KEY", "dev-admin-key"),
	}
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
