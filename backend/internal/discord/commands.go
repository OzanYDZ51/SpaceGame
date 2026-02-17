package discord

import (
	"context"
	"fmt"
	"strings"
	"time"

	"spacegame-backend/internal/repository"
	"spacegame-backend/internal/service"

	"github.com/bwmarrin/discordgo"
)

// CommandHandler processes bot prefix commands.
type CommandHandler struct {
	playerRepo  *repository.PlayerRepository
	corpRepo    *repository.CorporationRepository
	discordRepo *repository.DiscordRepository
	wsHub       *service.WSHub
}

func NewCommandHandler(
	playerRepo *repository.PlayerRepository,
	corpRepo *repository.CorporationRepository,
	discordRepo *repository.DiscordRepository,
	wsHub *service.WSHub,
) *CommandHandler {
	return &CommandHandler{
		playerRepo:  playerRepo,
		corpRepo:    corpRepo,
		discordRepo: discordRepo,
		wsHub:       wsHub,
	}
}

// Handle dispatches a prefix command.
func (h *CommandHandler) Handle(s *discordgo.Session, m *discordgo.MessageCreate) {
	parts := strings.Fields(m.Content)
	if len(parts) == 0 {
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	switch strings.ToLower(parts[0]) {
	case "!status":
		h.cmdStatus(ctx, s, m)
	case "!player":
		if len(parts) < 2 {
			s.ChannelMessageSend(m.ChannelID, "Usage: `!player <nom>`")
			return
		}
		h.cmdPlayer(ctx, s, m, parts[1])
	case "!link":
		h.cmdLink(ctx, s, m)
	case "!help":
		h.cmdHelp(s, m)
	}
}

func (h *CommandHandler) cmdStatus(ctx context.Context, s *discordgo.Session, m *discordgo.MessageCreate) {
	online := h.wsHub.OnlineCount()

	embed := &discordgo.MessageEmbed{
		Title: "Imperion Online — Statut du serveur",
		Color: 0x2ECC71,
		Fields: []*discordgo.MessageEmbedField{
			{Name: "Joueurs en ligne", Value: fmt.Sprintf("%d", online), Inline: true},
			{Name: "Status", Value: "EN LIGNE", Inline: true},
		},
		Timestamp: time.Now().UTC().Format(time.RFC3339),
		Footer:    &discordgo.MessageEmbedFooter{Text: "Imperion Online"},
	}
	s.ChannelMessageSendEmbed(m.ChannelID, embed)
}

func (h *CommandHandler) cmdPlayer(ctx context.Context, s *discordgo.Session, m *discordgo.MessageCreate, name string) {
	player, err := h.playerRepo.GetByUsername(ctx, name)
	if err != nil {
		s.ChannelMessageSend(m.ChannelID, fmt.Sprintf("Joueur `%s` introuvable.", name))
		return
	}

	corporationName := "Aucun"
	if player.CorporationID != nil {
		corporation, err := h.corpRepo.GetByID(ctx, *player.CorporationID)
		if err == nil && corporation != nil {
			corporationName = fmt.Sprintf("[%s] %s", corporation.CorporationTag, corporation.CorporationName)
		}
	}

	kd := "N/A"
	if player.Deaths > 0 {
		kd = fmt.Sprintf("%.2f", float64(player.Kills)/float64(player.Deaths))
	} else if player.Kills > 0 {
		kd = fmt.Sprintf("%d/0", player.Kills)
	}

	embed := &discordgo.MessageEmbed{
		Title: fmt.Sprintf("Profil de %s", player.Username),
		Color: 0x00C8FF,
		Fields: []*discordgo.MessageEmbedField{
			{Name: "Vaisseau", Value: player.CurrentShipID, Inline: true},
			{Name: "Corporation", Value: corporationName, Inline: true},
			{Name: "Kills", Value: fmt.Sprintf("%d", player.Kills), Inline: true},
			{Name: "Morts", Value: fmt.Sprintf("%d", player.Deaths), Inline: true},
			{Name: "K/D", Value: kd, Inline: true},
		},
		Timestamp: time.Now().UTC().Format(time.RFC3339),
		Footer:    &discordgo.MessageEmbedFooter{Text: "Imperion Online"},
	}
	s.ChannelMessageSendEmbed(m.ChannelID, embed)
}

func (h *CommandHandler) cmdLink(ctx context.Context, s *discordgo.Session, m *discordgo.MessageCreate) {
	// Check if already linked
	existing, _ := h.discordRepo.GetPlayerByDiscordID(ctx, m.Author.ID)
	if existing != nil {
		s.ChannelMessageSend(m.ChannelID,
			fmt.Sprintf("Votre Discord est déjà lié au compte **%s**.", existing.Username))
		return
	}

	code, err := h.discordRepo.GenerateLinkCode(ctx, m.Author.ID)
	if err != nil {
		s.ChannelMessageSend(m.ChannelID, "Erreur lors de la génération du code.")
		return
	}

	embed := &discordgo.MessageEmbed{
		Title:       "Lier votre compte Imperion Online",
		Description: fmt.Sprintf("Votre code de liaison: **%s**\n\nEntrez ce code dans le jeu:\n`/discord %s`\n\nLe code expire dans 10 minutes.", code, code),
		Color:       0x00C8FF,
		Footer:      &discordgo.MessageEmbedFooter{Text: "Imperion Online"},
	}

	// Send as DM
	ch, err := s.UserChannelCreate(m.Author.ID)
	if err != nil {
		s.ChannelMessageSendEmbed(m.ChannelID, embed)
		return
	}
	s.ChannelMessageSendEmbed(ch.ID, embed)
	s.ChannelMessageSend(m.ChannelID, "Code de liaison envoyé en message privé!")
}

func (h *CommandHandler) cmdHelp(s *discordgo.Session, m *discordgo.MessageCreate) {
	embed := &discordgo.MessageEmbed{
		Title: "Imperion Online Bot — Commandes",
		Color: 0x00C8FF,
		Fields: []*discordgo.MessageEmbedField{
			{Name: "`!status`", Value: "Affiche le statut du serveur et le nombre de joueurs en ligne"},
			{Name: "`!player <nom>`", Value: "Affiche les stats publiques d'un joueur"},
			{Name: "`!link`", Value: "Lie votre compte Discord à votre compte Imperion Online"},
			{Name: "`!help`", Value: "Affiche cette aide"},
		},
		Footer: &discordgo.MessageEmbedFooter{Text: "Imperion Online"},
	}
	s.ChannelMessageSendEmbed(m.ChannelID, embed)
}
