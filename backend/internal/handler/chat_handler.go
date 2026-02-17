package handler

import (
	"log"
	"strconv"
	"strings"

	"spacegame-backend/internal/model"
	"spacegame-backend/internal/repository"

	"github.com/gofiber/fiber/v2"
)

type ChatHandler struct {
	chatRepo *repository.ChatRepository
}

func NewChatHandler(chatRepo *repository.ChatRepository) *ChatHandler {
	return &ChatHandler{chatRepo: chatRepo}
}

// PostMessage stores a single chat message.
// POST /api/v1/server/chat/messages
func (h *ChatHandler) PostMessage(c *fiber.Ctx) error {
	var req model.ChatPostRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "invalid request body"})
	}

	if req.SenderName == "" || req.Text == "" {
		log.Printf("[Chat] PostMessage rejected: empty sender_name or text")
		return c.Status(400).JSON(fiber.Map{"error": "sender_name and text are required"})
	}
	if req.Channel < 0 || req.Channel > 3 {
		log.Printf("[Chat] PostMessage rejected: invalid channel %d", req.Channel)
		return c.Status(400).JSON(fiber.Map{"error": "channel must be 0-3"})
	}

	if err := h.chatRepo.InsertMessage(c.Context(), req); err != nil {
		log.Printf("[Chat] PostMessage DB error: %v", err)
		return c.Status(500).JSON(fiber.Map{"error": "failed to store message"})
	}

	log.Printf("[Chat] Stored: ch=%d sys=%d sender='%s' text='%.40s'", req.Channel, req.SystemID, req.SenderName, req.Text)
	return c.JSON(fiber.Map{"ok": true})
}

// GetHistory returns recent chat messages for the requested channels.
// GET /api/v1/server/chat/history?channels=0,1,2,3&system_id=5&limit=50
func (h *ChatHandler) GetHistory(c *fiber.Ctx) error {
	// Parse channels
	channelsStr := c.Query("channels", "0,1,2,3")
	parts := strings.Split(channelsStr, ",")
	var channels []int
	for _, p := range parts {
		p = strings.TrimSpace(p)
		if p == "" {
			continue
		}
		ch, err := strconv.Atoi(p)
		if err != nil || ch < 0 || ch > 3 {
			continue
		}
		channels = append(channels, ch)
	}

	systemID, _ := strconv.Atoi(c.Query("system_id", "0"))
	limit, _ := strconv.Atoi(c.Query("limit", "50"))
	if limit <= 0 || limit > 200 {
		limit = 50
	}

	log.Printf("[Chat] GetHistory: channels=%v system_id=%d limit=%d", channels, systemID, limit)

	msgs, err := h.chatRepo.GetHistory(c.Context(), channels, systemID, limit)
	if err != nil {
		log.Printf("[Chat] GetHistory DB error: %v", err)
		return c.Status(500).JSON(fiber.Map{"error": "failed to get history"})
	}

	if msgs == nil {
		msgs = []model.ChatMessage{}
	}

	log.Printf("[Chat] GetHistory: returning %d messages", len(msgs))
	return c.JSON(fiber.Map{"messages": msgs})
}
