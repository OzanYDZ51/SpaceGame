package service

import (
	"context"

	"spacegame-backend/internal/model"
	"spacegame-backend/internal/repository"
)

type PlayerService struct {
	playerRepo *repository.PlayerRepository
}

func NewPlayerService(playerRepo *repository.PlayerRepository) *PlayerService {
	return &PlayerService{playerRepo: playerRepo}
}

func (s *PlayerService) GetState(ctx context.Context, playerID string) (*model.PlayerState, error) {
	return s.playerRepo.GetFullState(ctx, playerID)
}

func (s *PlayerService) SaveState(ctx context.Context, playerID string, state *model.PlayerState) error {
	return s.playerRepo.SaveFullState(ctx, playerID, state)
}

func (s *PlayerService) GetProfile(ctx context.Context, playerID string) (*model.PlayerProfile, error) {
	return s.playerRepo.GetProfile(ctx, playerID)
}
