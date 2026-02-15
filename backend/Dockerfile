FROM golang:1.23-alpine AS builder
WORKDIR /app

# Cache Go modules (only re-downloaded if go.mod/go.sum change)
COPY go.mod go.sum* ./
RUN go mod download

# Build
COPY . .
RUN go mod tidy && CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /server ./cmd/server

# Minimal runtime image
FROM alpine:3.19
RUN apk add --no-cache ca-certificates tzdata
COPY --from=builder /server /server
COPY migrations /migrations
COPY discord.json /discord.json
EXPOSE 3000
ENTRYPOINT ["/server"]
