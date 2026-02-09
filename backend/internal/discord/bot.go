package discord

import (
	"log"

	"spacegame-backend/internal/repository"
	"spacegame-backend/internal/service"

	"github.com/bwmarrin/discordgo"
)

// Bot manages the Discord bot lifecycle and command dispatch.
type Bot struct {
	session    *discordgo.Session
	guildID    string
	commands   *CommandHandler
	clanSync   *ClanSync
}

// NewBot creates and configures a new Discord bot.
func NewBot(
	token string,
	guildID string,
	playerRepo *repository.PlayerRepository,
	clanRepo *repository.ClanRepository,
	discordRepo *repository.DiscordRepository,
	wsHub *service.WSHub,
	webhooks *service.DiscordWebhookService,
) (*Bot, error) {
	if token == "" {
		log.Println("[discord-bot] No bot token configured, bot disabled")
		return nil, nil
	}

	s, err := discordgo.New("Bot " + token)
	if err != nil {
		return nil, err
	}

	s.Identify.Intents = discordgo.IntentsGuildMessages |
		discordgo.IntentsGuildMembers |
		discordgo.IntentsDirectMessages

	commands := NewCommandHandler(playerRepo, clanRepo, discordRepo, wsHub)
	clanSync := NewClanSync(s, guildID, clanRepo, discordRepo)

	bot := &Bot{
		session:  s,
		guildID:  guildID,
		commands: commands,
		clanSync: clanSync,
	}

	// Register message handler for prefix commands
	s.AddHandler(bot.onMessageCreate)

	return bot, nil
}

// Start opens the Discord gateway connection.
func (b *Bot) Start() error {
	if b == nil || b.session == nil {
		return nil
	}
	if err := b.session.Open(); err != nil {
		return err
	}
	log.Println("[discord-bot] Bot connected to Discord")
	return nil
}

// Stop closes the Discord gateway connection.
func (b *Bot) Stop() {
	if b == nil || b.session == nil {
		return
	}
	_ = b.session.Close()
	log.Println("[discord-bot] Bot disconnected")
}

// ClanSync returns the clan sync manager for external use.
func (b *Bot) ClanSync() *ClanSync {
	if b == nil {
		return nil
	}
	return b.clanSync
}

func (b *Bot) onMessageCreate(s *discordgo.Session, m *discordgo.MessageCreate) {
	// Ignore own messages
	if m.Author.ID == s.State.User.ID {
		return
	}
	if len(m.Content) == 0 || m.Content[0] != '!' {
		return
	}
	b.commands.Handle(s, m)
}
