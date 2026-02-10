package handler

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/gofiber/fiber/v2"
)

type UpdatesHandler struct {
	owner       string
	repo        string
	githubToken string
	cache       *updatesCache
}

type updatesCache struct {
	mu   sync.RWMutex
	data *UpdatesResponse
	ts   time.Time
	ttl  time.Duration
}

type UpdatesResponse struct {
	Game     *ReleaseInfo `json:"game"`
	Launcher *ReleaseInfo `json:"launcher"`
}

type ReleaseInfo struct {
	Version     string `json:"version"`
	DownloadURL string `json:"download_url"`
	Size        int64  `json:"size"`
}

func NewUpdatesHandler(owner, repo, githubToken string) *UpdatesHandler {
	return &UpdatesHandler{
		owner:       owner,
		repo:        repo,
		githubToken: githubToken,
		cache: &updatesCache{
			ttl: 5 * time.Minute,
		},
	}
}

func (h *UpdatesHandler) GetUpdates(c *fiber.Ctx) error {
	h.cache.mu.RLock()
	if h.cache.data != nil && time.Since(h.cache.ts) < h.cache.ttl {
		data := h.cache.data
		h.cache.mu.RUnlock()
		return c.JSON(data)
	}
	h.cache.mu.RUnlock()

	resp, err := h.fetchReleases()
	if err != nil {
		return c.Status(502).JSON(fiber.Map{"error": err.Error()})
	}

	h.cache.mu.Lock()
	h.cache.data = resp
	h.cache.ts = time.Now()
	h.cache.mu.Unlock()

	return c.JSON(resp)
}

func (h *UpdatesHandler) RefreshCache(c *fiber.Ctx) error {
	h.cache.mu.Lock()
	h.cache.data = nil
	h.cache.ts = time.Time{}
	h.cache.mu.Unlock()

	resp, err := h.fetchReleases()
	if err != nil {
		return c.Status(500).JSON(fiber.Map{"error": err.Error()})
	}

	h.cache.mu.Lock()
	h.cache.data = resp
	h.cache.ts = time.Now()
	h.cache.mu.Unlock()

	return c.JSON(fiber.Map{"refreshed": true, "versions": resp})
}

func (h *UpdatesHandler) fetchReleases() (*UpdatesResponse, error) {
	url := fmt.Sprintf("https://api.github.com/repos/%s/%s/releases?per_page=100", h.owner, h.repo)

	req, _ := http.NewRequest("GET", url, nil)
	req.Header.Set("User-Agent", "ImperionOnlineBackend/1.0")
	req.Header.Set("Accept", "application/vnd.github+json")
	if h.githubToken != "" {
		req.Header.Set("Authorization", "token "+h.githubToken)
	}

	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("github request failed: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("reading github response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("github API returned %d: %s", resp.StatusCode, string(body[:min(len(body), 200)]))
	}

	var releases []ghRelease
	if err := json.Unmarshal(body, &releases); err != nil {
		return nil, fmt.Errorf("parsing github releases: %w", err)
	}

	result := &UpdatesResponse{}

	for _, rel := range releases {
		if rel.Draft || rel.Prerelease {
			continue
		}

		tag := rel.TagName

		// Game release: tag starts with "v" (not "launcher-v")
		if result.Game == nil && strings.HasPrefix(tag, "v") && !strings.HasPrefix(tag, "launcher-v") {
			for _, asset := range rel.Assets {
				if strings.HasSuffix(asset.Name, ".zip") {
					result.Game = &ReleaseInfo{
						Version:     strings.TrimPrefix(tag, "v"),
						DownloadURL: asset.BrowserDownloadURL,
						Size:        asset.Size,
					}
					break
				}
			}
		}

		// Launcher release: tag starts with "launcher-v"
		if result.Launcher == nil && strings.HasPrefix(tag, "launcher-v") {
			for _, asset := range rel.Assets {
				if strings.HasSuffix(asset.Name, ".exe") {
					result.Launcher = &ReleaseInfo{
						Version:     strings.TrimPrefix(tag, "launcher-v"),
						DownloadURL: asset.BrowserDownloadURL,
						Size:        asset.Size,
					}
					break
				}
			}
		}

		if result.Game != nil && result.Launcher != nil {
			break
		}
	}

	return result, nil
}

type ghRelease struct {
	TagName    string    `json:"tag_name"`
	Draft      bool      `json:"draft"`
	Prerelease bool      `json:"prerelease"`
	Assets     []ghAsset `json:"assets"`
}

type ghAsset struct {
	Name                string `json:"name"`
	BrowserDownloadURL  string `json:"browser_download_url"`
	Size                int64  `json:"size"`
}
