package service

import (
	"encoding/json"
	"log"
	"sync"

	"spacegame-backend/internal/model"

	"github.com/gofiber/contrib/websocket"
)

type WSClient struct {
	Conn          *websocket.Conn
	PlayerID      string
	Username      string
	CorporationID string
	Send          chan []byte
}

type WSHub struct {
	clients    map[*WSClient]bool
	register   chan *WSClient
	unregister chan *WSClient
	broadcast  chan []byte
	mu         sync.RWMutex
	done       chan struct{}
}

func NewWSHub() *WSHub {
	return &WSHub{
		clients:    make(map[*WSClient]bool),
		register:   make(chan *WSClient),
		unregister: make(chan *WSClient),
		broadcast:  make(chan []byte, 256),
		done:       make(chan struct{}),
	}
}

func (h *WSHub) Run() {
	for {
		select {
		case client := <-h.register:
			h.mu.Lock()
			h.clients[client] = true
			h.mu.Unlock()
			log.Printf("WS: %s connected (total: %d)", client.Username, len(h.clients))

		case client := <-h.unregister:
			h.mu.Lock()
			if _, ok := h.clients[client]; ok {
				delete(h.clients, client)
				close(client.Send)
			}
			h.mu.Unlock()
			log.Printf("WS: %s disconnected (total: %d)", client.Username, len(h.clients))

		case message := <-h.broadcast:
			h.mu.Lock()
			for client := range h.clients {
				select {
				case client.Send <- message:
				default:
					close(client.Send)
					delete(h.clients, client)
				}
			}
			h.mu.Unlock()

		case <-h.done:
			return
		}
	}
}

func (h *WSHub) Shutdown() {
	close(h.done)
}

func (h *WSHub) Register(client *WSClient) {
	h.register <- client
}

func (h *WSHub) Unregister(client *WSClient) {
	h.unregister <- client
}

func (h *WSHub) Broadcast(event *model.WSEvent) {
	data, err := json.Marshal(event)
	if err != nil {
		return
	}
	h.broadcast <- data
}

func (h *WSHub) BroadcastToCorporation(corporationID string, event *model.WSEvent) {
	data, err := json.Marshal(event)
	if err != nil {
		return
	}

	h.mu.RLock()
	defer h.mu.RUnlock()

	for client := range h.clients {
		if client.CorporationID == corporationID {
			select {
			case client.Send <- data:
			default:
			}
		}
	}
}

func (h *WSHub) OnlineCount() int {
	h.mu.RLock()
	defer h.mu.RUnlock()
	return len(h.clients)
}
