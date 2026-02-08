.PHONY: build run dev up down migrate test clean

build:
	go build -o bin/server ./cmd/server

run: build
	./bin/server

dev:
	go run ./cmd/server

up:
	docker-compose up -d

down:
	docker-compose down

up-db:
	docker-compose up -d db

logs:
	docker-compose logs -f backend

test:
	go test ./...

clean:
	rm -rf bin/
	docker-compose down -v
