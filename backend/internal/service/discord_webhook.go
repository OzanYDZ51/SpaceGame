package service

import (
	"bytes"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"time"
)

// DiscordWebhookService sends rich embeds to Discord channels via webhooks.
type DiscordWebhookService struct {
	webhookDevlog string
	webhookStatus string
	webhookKills  string
	webhookEvents string
	webhookBugs   string
	webhookClans  string
	client        *http.Client
}

func NewDiscordWebhookService(devlog, status, kills, events, bugs, clans string) *DiscordWebhookService {
	return &DiscordWebhookService{
		webhookDevlog: devlog,
		webhookStatus: status,
		webhookKills:  kills,
		webhookEvents: events,
		webhookBugs:   bugs,
		webhookClans:  clans,
		client:        &http.Client{Timeout: 10 * time.Second},
	}
}

// discordEmbed is a Discord webhook embed.
type discordEmbed struct {
	Title       string          `json:"title,omitempty"`
	Description string          `json:"description,omitempty"`
	Color       int             `json:"color,omitempty"`
	Fields      []discordField  `json:"fields,omitempty"`
	Footer      *discordFooter  `json:"footer,omitempty"`
	Timestamp   string          `json:"timestamp,omitempty"`
	Author      *discordAuthor  `json:"author,omitempty"`
}

type discordField struct {
	Name   string `json:"name"`
	Value  string `json:"value"`
	Inline bool   `json:"inline,omitempty"`
}

type discordFooter struct {
	Text string `json:"text"`
}

type discordAuthor struct {
	Name string `json:"name"`
}

type discordWebhookPayload struct {
	Username  string         `json:"username,omitempty"`
	AvatarURL string         `json:"avatar_url,omitempty"`
	Embeds    []discordEmbed `json:"embeds"`
}

func (s *DiscordWebhookService) send(webhookURL string, payload discordWebhookPayload) {
	if webhookURL == "" {
		return
	}
	go func() {
		body, err := json.Marshal(payload)
		if err != nil {
			log.Printf("[discord-webhook] marshal error: %v", err)
			return
		}
		resp, err := s.client.Post(webhookURL, "application/json", bytes.NewReader(body))
		if err != nil {
			log.Printf("[discord-webhook] send error: %v", err)
			return
		}
		resp.Body.Close()
		if resp.StatusCode >= 400 {
			log.Printf("[discord-webhook] HTTP %d for webhook", resp.StatusCode)
		}
	}()
}

// SendDevlog posts a new version update to #devlog.
func (s *DiscordWebhookService) SendDevlog(version, summary string) {
	s.send(s.webhookDevlog, discordWebhookPayload{
		Username: "Imperion Online Devlog",
		Embeds: []discordEmbed{{
			Title:       fmt.Sprintf("🚀 Mise à jour %s", version),
			Description: summary,
			Color:       0x3498DB, // Blue
			Timestamp:   time.Now().UTC().Format(time.RFC3339),
			Footer:      &discordFooter{Text: "Imperion Online Devlog"},
		}},
	})
}

// SendServerStatus posts server online/offline status to #server-status.
func (s *DiscordWebhookService) SendServerStatus(online bool, playerCount int) {
	color := 0x2ECC71 // Green
	status := "EN LIGNE"
	if !online {
		color = 0xE74C3C // Red
		status = "HORS LIGNE"
	}
	s.send(s.webhookStatus, discordWebhookPayload{
		Username: "Imperion Online Server",
		Embeds: []discordEmbed{{
			Title: fmt.Sprintf("Serveur %s", status),
			Color: color,
			Fields: []discordField{
				{Name: "Joueurs", Value: fmt.Sprintf("%d", playerCount), Inline: true},
				{Name: "Status", Value: status, Inline: true},
			},
			Timestamp: time.Now().UTC().Format(time.RFC3339),
		}},
	})
}

// SendKillFeed posts a PvP kill to #kill-feed.
func (s *DiscordWebhookService) SendKillFeed(killer, victim, weapon, system string) {
	s.send(s.webhookKills, discordWebhookPayload{
		Username: "Imperion Online Kill Feed",
		Embeds: []discordEmbed{{
			Title:       fmt.Sprintf("💀 %s a détruit %s", killer, victim),
			Color:       0xE74C3C, // Red
			Fields: []discordField{
				{Name: "Arme", Value: weapon, Inline: true},
				{Name: "Système", Value: system, Inline: true},
			},
			Timestamp: time.Now().UTC().Format(time.RFC3339),
		}},
	})
}

// SendGameEvent posts a notable game event to #events.
func (s *DiscordWebhookService) SendGameEvent(eventType, title, description string) {
	s.send(s.webhookEvents, discordWebhookPayload{
		Username: "Imperion Online Events",
		Embeds: []discordEmbed{{
			Title:       title,
			Description: description,
			Color:       0xF1C40F, // Gold
			Fields: []discordField{
				{Name: "Type", Value: eventType, Inline: true},
			},
			Timestamp: time.Now().UTC().Format(time.RFC3339),
		}},
	})
}

// SendBugReport posts a bug report to #bug-reports.
func (s *DiscordWebhookService) SendBugReport(reporter, title, description, system, position string) {
	fields := []discordField{
		{Name: "Rapporteur", Value: reporter, Inline: true},
		{Name: "Système", Value: system, Inline: true},
		{Name: "Position", Value: position, Inline: true},
	}
	s.send(s.webhookBugs, discordWebhookPayload{
		Username: "Imperion Online Bug Reports",
		Embeds: []discordEmbed{{
			Title:       fmt.Sprintf("🐛 %s", title),
			Description: description,
			Color:       0xE67E22, // Orange
			Fields:      fields,
			Timestamp:   time.Now().UTC().Format(time.RFC3339),
		}},
	})
}

// SendClanEvent posts a clan event to #clan-activity.
func (s *DiscordWebhookService) SendClanEvent(eventType, clanName, details string) {
	s.send(s.webhookClans, discordWebhookPayload{
		Username: "Imperion Online Clans",
		Embeds: []discordEmbed{{
			Title:       fmt.Sprintf("⚔️ [%s] %s", clanName, eventType),
			Description: details,
			Color:       0x9B59B6, // Purple
			Timestamp:   time.Now().UTC().Format(time.RFC3339),
		}},
	})
}
