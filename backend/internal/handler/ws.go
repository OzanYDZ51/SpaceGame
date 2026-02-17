package handler

import (
	"encoding/json"
	"log"
	"time"

	"spacegame-backend/internal/model"
	"spacegame-backend/internal/service"

	"github.com/gofiber/contrib/websocket"
	"github.com/gofiber/fiber/v2"
)

type WSHandler struct {
	hub       *service.WSHub
	jwtSecret string
}

func NewWSHandler(hub *service.WSHub, jwtSecret string) *WSHandler {
	return &WSHandler{hub: hub, jwtSecret: jwtSecret}
}

func (h *WSHandler) Upgrade(c *fiber.Ctx) error {
	if websocket.IsWebSocketUpgrade(c) {
		// Validate JWT from query param
		token := c.Query("token")
		if token == "" {
			return c.Status(401).JSON(fiber.Map{"error": "token required"})
		}

		authSvc := service.NewAuthService(nil, nil, h.jwtSecret)
		playerID, username, err := authSvc.ValidateAccessToken(token)
		if err != nil {
			return c.Status(401).JSON(fiber.Map{"error": "invalid token"})
		}

		c.Locals("player_id", playerID)
		c.Locals("username", username)
		return websocket.New(h.handleConnection)(c)
	}
	return fiber.ErrUpgradeRequired
}

func (h *WSHandler) handleConnection(c *websocket.Conn) {
	playerID, _ := c.Locals("player_id").(string)
	username, _ := c.Locals("username").(string)

	client := &service.WSClient{
		Conn:     c,
		PlayerID: playerID,
		Username: username,
		Send:     make(chan []byte, 256),
	}

	h.hub.Register(client)
	defer h.hub.Unregister(client)

	// Writer goroutine
	go func() {
		defer c.Close()
		for msg := range client.Send {
			if err := c.WriteMessage(websocket.TextMessage, msg); err != nil {
				break
			}
		}
	}()

	// Reader loop
	c.SetReadDeadline(time.Now().Add(60 * time.Second))
	for {
		_, msg, err := c.ReadMessage()
		if err != nil {
			break
		}

		// Reset deadline on any message
		c.SetReadDeadline(time.Now().Add(60 * time.Second))

		var event model.WSEvent
		if err := json.Unmarshal(msg, &event); err != nil {
			continue
		}

		switch event.Type {
		case "ping":
			pong, _ := json.Marshal(model.WSEvent{Type: "pong"})
			select {
			case client.Send <- pong:
			default:
			}
		case "subscribe":
			// Client can subscribe to corporation channel by sending their corporation_id
			var sub struct {
				CorporationID string `json:"corporation_id"`
			}
			if err := json.Unmarshal(event.Data, &sub); err == nil {
				client.CorporationID = sub.CorporationID
			}
		default:
			log.Printf("WS: unknown event type %s from %s", event.Type, username)
		}
	}
}
