package service

import (
	"context"
	"encoding/json"
	"log"

	"spacegame-backend/internal/repository"
)

// EventService records game events and dispatches them to Discord.
type EventService struct {
	eventRepo *repository.EventRepository
	webhooks  *DiscordWebhookService
}

func NewEventService(eventRepo *repository.EventRepository, webhooks *DiscordWebhookService) *EventService {
	return &EventService{
		eventRepo: eventRepo,
		webhooks:  webhooks,
	}
}

// RecordKill saves a kill event and sends it to the kill-feed webhook.
func (s *EventService) RecordKill(ctx context.Context, killer, victim, weapon, systemName string, systemID int) {
	details, _ := json.Marshal(map[string]string{"weapon": weapon, "system": systemName})
	_, err := s.eventRepo.Create(ctx, "kill", killer, victim, details, systemID)
	if err != nil {
		log.Printf("[events] failed to record kill: %v", err)
	}
	s.webhooks.SendKillFeed(killer, victim, weapon, systemName)
}

// RecordDiscovery saves a discovery event and sends it to the events webhook.
func (s *EventService) RecordDiscovery(ctx context.Context, player, what, systemName string, systemID int) {
	details, _ := json.Marshal(map[string]string{"discovery": what, "system": systemName})
	_, err := s.eventRepo.Create(ctx, "discovery", player, what, details, systemID)
	if err != nil {
		log.Printf("[events] failed to record discovery: %v", err)
	}
	s.webhooks.SendGameEvent("discovery",
		"🌟 Nouvelle découverte!",
		player+" a découvert "+what+" dans "+systemName,
	)
}

// RecordEconomyEvent saves an economy event and sends it to the events webhook.
func (s *EventService) RecordEconomyEvent(ctx context.Context, eventType, details string) {
	detailsJSON, _ := json.Marshal(map[string]string{"info": details})
	_, err := s.eventRepo.Create(ctx, "economy", "", "", detailsJSON, 0)
	if err != nil {
		log.Printf("[events] failed to record economy event: %v", err)
	}
	s.webhooks.SendGameEvent("economy", "💰 Événement économique", details)
}

// RecordBugReport saves a bug report and sends it to the bug-reports webhook.
func (s *EventService) RecordBugReport(ctx context.Context, reporter, title, description, system, position string, systemID int, gameVersion, screenshotB64 string) {
	detailsMap := map[string]string{
		"title":       title,
		"description": description,
		"system":      system,
		"position":    position,
		"version":     gameVersion,
	}
	if screenshotB64 != "" {
		detailsMap["screenshot_b64"] = screenshotB64
	}
	details, _ := json.Marshal(detailsMap)
	_, err := s.eventRepo.Create(ctx, "bug_report", reporter, "", details, systemID)
	if err != nil {
		log.Printf("[events] failed to record bug report: %v", err)
	}
	s.webhooks.SendBugReport(reporter, title, description, system, position, gameVersion)
}

// RecordClanEvent saves a clan event and sends it to the clan-activity webhook.
func (s *EventService) RecordClanEvent(ctx context.Context, eventType, clanName, details string) {
	detailsJSON, _ := json.Marshal(map[string]string{"clan": clanName, "info": details})
	_, err := s.eventRepo.Create(ctx, "clan_"+eventType, clanName, "", detailsJSON, 0)
	if err != nil {
		log.Printf("[events] failed to record clan event: %v", err)
	}
	s.webhooks.SendClanEvent(eventType, clanName, details)
}
