package service

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"strings"
	"time"

	"spacegame-backend/internal/model"
	"spacegame-backend/internal/repository"

	"github.com/golang-jwt/jwt/v5"
	"golang.org/x/crypto/bcrypt"
)

var (
	ErrInvalidCredentials = errors.New("invalid credentials")
	ErrUserExists         = errors.New("username or email already exists")
	ErrBanned             = errors.New("account is banned")
	ErrInvalidToken       = errors.New("invalid or expired token")
	ErrWeakPassword       = errors.New("password must be at least 6 characters")
	ErrInvalidUsername     = errors.New("username must be 3-32 alphanumeric characters")
)

const (
	accessTokenDuration  = 15 * time.Minute
	refreshTokenDuration = 30 * 24 * time.Hour // 30 days
)

type AuthService struct {
	playerRepo  *repository.PlayerRepository
	sessionRepo *repository.SessionRepository
	jwtSecret   []byte
}

func NewAuthService(playerRepo *repository.PlayerRepository, sessionRepo *repository.SessionRepository, jwtSecret string) *AuthService {
	return &AuthService{
		playerRepo:  playerRepo,
		sessionRepo: sessionRepo,
		jwtSecret:   []byte(jwtSecret),
	}
}

func (s *AuthService) Register(ctx context.Context, req *model.RegisterRequest) (*model.AuthResponse, error) {
	// Validate
	req.Username = strings.TrimSpace(req.Username)
	req.Email = strings.TrimSpace(strings.ToLower(req.Email))

	if len(req.Username) < 3 || len(req.Username) > 32 {
		return nil, ErrInvalidUsername
	}
	if len(req.Password) < 6 {
		return nil, ErrWeakPassword
	}

	// Hash password
	hash, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		return nil, fmt.Errorf("hash password: %w", err)
	}

	// Create player
	player, err := s.playerRepo.Create(ctx, req.Username, req.Email, string(hash))
	if err != nil {
		if strings.Contains(err.Error(), "duplicate key") || strings.Contains(err.Error(), "unique") {
			return nil, ErrUserExists
		}
		return nil, fmt.Errorf("create player: %w", err)
	}

	// Generate tokens
	tokens, err := s.generateTokenPair(ctx, player.ID, player.Username)
	if err != nil {
		return nil, err
	}

	_ = s.playerRepo.UpdateLoginTime(ctx, player.ID)

	return &model.AuthResponse{
		AccessToken:  tokens.AccessToken,
		RefreshToken: tokens.RefreshToken,
		Player:       player,
	}, nil
}

func (s *AuthService) Login(ctx context.Context, req *model.LoginRequest) (*model.AuthResponse, error) {
	player, err := s.playerRepo.GetByUsername(ctx, strings.TrimSpace(req.Username))
	if err != nil {
		return nil, ErrInvalidCredentials
	}

	if player.IsBanned {
		return nil, ErrBanned
	}

	if err := bcrypt.CompareHashAndPassword([]byte(player.PasswordHash), []byte(req.Password)); err != nil {
		return nil, ErrInvalidCredentials
	}

	tokens, err := s.generateTokenPair(ctx, player.ID, player.Username)
	if err != nil {
		return nil, err
	}

	_ = s.playerRepo.UpdateLoginTime(ctx, player.ID)

	return &model.AuthResponse{
		AccessToken:  tokens.AccessToken,
		RefreshToken: tokens.RefreshToken,
		Player:       player,
	}, nil
}

func (s *AuthService) Refresh(ctx context.Context, refreshToken string) (*model.TokenPair, error) {
	tokenHash := hashToken(refreshToken)

	playerID, err := s.sessionRepo.ValidateRefreshToken(ctx, tokenHash)
	if err != nil {
		return nil, ErrInvalidToken
	}

	// Revoke old token
	_ = s.sessionRepo.RevokeRefreshToken(ctx, tokenHash)

	// Get player username
	player, err := s.playerRepo.GetByID(ctx, playerID)
	if err != nil {
		return nil, err
	}

	if player.IsBanned {
		return nil, ErrBanned
	}

	return s.generateTokenPair(ctx, playerID, player.Username)
}

func (s *AuthService) Logout(ctx context.Context, refreshToken string) error {
	tokenHash := hashToken(refreshToken)
	return s.sessionRepo.RevokeRefreshToken(ctx, tokenHash)
}

func (s *AuthService) ValidateAccessToken(tokenString string) (string, string, error) {
	token, err := jwt.Parse(tokenString, func(t *jwt.Token) (interface{}, error) {
		if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", t.Header["alg"])
		}
		return s.jwtSecret, nil
	})
	if err != nil {
		return "", "", ErrInvalidToken
	}

	claims, ok := token.Claims.(jwt.MapClaims)
	if !ok || !token.Valid {
		return "", "", ErrInvalidToken
	}

	playerID, _ := claims["sub"].(string)
	username, _ := claims["username"].(string)
	if playerID == "" {
		return "", "", ErrInvalidToken
	}

	return playerID, username, nil
}

func (s *AuthService) generateTokenPair(ctx context.Context, playerID, username string) (*model.TokenPair, error) {
	// Access token
	now := time.Now()
	accessClaims := jwt.MapClaims{
		"sub":      playerID,
		"username": username,
		"iat":      now.Unix(),
		"exp":      now.Add(accessTokenDuration).Unix(),
	}
	accessToken := jwt.NewWithClaims(jwt.SigningMethodHS256, accessClaims)
	accessStr, err := accessToken.SignedString(s.jwtSecret)
	if err != nil {
		return nil, fmt.Errorf("sign access token: %w", err)
	}

	// Refresh token (random bytes)
	refreshBytes := make([]byte, 32)
	if _, err := rand.Read(refreshBytes); err != nil {
		return nil, fmt.Errorf("generate refresh token: %w", err)
	}
	refreshStr := hex.EncodeToString(refreshBytes)

	// Store hash of refresh token
	tokenHash := hashToken(refreshStr)
	expiresAt := now.Add(refreshTokenDuration)
	if err := s.sessionRepo.StoreRefreshToken(ctx, playerID, tokenHash, expiresAt); err != nil {
		return nil, fmt.Errorf("store refresh token: %w", err)
	}

	return &model.TokenPair{
		AccessToken:  accessStr,
		RefreshToken: refreshStr,
	}, nil
}

func hashToken(token string) string {
	h := sha256.Sum256([]byte(token))
	return hex.EncodeToString(h[:])
}
