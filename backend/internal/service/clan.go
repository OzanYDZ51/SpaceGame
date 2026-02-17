package service

import (
	"context"
	"errors"

	"spacegame-backend/internal/model"
	"spacegame-backend/internal/repository"
)

var (
	ErrClanNotFound     = errors.New("clan not found")
	ErrNotClanMember    = errors.New("not a clan member")
	ErrNotClanLeader    = errors.New("insufficient clan permissions")
	ErrAlreadyInClan    = errors.New("player is already in a clan")
	ErrClanFull         = errors.New("clan is full")
	ErrInvalidAmount    = errors.New("invalid amount")
	ErrInsufficientFunds = errors.New("insufficient funds")
)

type ClanService struct {
	clanRepo   *repository.ClanRepository
	playerRepo *repository.PlayerRepository
}

func NewClanService(clanRepo *repository.ClanRepository, playerRepo *repository.PlayerRepository) *ClanService {
	return &ClanService{clanRepo: clanRepo, playerRepo: playerRepo}
}

func (s *ClanService) Create(ctx context.Context, playerID string, req *model.CreateClanRequest) (*model.Clan, error) {
	// Check player not already in a clan
	existingClanID, err := s.playerRepo.GetClanID(ctx, playerID)
	if err != nil {
		return nil, err
	}
	if existingClanID != nil {
		return nil, ErrAlreadyInClan
	}

	clan, err := s.clanRepo.Create(ctx, req)
	if err != nil {
		return nil, err
	}

	// Create default ranks
	if err := s.clanRepo.CreateDefaultRanks(ctx, clan.ID); err != nil {
		return nil, err
	}

	// Add creator as leader (rank 4)
	if err := s.clanRepo.AddMember(ctx, clan.ID, playerID, 4); err != nil {
		return nil, err
	}

	// Update player's clan_id
	if err := s.playerRepo.SetClanID(ctx, playerID, &clan.ID); err != nil {
		return nil, err
	}

	return clan, nil
}

func (s *ClanService) Get(ctx context.Context, clanID string) (*model.Clan, error) {
	return s.clanRepo.GetByID(ctx, clanID)
}

func (s *ClanService) Search(ctx context.Context, query string) ([]*model.Clan, error) {
	return s.clanRepo.Search(ctx, query, 20)
}

func (s *ClanService) Update(ctx context.Context, playerID, clanID string, req *model.UpdateClanRequest) error {
	if err := s.requireRank(ctx, playerID, clanID, 3); err != nil {
		return err
	}
	return s.clanRepo.Update(ctx, clanID, req)
}

func (s *ClanService) Delete(ctx context.Context, playerID, clanID string) error {
	if err := s.requireRank(ctx, playerID, clanID, 4); err != nil {
		return err
	}

	// Clear all members' clan_id
	members, err := s.clanRepo.GetMembers(ctx, clanID)
	if err != nil {
		return err
	}
	for _, m := range members {
		_ = s.playerRepo.SetClanID(ctx, m.PlayerID, nil)
	}

	return s.clanRepo.Delete(ctx, clanID)
}

func (s *ClanService) GetMembers(ctx context.Context, clanID string) ([]*model.ClanMember, error) {
	return s.clanRepo.GetMembers(ctx, clanID)
}

func (s *ClanService) AddMember(ctx context.Context, playerID, clanID, targetPlayerID string) error {
	if err := s.requireRank(ctx, playerID, clanID, 2); err != nil {
		return err
	}

	// Check target not already in a clan
	existingClanID, err := s.playerRepo.GetClanID(ctx, targetPlayerID)
	if err != nil {
		return err
	}
	if existingClanID != nil {
		return ErrAlreadyInClan
	}

	// Check capacity
	count, err := s.clanRepo.GetMemberCount(ctx, clanID)
	if err != nil {
		return err
	}
	clan, err := s.clanRepo.GetByID(ctx, clanID)
	if err != nil {
		return err
	}
	if count >= clan.MaxMembers {
		return ErrClanFull
	}

	if err := s.clanRepo.AddMember(ctx, clanID, targetPlayerID, 0); err != nil {
		return err
	}

	if err := s.playerRepo.SetClanID(ctx, targetPlayerID, &clanID); err != nil {
		return err
	}

	// Log activity
	player, _ := s.playerRepo.GetByID(ctx, playerID)
	target, _ := s.playerRepo.GetByID(ctx, targetPlayerID)
	actorName, targetName := "", ""
	if player != nil {
		actorName = player.Username
	}
	if target != nil {
		targetName = target.Username
	}
	_ = s.clanRepo.AddActivity(ctx, clanID, 1, actorName, targetName, "joined the clan")

	return nil
}

func (s *ClanService) RemoveMember(ctx context.Context, playerID, clanID, targetPlayerID string) error {
	// Can remove self (leave) or officer+ can kick
	if playerID != targetPlayerID {
		if err := s.requireRank(ctx, playerID, clanID, 2); err != nil {
			return err
		}
	}

	if err := s.clanRepo.RemoveMember(ctx, targetPlayerID); err != nil {
		return err
	}

	if err := s.playerRepo.SetClanID(ctx, targetPlayerID, nil); err != nil {
		return err
	}

	// Auto-dissolve clan if no members remain
	count, err := s.clanRepo.GetMemberCount(ctx, clanID)
	if err == nil && count == 0 {
		_ = s.clanRepo.Delete(ctx, clanID)
		return nil
	}

	player, _ := s.playerRepo.GetByID(ctx, playerID)
	target, _ := s.playerRepo.GetByID(ctx, targetPlayerID)
	actorName, targetName := "", ""
	if player != nil {
		actorName = player.Username
	}
	if target != nil {
		targetName = target.Username
	}
	_ = s.clanRepo.AddActivity(ctx, clanID, 2, actorName, targetName, "left the clan")

	return nil
}

func (s *ClanService) SetMemberRank(ctx context.Context, playerID, clanID, targetPlayerID string, rankPriority int) error {
	if err := s.requireRank(ctx, playerID, clanID, 3); err != nil {
		return err
	}
	return s.clanRepo.SetMemberRank(ctx, targetPlayerID, rankPriority)
}

func (s *ClanService) Deposit(ctx context.Context, playerID, clanID string, amount int64) (int64, error) {
	if amount <= 0 {
		return 0, ErrInvalidAmount
	}

	member, err := s.clanRepo.GetMember(ctx, playerID)
	if err != nil {
		return 0, ErrNotClanMember
	}
	if member.ClanID != clanID {
		return 0, ErrNotClanMember
	}

	newBalance, err := s.clanRepo.UpdateTreasury(ctx, clanID, amount)
	if err != nil {
		return 0, err
	}

	player, _ := s.playerRepo.GetByID(ctx, playerID)
	name := ""
	if player != nil {
		name = player.Username
	}
	_ = s.clanRepo.AddTransaction(ctx, clanID, playerID, name, "deposit", amount)

	return newBalance, nil
}

func (s *ClanService) Withdraw(ctx context.Context, playerID, clanID string, amount int64) (int64, error) {
	if amount <= 0 {
		return 0, ErrInvalidAmount
	}

	if err := s.requireRank(ctx, playerID, clanID, 3); err != nil {
		return 0, err
	}

	newBalance, err := s.clanRepo.UpdateTreasury(ctx, clanID, -amount)
	if err != nil {
		return 0, ErrInsufficientFunds
	}

	player, _ := s.playerRepo.GetByID(ctx, playerID)
	name := ""
	if player != nil {
		name = player.Username
	}
	_ = s.clanRepo.AddTransaction(ctx, clanID, playerID, name, "withdraw", amount)

	return newBalance, nil
}

func (s *ClanService) GetActivity(ctx context.Context, clanID string, limit int) ([]*model.ClanActivity, error) {
	if limit <= 0 || limit > 100 {
		limit = 50
	}
	return s.clanRepo.GetActivity(ctx, clanID, limit)
}

func (s *ClanService) GetDiplomacy(ctx context.Context, clanID string) ([]*model.ClanDiplomacy, error) {
	return s.clanRepo.GetDiplomacy(ctx, clanID)
}

func (s *ClanService) SetDiplomacy(ctx context.Context, playerID, clanID, targetClanID, relation string) error {
	if err := s.requireRank(ctx, playerID, clanID, 3); err != nil {
		return err
	}
	return s.clanRepo.SetDiplomacy(ctx, clanID, targetClanID, relation)
}

// requireRank checks that the player has at least the given rank priority in the clan
func (s *ClanService) requireRank(ctx context.Context, playerID, clanID string, minRank int) error {
	member, err := s.clanRepo.GetMember(ctx, playerID)
	if err != nil {
		return ErrNotClanMember
	}
	if member.ClanID != clanID {
		return ErrNotClanMember
	}
	if member.RankPriority < minRank {
		return ErrNotClanLeader
	}
	return nil
}
