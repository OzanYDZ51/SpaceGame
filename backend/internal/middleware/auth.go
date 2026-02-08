package middleware

import (
	"fmt"
	"strings"

	"github.com/gofiber/fiber/v2"
	"github.com/golang-jwt/jwt/v5"
)

func Auth(jwtSecret string) fiber.Handler {
	secret := []byte(jwtSecret)
	return func(c *fiber.Ctx) error {
		authHeader := c.Get("Authorization")
		if authHeader == "" {
			return c.Status(401).JSON(fiber.Map{"error": "missing authorization header"})
		}

		tokenString := strings.TrimPrefix(authHeader, "Bearer ")
		if tokenString == authHeader {
			return c.Status(401).JSON(fiber.Map{"error": "invalid authorization format"})
		}

		token, err := jwt.Parse(tokenString, func(t *jwt.Token) (interface{}, error) {
			if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
				return nil, fmt.Errorf("unexpected signing method: %v", t.Header["alg"])
			}
			return secret, nil
		})
		if err != nil || !token.Valid {
			return c.Status(401).JSON(fiber.Map{"error": "invalid or expired token"})
		}

		claims, ok := token.Claims.(jwt.MapClaims)
		if !ok {
			return c.Status(401).JSON(fiber.Map{"error": "invalid token claims"})
		}

		playerID, _ := claims["sub"].(string)
		username, _ := claims["username"].(string)
		if playerID == "" {
			return c.Status(401).JSON(fiber.Map{"error": "invalid token: missing subject"})
		}

		c.Locals("player_id", playerID)
		c.Locals("username", username)
		return c.Next()
	}
}

func ServerKey(expectedKey string) fiber.Handler {
	return func(c *fiber.Ctx) error {
		key := c.Get("X-Server-Key")
		if key == "" || key != expectedKey {
			return c.Status(403).JSON(fiber.Map{"error": "invalid server key"})
		}
		return c.Next()
	}
}

func AdminKey(expectedKey string) fiber.Handler {
	return func(c *fiber.Ctx) error {
		key := c.Get("X-Admin-Key")
		if key == "" || key != expectedKey {
			return c.Status(403).JSON(fiber.Map{"error": "invalid admin key"})
		}
		return c.Next()
	}
}
