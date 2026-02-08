#!/bin/bash
# =============================================================================
# SpaceGame — Railway Full Deployment Script
#
# Provisions all 3 services + database on Railway from scratch.
# Run from project root: bash deploy/railway-setup.sh
#
# Prerequisites:
#   - Railway CLI: npm i -g @railway/cli
#   - GitHub repo with project pushed
# =============================================================================

set -e

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════╗"
echo "║     SpaceGame — Railway Deployment Setup     ║"
echo "╚══════════════════════════════════════════════╝"
echo -e "${NC}"

# --- Check prerequisites ---
if ! command -v railway &> /dev/null; then
    echo -e "${RED}Railway CLI not found.${NC}"
    echo "Install: npm i -g @railway/cli"
    exit 1
fi

if ! command -v openssl &> /dev/null; then
    # Fallback to /dev/urandom if openssl not available
    gen_secret() { head -c 32 /dev/urandom | xxd -p | tr -d '\n'; }
else
    gen_secret() { openssl rand -hex "$1"; }
fi

# --- GitHub repo URL ---
REPO_URL=$(git remote get-url origin 2>/dev/null || echo "")
if [ -z "$REPO_URL" ]; then
    echo -e "${RED}No git remote 'origin' found. Push your project to GitHub first.${NC}"
    exit 1
fi
echo -e "${GREEN}GitHub repo:${NC} $REPO_URL"
echo ""

# --- Generate secrets ---
JWT_SECRET=$(gen_secret 32)
SERVER_KEY=$(gen_secret 16)
ADMIN_KEY=$(gen_secret 16)

echo -e "${YELLOW}Generated secrets (save these!):${NC}"
echo "  JWT_SECRET  = $JWT_SECRET"
echo "  SERVER_KEY  = $SERVER_KEY"
echo "  ADMIN_KEY   = $ADMIN_KEY"
echo ""

# --- Step 1: Login ---
echo -e "${CYAN}[1/6] Railway Login${NC}"
railway login
echo ""

# --- Step 2: Create project ---
echo -e "${CYAN}[2/6] Creating Railway project...${NC}"
railway init --name spacegame
echo ""

# --- Step 3: Add PostgreSQL ---
echo -e "${CYAN}[3/6] Adding PostgreSQL database...${NC}"
railway add --database postgres
echo ""

# --- Step 4: Create Backend service ---
echo -e "${CYAN}[4/6] Creating Go Backend service...${NC}"
railway add --repo "$REPO_URL" --service backend
echo ""

echo "Setting backend environment variables..."
railway variables \
    --set "DATABASE_URL=\${{Postgres.DATABASE_URL}}" \
    --set "JWT_SECRET=$JWT_SECRET" \
    --set "SERVER_KEY=$SERVER_KEY" \
    --set "ADMIN_KEY=$ADMIN_KEY" \
    --set "ENV=production" \
    --service backend
echo ""

echo "Setting backend root directory to 'backend'..."
echo -e "${YELLOW}NOTE: Set Root Directory to 'backend' in Railway dashboard > backend service > Settings${NC}"
echo ""

echo "Generating backend domain..."
BACKEND_DOMAIN=$(railway domain --service backend --json 2>/dev/null | grep -o '"domain":"[^"]*"' | cut -d'"' -f4 || echo "")
if [ -n "$BACKEND_DOMAIN" ]; then
    echo -e "${GREEN}Backend URL:${NC} https://$BACKEND_DOMAIN"
else
    echo -e "${YELLOW}Generate domain manually: Railway dashboard > backend > Settings > Networking > Generate Domain${NC}"
fi
echo ""

# --- Step 5: Create Game Server service ---
echo -e "${CYAN}[5/6] Creating Godot Game Server service...${NC}"
railway add --repo "$REPO_URL" --service gameserver
echo ""

echo "Setting game server environment variables..."
railway variables \
    --set "PORT=7777" \
    --service gameserver
echo ""

echo "Setting game server Dockerfile path..."
echo -e "${YELLOW}NOTE: In Railway dashboard > gameserver > Settings:${NC}"
echo -e "${YELLOW}  - Root Directory: (leave empty)${NC}"
echo -e "${YELLOW}  - Dockerfile Path: gameserver/Dockerfile${NC}"
echo ""

echo "Generating game server domain..."
GS_DOMAIN=$(railway domain --service gameserver --json 2>/dev/null | grep -o '"domain":"[^"]*"' | cut -d'"' -f4 || echo "")
if [ -n "$GS_DOMAIN" ]; then
    echo -e "${GREEN}Game Server URL:${NC} wss://$GS_DOMAIN"
else
    echo -e "${YELLOW}Generate domain manually: Railway dashboard > gameserver > Settings > Networking > Generate Domain${NC}"
fi
echo ""

# --- Step 6: Summary ---
echo -e "${CYAN}[6/6] Deployment Summary${NC}"
echo "═══════════════════════════════════════════════"
echo ""
echo "Services created:"
echo "  1. PostgreSQL        — managed by Railway"
echo "  2. Go Backend        — REST API + WebSocket events"
echo "  3. Godot Game Server — WebSocket multiplayer"
echo ""

if [ -n "$BACKEND_DOMAIN" ] && [ -n "$GS_DOMAIN" ]; then
    echo -e "${GREEN}Update scripts/core/constants.gd with:${NC}"
    echo ""
    echo "const BACKEND_URL_PROD: String = \"https://$BACKEND_DOMAIN\""
    echo "const BACKEND_WS_PROD: String = \"wss://$BACKEND_DOMAIN/ws\""
    echo "const NET_GAME_SERVER_URL: String = \"wss://$GS_DOMAIN\""
    echo ""
else
    echo -e "${YELLOW}After generating domains in Railway dashboard, update constants.gd:${NC}"
    echo ""
    echo 'const BACKEND_URL_PROD: String = "https://<backend-domain>.up.railway.app"'
    echo 'const BACKEND_WS_PROD: String = "wss://<backend-domain>.up.railway.app/ws"'
    echo 'const NET_GAME_SERVER_URL: String = "wss://<gameserver-domain>.up.railway.app"'
    echo ""
fi

echo -e "${YELLOW}Manual steps remaining:${NC}"
echo "  1. In Railway dashboard, set Root Directory for backend service to 'backend'"
echo "  2. In Railway dashboard, set Dockerfile Path for gameserver to 'gameserver/Dockerfile'"
echo "  3. Verify both services deploy successfully (check logs)"
echo "  4. Update constants.gd with the Railway URLs"
echo "  5. Push the constants.gd update → triggers redeploy"
echo ""
echo -e "${GREEN}Secrets (save in a safe place!):${NC}"
echo "  JWT_SECRET  = $JWT_SECRET"
echo "  SERVER_KEY  = $SERVER_KEY"
echo "  ADMIN_KEY   = $ADMIN_KEY"
echo ""
echo -e "${CYAN}Done! Check Railway dashboard: https://railway.app/dashboard${NC}"
