package middleware

import (
	"io"
	"os"
	"strconv"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/fiber/v2/middleware/logger"
)

// Logger returns a Fiber middleware that only logs slow or failed requests
// to stay within Railway's 500 logs/sec rate limit.
func Logger() fiber.Handler {
	return logger.New(logger.Config{
		Format:     "${time} | ${status} | ${latency} | ${method} ${path}\n",
		TimeFormat: "15:04:05",
		Output: &filteredWriter{
			dest:             os.Stdout,
			slowThresholdMs:  500,
			errorStatusFloor: 400,
		},
	})
}

// filteredWriter discards log lines for fast, successful requests.
// Only writes when the response is slow (>500ms) or has an error status (>=400).
// It parses the status and latency from the log line format:
//
//	"15:04:05 | 200 | 1.23ms | GET /path\n"
type filteredWriter struct {
	dest             io.Writer
	slowThresholdMs  float64
	errorStatusFloor int
}

func (w *filteredWriter) Write(p []byte) (n int, err error) {
	line := string(p)
	// Parse: "HH:MM:SS | STATUS | LATENCY | METHOD PATH\n"
	// Find segments between " | "
	parts := splitParts(line)
	if len(parts) < 3 {
		return w.dest.Write(p) // Can't parse — write anyway
	}

	statusStr := parts[1]
	latencyStr := parts[2]

	// Check status >= 400
	status, _ := strconv.Atoi(statusStr)
	if status >= w.errorStatusFloor {
		return w.dest.Write(p)
	}

	// Check latency > threshold
	dur, err2 := time.ParseDuration(latencyStr)
	if err2 == nil && dur.Seconds()*1000 >= w.slowThresholdMs {
		return w.dest.Write(p)
	}

	// Discard (fast + successful)
	return len(p), nil
}

// splitParts splits "a | b | c | d" into trimmed segments.
func splitParts(s string) []string {
	var parts []string
	for {
		idx := indexOf(s, " | ")
		if idx < 0 {
			parts = append(parts, trim(s))
			break
		}
		parts = append(parts, trim(s[:idx]))
		s = s[idx+3:]
	}
	return parts
}

func indexOf(s, sep string) int {
	for i := 0; i <= len(s)-len(sep); i++ {
		if s[i:i+len(sep)] == sep {
			return i
		}
	}
	return -1
}

func trim(s string) string {
	start, end := 0, len(s)
	for start < end && (s[start] == ' ' || s[start] == '\n' || s[start] == '\r') {
		start++
	}
	for end > start && (s[end-1] == ' ' || s[end-1] == '\n' || s[end-1] == '\r') {
		end--
	}
	return s[start:end]
}
