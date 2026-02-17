package discord

import (
	"context"
	"log"
	"time"

	"spacegame-backend/internal/repository"

	"github.com/bwmarrin/discordgo"
)

// ClanSync manages the synchronization between game clans and Discord roles/channels.
type ClanSync struct {
	session     *discordgo.Session
	guildID     string
	clanRepo    *repository.ClanRepository
	discordRepo *repository.DiscordRepository
}

func NewClanSync(
	session *discordgo.Session,
	guildID string,
	clanRepo *repository.ClanRepository,
	discordRepo *repository.DiscordRepository,
) *ClanSync {
	return &ClanSync{
		session:     session,
		guildID:     guildID,
		clanRepo:    clanRepo,
		discordRepo: discordRepo,
	}
}

// OnClanCreated creates a Discord role and private channel for the new clan.
func (cs *ClanSync) OnClanCreated(clanID, clanName, clanTag string) {
	if cs == nil || cs.session == nil || cs.guildID == "" {
		return
	}

	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
		defer cancel()

		// Create role
		role, err := cs.session.GuildRoleCreate(cs.guildID, &discordgo.RoleParams{
			Name:  "Clan " + clanTag,
			Color: intPtr(0x9B59B6), // Purple
		})
		if err != nil {
			log.Printf("[clan-sync] failed to create role for clan %s: %v", clanName, err)
			return
		}

		// Create private channel
		channel, err := cs.session.GuildChannelCreateComplex(cs.guildID, discordgo.GuildChannelCreateData{
			Name: "clan-" + sanitizeChannelName(clanTag),
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
			log.Printf("[clan-sync] failed to create channel for clan %s: %v", clanName, err)
			return
		}

		// Store mapping
		if err := cs.discordRepo.SetClanMapping(ctx, clanID, role.ID, channel.ID); err != nil {
			log.Printf("[clan-sync] failed to store mapping for clan %s: %v", clanName, err)
		}

		log.Printf("[clan-sync] Created role %s and channel #%s for clan [%s]", role.Name, channel.Name, clanTag)
	}()
}

// OnClanDeleted removes the Discord role and channel for a deleted clan.
func (cs *ClanSync) OnClanDeleted(clanID string) {
	if cs == nil || cs.session == nil || cs.guildID == "" {
		return
	}

	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()

		mapping, err := cs.discordRepo.GetClanMapping(ctx, clanID)
		if err != nil {
			return
		}

		// Delete channel and role
		if _, err := cs.session.ChannelDelete(mapping.DiscordChannelID); err != nil {
			log.Printf("[clan-sync] failed to delete channel %s: %v", mapping.DiscordChannelID, err)
		}
		if err := cs.session.GuildRoleDelete(cs.guildID, mapping.DiscordRoleID); err != nil {
			log.Printf("[clan-sync] failed to delete role %s: %v", mapping.DiscordRoleID, err)
		}

		_ = cs.discordRepo.DeleteClanMapping(ctx, clanID)
		log.Printf("[clan-sync] Cleaned up Discord resources for clan %s", clanID)
	}()
}

// OnMemberJoined assigns the clan's Discord role to a player (if their account is linked).
func (cs *ClanSync) OnMemberJoined(clanID, playerID string) {
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

		mapping, err := cs.discordRepo.GetClanMapping(ctx, clanID)
		if err != nil {
			return
		}

		if err := cs.session.GuildMemberRoleAdd(cs.guildID, discordID, mapping.DiscordRoleID); err != nil {
			log.Printf("[clan-sync] failed to add role to %s: %v", discordID, err)
		}
	}()
}

// OnMemberLeft removes the clan's Discord role from a player.
func (cs *ClanSync) OnMemberLeft(clanID, playerID string) {
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

		mapping, err := cs.discordRepo.GetClanMapping(ctx, clanID)
		if err != nil {
			return
		}

		if err := cs.session.GuildMemberRoleRemove(cs.guildID, discordID, mapping.DiscordRoleID); err != nil {
			log.Printf("[clan-sync] failed to remove role from %s: %v", discordID, err)
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
