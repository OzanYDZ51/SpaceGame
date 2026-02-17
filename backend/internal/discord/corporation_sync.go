package discord

import (
	"context"
	"log"
	"time"

	"spacegame-backend/internal/repository"

	"github.com/bwmarrin/discordgo"
)

// CorporationSync manages the synchronization between game corporations and Discord roles/channels.
type CorporationSync struct {
	session     *discordgo.Session
	guildID     string
	corpRepo    *repository.CorporationRepository
	discordRepo *repository.DiscordRepository
}

func NewCorporationSync(
	session *discordgo.Session,
	guildID string,
	corpRepo *repository.CorporationRepository,
	discordRepo *repository.DiscordRepository,
) *CorporationSync {
	return &CorporationSync{
		session:     session,
		guildID:     guildID,
		corpRepo:    corpRepo,
		discordRepo: discordRepo,
	}
}

// OnCorporationCreated creates a Discord role and private channel for the new corporation.
func (cs *CorporationSync) OnCorporationCreated(corporationID, corporationName, corporationTag string) {
	if cs == nil || cs.session == nil || cs.guildID == "" {
		return
	}

	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
		defer cancel()

		// Create role
		role, err := cs.session.GuildRoleCreate(cs.guildID, &discordgo.RoleParams{
			Name:  "Corporation " + corporationTag,
			Color: intPtr(0x9B59B6), // Purple
		})
		if err != nil {
			log.Printf("[corporation-sync] failed to create role for corporation %s: %v", corporationName, err)
			return
		}

		// Create private channel
		channel, err := cs.session.GuildChannelCreateComplex(cs.guildID, discordgo.GuildChannelCreateData{
			Name: "corp-" + sanitizeChannelName(corporationTag),
			Type: discordgo.ChannelTypeGuildText,
			PermissionOverwrites: []*discordgo.PermissionOverwrite{
				{
					ID:   cs.guildID, // @everyone
					Type: discordgo.PermissionOverwriteTypeRole,
					Deny: discordgo.PermissionViewChannel,
				},
				{
					ID:    role.ID,
					Type:  discordgo.PermissionOverwriteTypeRole,
					Allow: discordgo.PermissionViewChannel | discordgo.PermissionSendMessages,
				},
			},
		})
		if err != nil {
			log.Printf("[corporation-sync] failed to create channel for corporation %s: %v", corporationName, err)
			return
		}

		// Store mapping
		if err := cs.discordRepo.SetCorporationMapping(ctx, corporationID, role.ID, channel.ID); err != nil {
			log.Printf("[corporation-sync] failed to store mapping for corporation %s: %v", corporationName, err)
		}

		log.Printf("[corporation-sync] Created role %s and channel #%s for corporation [%s]", role.Name, channel.Name, corporationTag)
	}()
}

// OnCorporationDeleted removes the Discord role and channel for a deleted corporation.
func (cs *CorporationSync) OnCorporationDeleted(corporationID string) {
	if cs == nil || cs.session == nil || cs.guildID == "" {
		return
	}

	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()

		mapping, err := cs.discordRepo.GetCorporationMapping(ctx, corporationID)
		if err != nil {
			return
		}

		// Delete channel and role
		if _, err := cs.session.ChannelDelete(mapping.DiscordChannelID); err != nil {
			log.Printf("[corporation-sync] failed to delete channel %s: %v", mapping.DiscordChannelID, err)
		}
		if err := cs.session.GuildRoleDelete(cs.guildID, mapping.DiscordRoleID); err != nil {
			log.Printf("[corporation-sync] failed to delete role %s: %v", mapping.DiscordRoleID, err)
		}

		_ = cs.discordRepo.DeleteCorporationMapping(ctx, corporationID)
		log.Printf("[corporation-sync] Cleaned up Discord resources for corporation %s", corporationID)
	}()
}

// OnMemberJoined assigns the corporation's Discord role to a player (if their account is linked).
func (cs *CorporationSync) OnMemberJoined(corporationID, playerID string) {
	if cs == nil || cs.session == nil || cs.guildID == "" {
		return
	}

	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()

		discordID, err := cs.discordRepo.GetDiscordID(ctx, playerID)
		if err != nil || discordID == "" {
			return
		}

		mapping, err := cs.discordRepo.GetCorporationMapping(ctx, corporationID)
		if err != nil {
			return
		}

		if err := cs.session.GuildMemberRoleAdd(cs.guildID, discordID, mapping.DiscordRoleID); err != nil {
			log.Printf("[corporation-sync] failed to add role to %s: %v", discordID, err)
		}
	}()
}

// OnMemberLeft removes the corporation's Discord role from a player.
func (cs *CorporationSync) OnMemberLeft(corporationID, playerID string) {
	if cs == nil || cs.session == nil || cs.guildID == "" {
		return
	}

	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()

		discordID, err := cs.discordRepo.GetDiscordID(ctx, playerID)
		if err != nil || discordID == "" {
			return
		}

		mapping, err := cs.discordRepo.GetCorporationMapping(ctx, corporationID)
		if err != nil {
			return
		}

		if err := cs.session.GuildMemberRoleRemove(cs.guildID, discordID, mapping.DiscordRoleID); err != nil {
			log.Printf("[corporation-sync] failed to remove role from %s: %v", discordID, err)
		}
	}()
}

func intPtr(i int) *int {
	return &i
}

func sanitizeChannelName(name string) string {
	result := make([]byte, 0, len(name))
	for _, c := range []byte(name) {
		if (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-' {
			result = append(result, c)
		} else if c >= 'A' && c <= 'Z' {
			result = append(result, c+32) // toLower
		} else {
			result = append(result, '-')
		}
	}
	return string(result)
}
