package handler

import (
	"errors"

	"spacegame-backend/internal/model"
	"spacegame-backend/internal/service"

	"github.com/gofiber/fiber/v2"
)

type AuthHandler struct {
	authSvc *service.AuthService
}

func NewAuthHandler(authSvc *service.AuthService) *AuthHandler {
	return &AuthHandler{authSvc: authSvc}
}

func (h *AuthHandler) Register(c *fiber.Ctx) error {
	var req model.RegisterRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "invalid request body"})
	}

	if req.Username == "" || req.Email == "" || req.Password == "" {
		return c.Status(400).JSON(fiber.Map{"error": "username, email and password are required"})
	}

	resp, err := h.authSvc.Register(c.Context(), &req)
	if err != nil {
		return authError(c, err)
	}

	return c.Status(201).JSON(resp)
}

func (h *AuthHandler) Login(c *fiber.Ctx) error {
	var req model.LoginRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "invalid request body"})
	}

	if req.Username == "" || req.Password == "" {
		return c.Status(400).JSON(fiber.Map{"error": "username and password are required"})
	}

	resp, err := h.authSvc.Login(c.Context(), &req)
	if err != nil {
		return authError(c, err)
	}

	return c.JSON(resp)
}

func (h *AuthHandler) Refresh(c *fiber.Ctx) error {
	var req model.RefreshRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "invalid request body"})
	}

	if req.RefreshToken == "" {
		return c.Status(400).JSON(fiber.Map{"error": "refresh_token is required"})
	}

	tokens, err := h.authSvc.Refresh(c.Context(), req.RefreshToken)
	if err != nil {
		return authError(c, err)
	}

	return c.JSON(tokens)
}

func (h *AuthHandler) Logout(c *fiber.Ctx) error {
	var req model.LogoutRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "invalid request body"})
	}

	if req.RefreshToken != "" {
		_ = h.authSvc.Logout(c.Context(), req.RefreshToken)
	}

	return c.JSON(fiber.Map{"ok": true})
}

func authError(c *fiber.Ctx, err error) error {
	switch {
	case errors.Is(err, service.ErrInvalidCredentials):
		return c.Status(401).JSON(fiber.Map{"error": "invalid credentials"})
	case errors.Is(err, service.ErrUserExists):
		return c.Status(409).JSON(fiber.Map{"error": "username or email already exists"})
	case errors.Is(err, service.ErrBanned):
		return c.Status(403).JSON(fiber.Map{"error": "account is banned"})
	case errors.Is(err, service.ErrInvalidToken):
		return c.Status(401).JSON(fiber.Map{"error": "invalid or expired token"})
	case errors.Is(err, service.ErrWeakPassword):
		return c.Status(400).JSON(fiber.Map{"error": err.Error()})
	case errors.Is(err, service.ErrInvalidUsername):
		return c.Status(400).JSON(fiber.Map{"error": err.Error()})
	default:
		return c.Status(500).JSON(fiber.Map{"error": "internal server error"})
	}
}
