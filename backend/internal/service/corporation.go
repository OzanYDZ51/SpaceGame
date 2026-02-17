package service

import (
	"context"
	"errors"
	"log"
	"strings"

	"spacegame-backend/internal/model"
	"spacegame-backend/internal/repository"
)

var (
	ErrCorporationNotFound       = errors.New("corporation not found")
	ErrNotCorporationMember      = errors.New("not a corporation member")
	ErrNotCorporationLeader      = errors.New("insufficient corporation permissions")
	ErrAlreadyInCorporation      = errors.New("player is already in a corporation")
	ErrCorporationFull           = errors.New("corporation is full")
	ErrCorporationNotRecruiting  = errors.New("corporation is not recruiting")
	ErrInvalidAmount             = errors.New("invalid amount")
	ErrInsufficientFunds         = errors.New("insufficient funds")
	ErrAlreadyApplied            = errors.New("already applied to this corporation")
	ErrApplicationNotFound       = errors.New("application not found")
	ErrNameTooLong               = errors.New("corporation name must be 32 characters or less")
	ErrTagTooLong                = errors.New("corporation tag must be 5 characters or less")
	ErrNameTooShort              = errors.New("corporation name must be at least 3 characters")
	ErrTagTooShort               = errors.New("corporation tag must be at least 2 characters")
)

type CorporationService struct {
	corpRepo   *repository.CorporationRepository
	playerRepo *repository.PlayerRepository
}

func NewCorporationService(corpRepo *repository.CorporationRepository, playerRepo *repository.PlayerRepository) *CorporationService {
	return &CorporationService{corpRepo: corpRepo, playerRepo: playerRepo}
}

func (s *CorporationService) Create(ctx context.Context, playerID string, req *model.CreateCorporationRequest) (*model.Corporation, error) {
	// Validate lengths
	req.CorporationName = strings.TrimSpace(req.CorporationName)
	req.CorporationTag = strings.TrimSpace(req.CorporationTag)
	if len(req.CorporationName) < 3 {
		return nil, ErrNameTooShort
	}
	if len(req.CorporationName) > 32 {
		return nil, ErrNameTooLong
	}
	if len(req.CorporationTag) < 2 {
		return nil, ErrTagTooShort
	}
	if len(req.CorporationTag) > 5 {
		return nil, ErrTagTooLong
	}

	// Check player not already in a corporation
	existingCorporationID, err := s.playerRepo.GetCorporationID(ctx, playerID)
	if err != nil {
		return nil, err
	}
	if existingCorporationID != nil {
		return nil, ErrAlreadyInCorporation
	}

	corporation, err := s.corpRepo.Create(ctx, req)
	if err != nil {
		return nil, err
	}

	// Create default ranks
	if err := s.corpRepo.CreateDefaultRanks(ctx, corporation.ID); err != nil {
		return nil, err
	}

	// Add creator as leader (rank 4)
	if err := s.corpRepo.AddMember(ctx, corporation.ID, playerID, 4); err != nil {
		return nil, err
	}

	// Update player's corporation_id
	if err := s.playerRepo.SetCorporationID(ctx, playerID, &corporation.ID); err != nil {
		return nil, err
	}

	return corporation, nil
}

func (s *CorporationService) Get(ctx context.Context, corporationID string) (*model.Corporation, error) {
	return s.corpRepo.GetByID(ctx, corporationID)
}

func (s *CorporationService) Search(ctx context.Context, query string) ([]*model.Corporation, error) {
	return s.corpRepo.Search(ctx, query, 20)
}

func (s *CorporationService) Update(ctx context.Context, playerID, corporationID string, req *model.UpdateCorporationRequest) error {
	if err := s.requireRank(ctx, playerID, corporationID, 3); err != nil {
		return err
	}
	return s.corpRepo.Update(ctx, corporationID, req)
}

func (s *CorporationService) Delete(ctx context.Context, playerID, corporationID string) error {
	if err := s.requireRank(ctx, playerID, corporationID, 4); err != nil {
		return err
	}

	// Clear all members' corporation_id
	members, err := s.corpRepo.GetMembers(ctx, corporationID)
	if err != nil {
		return err
	}
	for _, m := range members {
		_ = s.playerRepo.SetCorporationID(ctx, m.PlayerID, nil)
	}

	return s.corpRepo.Delete(ctx, corporationID)
}

func (s *CorporationService) GetMembers(ctx context.Context, corporationID string) ([]*model.CorporationMember, error) {
	return s.corpRepo.GetMembers(ctx, corporationID)
}

func (s *CorporationService) AddMember(ctx context.Context, playerID, corporationID, targetPlayerID string) error {
	// Self-join: player joining themselves — only require corporation to be recruiting
	if playerID == targetPlayerID {
		corporation, err := s.corpRepo.GetByID(ctx, corporationID)
		if err != nil {
			return ErrCorporationNotFound
		}
		if !corporation.IsRecruiting {
			return ErrCorporationNotRecruiting
		}
	} else {
		// Officer inviting someone else — require rank 2 (Officier)
		if err := s.requireRank(ctx, playerID, corporationID, 2); err != nil {
			return err
		}
	}

	// Check target not already in a corporation
	existingCorporationID, err := s.playerRepo.GetCorporationID(ctx, targetPlayerID)
	if err != nil {
		return err
	}
	if existingCorporationID != nil {
		return ErrAlreadyInCorporation
	}

	// Check capacity
	count, err := s.corpRepo.GetMemberCount(ctx, corporationID)
	if err != nil {
		return err
	}
	corporation, err := s.corpRepo.GetByID(ctx, corporationID)
	if err != nil {
		return err
	}
	if count >= corporation.MaxMembers {
		return ErrCorporationFull
	}

	if err := s.corpRepo.AddMember(ctx, corporationID, targetPlayerID, 0); err != nil {
		return err
	}

	if err := s.playerRepo.SetCorporationID(ctx, targetPlayerID, &corporationID); err != nil {
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
	_ = s.corpRepo.AddActivity(ctx, corporationID, 1, actorName, targetName, "joined the corporation")

	return nil
}

func (s *CorporationService) RemoveMember(ctx context.Context, playerID, corporationID, targetPlayerID string) error {
	// Can remove self (leave) or officer+ can kick
	if playerID != targetPlayerID {
		if err := s.requireRank(ctx, playerID, corporationID, 2); err != nil {
			return err
		}
	}

	if err := s.corpRepo.RemoveMember(ctx, targetPlayerID); err != nil {
		return err
	}

	if err := s.playerRepo.SetCorporationID(ctx, targetPlayerID, nil); err != nil {
		return err
	}

	// Auto-dissolve corporation if no members remain
	count, err := s.corpRepo.GetMemberCount(ctx, corporationID)
	if err == nil && count == 0 {
		if delErr := s.corpRepo.Delete(ctx, corporationID); delErr != nil {
			log.Printf("[CORPORATION] Failed to auto-dissolve corporation %s: %v", corporationID, delErr)
		} else {
			log.Printf("[CORPORATION] Auto-dissolved corporation %s (0 members)", corporationID)
		}
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
	_ = s.corpRepo.AddActivity(ctx, corporationID, 2, actorName, targetName, "left the corporation")

	return nil
}

func (s *CorporationService) SetMemberRank(ctx context.Context, playerID, corporationID, targetPlayerID string, rankPriority int) error {
	if err := s.requireRank(ctx, playerID, corporationID, 3); err != nil {
		return err
	}
	return s.corpRepo.SetMemberRank(ctx, targetPlayerID, rankPriority)
}

func (s *CorporationService) Deposit(ctx context.Context, playerID, corporationID string, amount int64) (int64, error) {
	if amount <= 0 {
		return 0, ErrInvalidAmount
	}

	member, err := s.corpRepo.GetMember(ctx, playerID)
	if err != nil {
		return 0, ErrNotCorporationMember
	}
	if member.CorporationID != corporationID {
		return 0, ErrNotCorporationMember
	}

	newBalance, err := s.corpRepo.UpdateTreasury(ctx, corporationID, amount)
	if err != nil {
		return 0, err
	}

	player, _ := s.playerRepo.GetByID(ctx, playerID)
	name := ""
	if player != nil {
		name = player.Username
	}
	_ = s.corpRepo.AddTransaction(ctx, corporationID, playerID, name, "deposit", amount)

	return newBalance, nil
}

func (s *CorporationService) Withdraw(ctx context.Context, playerID, corporationID string, amount int64) (int64, error) {
	if amount <= 0 {
		return 0, ErrInvalidAmount
	}

	if err := s.requireRank(ctx, playerID, corporationID, 3); err != nil {
		return 0, err
	}

	newBalance, err := s.corpRepo.UpdateTreasury(ctx, corporationID, -amount)
	if err != nil {
		return 0, ErrInsufficientFunds
	}

	player, _ := s.playerRepo.GetByID(ctx, playerID)
	name := ""
	if player != nil {
		name = player.Username
	}
	_ = s.corpRepo.AddTransaction(ctx, corporationID, playerID, name, "withdraw", amount)

	return newBalance, nil
}

func (s *CorporationService) GetActivity(ctx context.Context, corporationID string, limit int) ([]*model.CorporationActivity, error) {
	if limit <= 0 || limit > 100 {
		limit = 50
	}
	return s.corpRepo.GetActivity(ctx, corporationID, limit)
}

func (s *CorporationService) GetDiplomacy(ctx context.Context, corporationID string) ([]*model.CorporationDiplomacy, error) {
	return s.corpRepo.GetDiplomacy(ctx, corporationID)
}

func (s *CorporationService) SetDiplomacy(ctx context.Context, playerID, corporationID, targetCorporationID, relation string) error {
	if err := s.requireRank(ctx, playerID, corporationID, 3); err != nil {
		return err
	}
	return s.corpRepo.SetDiplomacy(ctx, corporationID, targetCorporationID, relation)
}

// --- Ranks ---

func (s *CorporationService) GetRanks(ctx context.Context, corporationID string) ([]*model.CorporationRank, error) {
	return s.corpRepo.GetRanks(ctx, corporationID)
}

func (s *CorporationService) AddRank(ctx context.Context, playerID, corporationID, rankName string, priority, permissions int) (*model.CorporationRank, error) {
	if err := s.requireRank(ctx, playerID, corporationID, 3); err != nil {
		return nil, err
	}
	return s.corpRepo.InsertRank(ctx, corporationID, rankName, priority, permissions)
}

func (s *CorporationService) UpdateRank(ctx context.Context, playerID, corporationID string, rankID int64, rankName string, permissions int) error {
	if err := s.requireRank(ctx, playerID, corporationID, 3); err != nil {
		return err
	}
	return s.corpRepo.UpdateRank(ctx, rankID, rankName, permissions)
}

func (s *CorporationService) RemoveRank(ctx context.Context, playerID, corporationID string, rankID int64) error {
	if err := s.requireRank(ctx, playerID, corporationID, 3); err != nil {
		return err
	}

	// Find the rank to get its priority
	ranks, err := s.corpRepo.GetRanks(ctx, corporationID)
	if err != nil {
		return err
	}

	var deletedPriority int = -1
	var lowestPriority int = 0
	for _, r := range ranks {
		if r.ID == rankID {
			deletedPriority = r.Priority
		}
		if r.Priority < lowestPriority || lowestPriority == 0 {
			lowestPriority = r.Priority
		}
	}

	if deletedPriority < 0 {
		return ErrCorporationNotFound
	}

	// Reassign members on the deleted rank to the lowest priority rank
	members, err := s.corpRepo.GetMembers(ctx, corporationID)
	if err != nil {
		return err
	}
	for _, m := range members {
		if m.RankPriority == deletedPriority {
			_ = s.corpRepo.SetMemberRank(ctx, m.PlayerID, lowestPriority)
		}
	}

	return s.corpRepo.DeleteRank(ctx, rankID)
}

// --- Applications ---

func (s *CorporationService) Apply(ctx context.Context, playerID, corporationID, note string) (*model.CorporationApplication, error) {
	// Check player not already in a corporation
	existingCorpID, err := s.playerRepo.GetCorporationID(ctx, playerID)
	if err != nil {
		return nil, err
	}
	if existingCorpID != nil {
		return nil, ErrAlreadyInCorporation
	}

	// Check corporation exists
	_, err = s.corpRepo.GetByID(ctx, corporationID)
	if err != nil {
		return nil, ErrCorporationNotFound
	}

	// Get player name
	player, err := s.playerRepo.GetByID(ctx, playerID)
	if err != nil {
		return nil, err
	}

	app, err := s.corpRepo.CreateApplication(ctx, corporationID, playerID, player.Username, note)
	if err != nil {
		if strings.Contains(err.Error(), "unique constraint") || strings.Contains(err.Error(), "duplicate key") {
			return nil, ErrAlreadyApplied
		}
		return nil, err
	}
	return app, nil
}

func (s *CorporationService) GetApplications(ctx context.Context, playerID, corporationID string) ([]*model.CorporationApplication, error) {
	if err := s.requireRank(ctx, playerID, corporationID, 2); err != nil {
		return nil, err
	}
	return s.corpRepo.GetApplications(ctx, corporationID)
}

func (s *CorporationService) GetMyApplications(ctx context.Context, playerID string) ([]*model.CorporationApplication, error) {
	return s.corpRepo.GetPlayerApplications(ctx, playerID)
}

func (s *CorporationService) HandleApplication(ctx context.Context, playerID, corporationID string, applicationID int64, action string) error {
	if err := s.requireRank(ctx, playerID, corporationID, 2); err != nil {
		return err
	}

	app, err := s.corpRepo.GetApplication(ctx, applicationID)
	if err != nil {
		return ErrApplicationNotFound
	}
	if app.CorporationID != corporationID {
		return ErrApplicationNotFound
	}

	if action == "accept" {
		// Check capacity
		count, err := s.corpRepo.GetMemberCount(ctx, corporationID)
		if err != nil {
			return err
		}
		corporation, err := s.corpRepo.GetByID(ctx, corporationID)
		if err != nil {
			return err
		}
		if count >= corporation.MaxMembers {
			return ErrCorporationFull
		}

		// Check applicant not already in a corporation
		existingCorpID, err := s.playerRepo.GetCorporationID(ctx, app.PlayerID)
		if err != nil {
			return err
		}
		if existingCorpID != nil {
			// Player joined another corp in the meantime — just delete the application
			_ = s.corpRepo.DeleteApplication(ctx, applicationID)
			return ErrAlreadyInCorporation
		}

		// Add as member (rank 0 = recruit)
		if err := s.corpRepo.AddMember(ctx, corporationID, app.PlayerID, 0); err != nil {
			return err
		}
		if err := s.playerRepo.SetCorporationID(ctx, app.PlayerID, &corporationID); err != nil {
			return err
		}

		// Clean up all of this player's applications
		_ = s.corpRepo.DeletePlayerApplications(ctx, app.PlayerID)

		// Log activity
		officer, _ := s.playerRepo.GetByID(ctx, playerID)
		officerName := ""
		if officer != nil {
			officerName = officer.Username
		}
		_ = s.corpRepo.AddActivity(ctx, corporationID, 1, officerName, app.PlayerName, "application accepted")
	} else {
		// Reject: delete the application
		_ = s.corpRepo.DeleteApplication(ctx, applicationID)

		officer, _ := s.playerRepo.GetByID(ctx, playerID)
		officerName := ""
		if officer != nil {
			officerName = officer.Username
		}
		_ = s.corpRepo.AddActivity(ctx, corporationID, 2, officerName, app.PlayerName, "application rejected")
	}
	return nil
}

func (s *CorporationService) CancelApplication(ctx context.Context, playerID string, applicationID int64) error {
	app, err := s.corpRepo.GetApplication(ctx, applicationID)
	if err != nil {
		return ErrApplicationNotFound
	}
	if app.PlayerID != playerID {
		return ErrNotCorporationMember
	}
	return s.corpRepo.DeleteApplication(ctx, applicationID)
}

// requireRank checks that the player has at least the given rank priority in the corporation
func (s *CorporationService) requireRank(ctx context.Context, playerID, corporationID string, minRank int) error {
	member, err := s.corpRepo.GetMember(ctx, playerID)
	if err != nil {
		return ErrNotCorporationMember
	}
	if member.CorporationID != corporationID {
		return ErrNotCorporationMember
	}
	if member.RankPriority < minRank {
		return ErrNotCorporationLeader
	}
	return nil
}
