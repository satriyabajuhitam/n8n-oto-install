#!/bin/bash
# ============================================================
# n8n Universal Auto-Install Script v4.0
# Clean installation on Ubuntu 22.04 / 24.04
# ============================================================
# Components: n8n 2.x + PostgreSQL 16 + Redis 7 + Traefik v3
#             + Telegram Bot
#             + FFmpeg + Python3 + Chromium + Tesseract OCR
#             + 30+ npm-libraries for AI/ML/automation
# ============================================================

set -euo pipefail

# ─── Colors ───────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC}  $(date '+%H:%M:%S') $1"; }
log_ok()      { echo -e "${GREEN}[OK]${NC}    $(date '+%H:%M:%S') $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $(date '+%H:%M:%S') $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $(date '+%H:%M:%S') $1"; }
log_step() {
    local title="$1"
    local width=52
    local line; line=$(printf '─%.0s' $(seq 1 $width))
    echo ""
    echo -e "${CYAN}${BOLD}┌${line}┐${NC}"
    printf "${CYAN}${BOLD}│${NC}  %-${width}s${CYAN}${BOLD}│${NC}\n" "$title"
    echo -e "${CYAN}${BOLD}└${line}┘${NC}"
    echo ""
}

# ─── Spinner (run in background, call after launching a background job) ────
spinner() {
    local msg="${1:-Working...}"
    local frames=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
    local i=0
    while kill -0 "$SPINNER_PID" 2>/dev/null; do
        echo -ne "\r  ${CYAN}${frames[$i]}${NC}  ${msg}"
        i=$(( (i+1) % ${#frames[@]} ))
        sleep 0.12
    done
    echo -ne "\r$(printf ' %.0s' $(seq 1 $((${#msg}+8))))\r"
}

# ─── Timer ─────────────────────────────────────────────────────
START_TIME=$(date +%s)

# ─── Error Trap ──────────────────────────────────────────
trap 'log_error "Script interrupted at line $LINENO. Last command: $BASH_COMMAND"' ERR

# ─── Installation Directory ────────────────────────────────────
INSTALL_DIR="/opt/automator/n8n"

# ─── Persistent Log File ───────────────────────────────────────
mkdir -p /var/log
LOG_FILE="/var/log/n8n_install_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Install log started → $LOG_FILE"

# ============================================================
# PREFLIGHT CHECKS
# ============================================================
log_step "Preflight checks"

# Root
if [[ $EUID -ne 0 ]]; then
    log_error "Run as root: sudo bash install.sh"
    exit 1
fi

# OS
if ! grep -qE "Ubuntu (22|24)" /etc/os-release 2>/dev/null; then
    log_warn "Ubuntu 22.04 or 24.04 is recommended. Current OS may not be supported."
    read -p "Continue anyway? (y/n): " -r
    [[ ! $REPLY =~ ^[Yy]$ ]] && exit 0
fi

# Disk Space
DISK_FREE=$(df -BG / | awk 'NR==2{print $4}' | tr -d 'G')
if (( DISK_FREE < 10 )); then
    log_error "Insufficient disk space: ${DISK_FREE}G free (need at least 10G)"
    exit 1
fi

log_ok "OS: $(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)"
log_ok "Disk free: ${DISK_FREE}G"

# ============================================================
# BANNER
# ============================================================
clear
echo ""
echo -e "${CYAN}"
cat << 'BANNER'
    ███╗   ██╗ █████╗ ███╗   ██╗
    ████╗  ██║██╔══██╗████╗  ██║
    ██╔██╗ ██║╚█████╔╝██╔██╗ ██║
    ██║╚██╗██║██╔══██╗██║╚██╗██║
    ██║ ╚████║╚█████╔╝██║ ╚████║
    ╚═╝  ╚═══╝ ╚════╝ ╚═╝  ╚═══╝
BANNER
echo -e "${NC}"
echo -e "${BOLD}    Universal Auto-Install v4.0${NC}"
echo -e "    n8n 2.x + PostgreSQL + Redis + Traefik SSL + Telegram Bot"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ============================================================
# INPUT DATA
# ============================================================
log_step "Configuration  ─  Step 0/11"

# --- 1. n8n Domain ---
echo -e "  ${BOLD}[1/4] Domain${NC}  ${DIM}(e.g. n8n.example.com)${NC}"
echo -e "  ${RED}●${NC} Required — must have a valid DNS A-record pointing to this server"
read -p "  → Domain: " DOMAIN
while [[ -z "$DOMAIN" ]]; do
    log_error "Domain cannot be empty"
    read -p "  → Domain: " DOMAIN
done
echo ""

# --- 2. Email ---
echo -e "  ${BOLD}[2/4] Email${NC}  ${DIM}(used for Let's Encrypt SSL certificate)${NC}"
echo -e "  ${RED}●${NC} Required"
read -p "  → Email: " EMAIL
while ! echo "$EMAIL" | grep -qE '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'; do
    log_error "Invalid email format. Example: user@example.com"
    read -p "  → Email: " EMAIL
done
echo ""

# --- 3. Telegram Bot Token ---
echo -e "  ${BOLD}[3/4] Telegram Bot Token${NC}  ${DIM}(obtain from @BotFather on Telegram)${NC}"
echo -e "  ${YELLOW}○${NC} Optional — press Enter to skip, can be added later in .env"
read -p "  → Bot Token: " TG_BOT_TOKEN
TG_BOT_TOKEN="${TG_BOT_TOKEN:-}"
echo ""

# --- 4. Telegram User ID ---
echo -e "  ${BOLD}[4/4] Telegram User ID${NC}  ${DIM}(obtain from @userinfobot on Telegram)${NC}"
echo -e "  ${YELLOW}○${NC} Optional — press Enter to skip"
read -p "  → User ID: " TG_USER_ID
TG_USER_ID="${TG_USER_ID:-}"
echo ""

if [[ -z "$TG_BOT_TOKEN" ]] || [[ -z "$TG_USER_ID" ]]; then
    log_warn "Telegram bot not configured (can be added later in .env)"
fi

# ============================================================
# AUTOGENERATION OF PARAMETERS
# ============================================================
log_step "Generating configuration"

# Passwords and keys
DB_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
ENCRYPTION_KEY=$(openssl rand -hex 32)
REDIS_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
log_ok "Passwords and encryption key generated"

# Timezone and proxy — defaults
TIMEZONE="Asia/Jakarta"
PROXY_URL=""

# ============================================================
# CONFIRMATION
# ============================================================

# Detect public IP
PUBLIC_IP=$(curl -sf --max-time 5 https://api.ipify.org || \
            curl -sf --max-time 5 https://ifconfig.me || \
            echo "not detected")

echo ""
echo -e "${CYAN}${BOLD}┌──────────────────────────────────────────────────────┐${NC}"
echo -e "${CYAN}${BOLD}│${NC}            ${BOLD}Installation Summary${NC}              ${CYAN}${BOLD}│${NC}"
echo -e "${CYAN}${BOLD}├──────────────────────────────────────────────────────┤${NC}"
printf "${CYAN}${BOLD}│${NC}  %-16s ${CYAN}%-33s${NC} ${CYAN}${BOLD}│${NC}\n" "Domain" "https://${DOMAIN}"
printf "${CYAN}${BOLD}│${NC}  %-16s %-33s ${CYAN}${BOLD}│${NC}\n" "SSL Email" "${EMAIL}"
printf "${CYAN}${BOLD}│${NC}  %-16s %-33s ${CYAN}${BOLD}│${NC}\n" "Timezone" "${TIMEZONE}"
if [ -n "$TG_BOT_TOKEN" ]; then
    printf "${CYAN}${BOLD}│${NC}  %-16s ${GREEN}%-33s${NC} ${CYAN}${BOLD}│${NC}\n" "Telegram Bot" "✅ Enabled"
else
    printf "${CYAN}${BOLD}│${NC}  %-16s ${YELLOW}%-33s${NC} ${CYAN}${BOLD}│${NC}\n" "Telegram Bot" "⏭ Skipped"
fi
printf "${CYAN}${BOLD}│${NC}  %-16s %-33s ${CYAN}${BOLD}│${NC}\n" "Directory" "${INSTALL_DIR}"
printf "${CYAN}${BOLD}│${NC}  %-16s %-33s ${CYAN}${BOLD}│${NC}\n" "Server IP" "${PUBLIC_IP}"
echo -e "${CYAN}${BOLD}├──────────────────────────────────────────────────────┤${NC}"
echo -e "${CYAN}${BOLD}│${NC}  ${YELLOW}⚠  DNS A-record for ${DOMAIN} must point to ${PUBLIC_IP}${NC}"
echo -e "${CYAN}${BOLD}└──────────────────────────────────────────────────────┘${NC}"
echo ""
read -p "  Start installation? (y/n): " -r
[[ ! $REPLY =~ ^[Yy]$ ]] && { echo "  Cancelled."; exit 0; }

# ============================================================
# 1. SYSTEM UPDATE
# ============================================================
log_step "1/11 · Updating system"

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get upgrade -y -qq
apt-get install -y -qq \
    apt-transport-https ca-certificates curl gnupg lsb-release \
    git jq openssl cron software-properties-common

log_ok "System updated"

# ============================================================
# 2. SWAP SETUP
# ============================================================
log_step "2/11 · Configuring SWAP"

TOTAL_RAM=$(free -m | awk '/^Mem:/{print $2}')

if swapon --show | grep -q '/'; then
    SWAP_SIZE=$(free -m | awk '/^Swap:/{print $2}')
    log_ok "SWAP already configured: ${SWAP_SIZE}MB"
else
    if (( TOTAL_RAM < 4096 )); then
        SWAP_GB=4
    else
        SWAP_GB=2
    fi
    log_info "Creating SWAP ${SWAP_GB}GB (RAM: ${TOTAL_RAM}MB)..."

    fallocate -l ${SWAP_GB}G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile

    if ! grep -q '/swapfile' /etc/fstab; then
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi

    sysctl -w vm.swappiness=10 > /dev/null
    grep -q 'vm.swappiness' /etc/sysctl.conf || echo 'vm.swappiness=10' >> /etc/sysctl.conf

    log_ok "SWAP ${SWAP_GB}GB created"
fi

# ============================================================
# 3. INSTALL DOCKER
# ============================================================
log_step "3/11 · Installing Docker Engine"

if command -v docker &>/dev/null && docker --version &>/dev/null; then
    log_ok "Docker already installed: $(docker --version)"
else
    # Remove old versions
    for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
        apt-get remove -y -qq "$pkg" 2>/dev/null || true
    done

    # Add Docker repository
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
        $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
        tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update -qq
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    systemctl enable docker
    systemctl start docker

    # Wait for startup
    for i in {1..10}; do
        systemctl is-active --quiet docker && break
        sleep 1
    done

    log_ok "Docker installed: $(docker --version)"
fi

# Check Docker Compose
if ! docker compose version &>/dev/null; then
    log_error "Docker Compose plugin not installed"
    exit 1
fi
log_ok "Docker Compose: $(docker compose version --short)"

# ============================================================
# 4. DIRECTORY STRUCTURE
# ============================================================
log_step "4/11 · Creating project structure"

mkdir -p "$INSTALL_DIR"/{bot,logs,backups,shims,n8n-files,data}

# Permissions for n8n (UID 1000 = node user in container)
chown -R 1000:1000 "$INSTALL_DIR/n8n-files"
chown -R 1000:1000 "$INSTALL_DIR/data"
chmod -R u+rwX,g+rwX "$INSTALL_DIR/n8n-files"
chmod -R u+rwX,g+rwX "$INSTALL_DIR/data"

log_ok "Structure created: $INSTALL_DIR"

# ============================================================
# 5. .ENV FILE
# ============================================================
log_step "5/11 · Creating .env configuration"

cat > "$INSTALL_DIR/.env" << ENVEOF
# ============================================================
# n8n v4 — Full Configuration
# Created: $(date '+%Y-%m-%d %H:%M:%S')
# ============================================================

# ─── DOMAIN ───────────────────────────────────────────────────
DOMAIN=${DOMAIN}

# ─── SSL ─────────────────────────────────────────────────────
EMAIL=${EMAIL}

# ─── POSTGRESQL ──────────────────────────────────────────────
POSTGRES_USER=n8n
POSTGRES_PASSWORD=${DB_PASSWORD}
POSTGRES_DB=n8n

# ─── REDIS ───────────────────────────────────────────────────
REDIS_PASSWORD=${REDIS_PASSWORD}

# ─── N8N CORE ───────────────────────────────────────────────
N8N_ENCRYPTION_KEY=${ENCRYPTION_KEY}
WEBHOOK_URL=https://${DOMAIN}/

# Binary data: gunakan 'default' (in-memory/DB) karena
# queue mode TIDAK kompatibel dengan 'filesystem' mode.
# Ref: https://docs.n8n.io/hosting/scaling/queue-mode/
N8N_BINARY_DATA_MODE=default
N8N_DEFAULT_BINARY_DATA_MODE=default

# Proxy settings untuk Traefik (1 layer reverse proxy)
# N8N_PROXY_HOPS=1 sudah cukup, tidak perlu TRUSTED_PROXIES=*
N8N_PROXY_HOPS=1

# ─── N8N 2.x SECURITY ──────────────────────────────────────
# Execute Command and Local File Trigger allowed
NODES_EXCLUDE=[]
# Whitelist of paths for Read/Write Binary Files
N8N_RESTRICT_FILE_ACCESS_TO="/home/node/.n8n-files;/data"
# Offload manual executions to workers (recommended for scaling mode)
OFFLOAD_MANUAL_EXECUTIONS_TO_WORKERS=true

# ─── N8N LIMITS ─────────────────────────────────────────────
N8N_PAYLOAD_SIZE_MAX=512
N8N_FORMDATA_FILE_SIZE_MAX=2048
# N8N_RUNNERS_TASK_TIMEOUT bukan env var untuk container n8n.
# Timeout eksekusi diatur via EXECUTIONS_TIMEOUT di bawah.
EXECUTIONS_TIMEOUT=-1
EXECUTIONS_TIMEOUT_MAX=14400

# Community packages
N8N_COMMUNITY_PACKAGES_ENABLED=true

# ─── EXTERNAL PROXY ────────────────────────────────────────
PROXY_URL=${PROXY_URL}
NO_PROXY=localhost,127.0.0.1,::1,.local,postgres,redis,traefik,n8n,n8n-postgres,n8n-redis,n8n-traefik

# ─── TELEGRAM BOT ──────────────────────────────────────────
TG_BOT_TOKEN=${TG_BOT_TOKEN}
TG_USER_ID=${TG_USER_ID}

# ─── BACKUPS ────────────────────────────────────────────────
BACKUP_RETENTION_DAYS=7

# ─── TIMEZONE ──────────────────────────────────────────────
GENERIC_TIMEZONE=${TIMEZONE}
TZ=${TIMEZONE}

# ─── N8N MISC ──────────────────────────────────────────────
N8N_METRICS=false
N8N_LOG_LEVEL=info
# false = tidak kirim telemetri ke n8n.
# CATATAN: jika false, fitur "Ask AI" di Code node tidak aktif.
N8N_DIAGNOSTICS_ENABLED=false
N8N_PERSONALIZATION_ENABLED=false

# ─── CODE NODE MODULES ─────────────────────────────────────
# Built-in Node.js modules yang diizinkan di Code node
NODE_FUNCTION_ALLOW_BUILTIN=crypto,fs,path,url,util,stream,buffer,os,querystring,zlib
# External npm modules yang diizinkan di Code node
NODE_FUNCTION_ALLOW_EXTERNAL=axios,node-fetch,form-data,date-fns,lodash,fs-extra,csv-parser,xml2js,js-yaml,xlsx,jsonwebtoken,uuid,openai,ioredis,validator,winston,dotenv

# ─── QUEUE MODE ────────────────────────────────────────────
EXECUTIONS_MODE=queue
QUEUE_BULL_REDIS_HOST=n8n-redis
QUEUE_BULL_REDIS_PORT=6379
QUEUE_BULL_REDIS_PASSWORD=${REDIS_PASSWORD}
ENVEOF

chmod 600 "$INSTALL_DIR/.env"
log_ok ".env created"

# ============================================================
# 6. DOCKERFILE.N8N
# ============================================================
log_step "6/11 · Creating Dockerfile.n8n"

# Determine host Docker GID
DOCKER_GID=$(getent group docker | cut -d: -f3 || echo "999")

cat > "$INSTALL_DIR/Dockerfile.n8n" << 'DEOF'
# ============================================================
# n8n Custom Build — Multi-Stage (Hardened Image)
# Stage 1: Alpine builder — install all packages
# Stage 2: Hardened n8n — copy tools via tar
# ============================================================

# ─── STAGE 1: Builder ──────────────────────────────────────
FROM alpine:3.21 AS builder

RUN apk add --no-cache \
    bash curl wget git make g++ gcc \
    jq apache2-utils

# Pack tools into tar (follow symlinks with -h)
RUN mkdir -p /export && tar chf /export/tools.tar \
    /usr/bin/jq \
    /usr/bin/htpasswd \
    /usr/lib/lib*.so* \
    /lib/lib*.so* \
    2>/dev/null ; true

# ─── STAGE 2: Hardened n8n ─────────────────────────────────
FROM docker.n8n.io/n8nio/n8n:latest

USER root

# Extract tools
COPY --from=builder /export/tools.tar /tmp/tools.tar
RUN tar xf /tmp/tools.tar -C / 2>/dev/null ; rm -f /tmp/tools.tar ; true

# ─── Docker group ──────────────────────────────────────────
ARG DOCKER_GID=999
RUN set -eux; \
    addgroup -S -g ${DOCKER_GID} docker 2>/dev/null || true; \
    adduser node docker 2>/dev/null || true

# ─── npm config ─────────────────────────────────────────────
RUN npm config set fund false && npm config set audit false

# ─── npm global packages ──────────────────────────────────
RUN for pkg in \
    axios node-fetch form-data \
    date-fns lodash \
    fs-extra csv-parser xml2js js-yaml xlsx \
    jsonwebtoken uuid \
    openai \
    node-telegram-bot-api \
    ioredis \
    validator \
    winston dotenv \
  ; do \
    echo "📦 $pkg..." && npm install -g "$pkg" 2>/dev/null || echo "⚠️  skip $pkg"; \
  done

# ─── Local packages for Code-nodes ─────────────────────────
RUN cd /tmp && npm install oauth-1.0a && \
    cp -r node_modules/oauth-1.0a /usr/local/lib/node_modules/ && \
    rm -rf /tmp/node_modules /tmp/package*.json

ENV N8N_USER_FOLDER=/home/node/.n8n

USER node
WORKDIR /home/node
DEOF

log_ok "Dockerfile.n8n created"

# ============================================================
# 7. DOCKER-COMPOSE.YML
# ============================================================
log_step "7/11 · Creating docker-compose.yml"

cat > "$INSTALL_DIR/docker-compose.yml" << 'COMPOSEOF'
# ============================================================
# n8n Full Stack — docker-compose.yml
# ============================================================

x-n8n-env: &n8n-env
  # Domain
  N8N_HOST: ${DOMAIN}
  N8N_PORT: 5678
  N8N_PROTOCOL: https
  WEBHOOK_URL: ${WEBHOOK_URL}
  # Encryption
  N8N_ENCRYPTION_KEY: ${N8N_ENCRYPTION_KEY}
  # PostgreSQL
  DB_TYPE: postgresdb
  DB_POSTGRESDB_HOST: n8n-postgres
  DB_POSTGRESDB_PORT: 5432
  DB_POSTGRESDB_DATABASE: ${POSTGRES_DB}
  DB_POSTGRESDB_USER: ${POSTGRES_USER}
  DB_POSTGRESDB_PASSWORD: ${POSTGRES_PASSWORD}
  # Redis queue
  EXECUTIONS_MODE: ${EXECUTIONS_MODE}
  QUEUE_BULL_REDIS_HOST: ${QUEUE_BULL_REDIS_HOST}
  QUEUE_BULL_REDIS_PORT: ${QUEUE_BULL_REDIS_PORT}
  QUEUE_BULL_REDIS_PASSWORD: ${REDIS_PASSWORD}
  # Binary data
  N8N_BINARY_DATA_MODE: ${N8N_BINARY_DATA_MODE}
  N8N_DEFAULT_BINARY_DATA_MODE: ${N8N_DEFAULT_BINARY_DATA_MODE}
  # Proxy (Traefik)
  N8N_EXPRESS_TRUST_PROXY: ${N8N_EXPRESS_TRUST_PROXY}
  N8N_TRUSTED_PROXIES: ${N8N_TRUSTED_PROXIES}
  N8N_PROXY_HOPS: ${N8N_PROXY_HOPS}
  # External Proxy
  HTTP_PROXY: ${PROXY_URL:-}
  HTTPS_PROXY: ${PROXY_URL:-}
  NO_PROXY: ${NO_PROXY}
  # Timezone
  GENERIC_TIMEZONE: ${GENERIC_TIMEZONE}
  TZ: ${TZ}
  # Misc
  N8N_METRICS: ${N8N_METRICS}
  N8N_LOG_LEVEL: ${N8N_LOG_LEVEL}
  N8N_DIAGNOSTICS_ENABLED: ${N8N_DIAGNOSTICS_ENABLED}
  N8N_PERSONALIZATION_ENABLED: ${N8N_PERSONALIZATION_ENABLED}
  # Code node modules
  NODE_FUNCTION_ALLOW_BUILTIN: ${NODE_FUNCTION_ALLOW_BUILTIN}
  NODE_FUNCTION_ALLOW_EXTERNAL: ${NODE_FUNCTION_ALLOW_EXTERNAL}
  # n8n 2.x security
  NODES_EXCLUDE: ${NODES_EXCLUDE}
  N8N_RESTRICT_FILE_ACCESS_TO: ${N8N_RESTRICT_FILE_ACCESS_TO}
  OFFLOAD_MANUAL_EXECUTIONS_TO_WORKERS: ${OFFLOAD_MANUAL_EXECUTIONS_TO_WORKERS:-true}
  # Limits
  N8N_PAYLOAD_SIZE_MAX: ${N8N_PAYLOAD_SIZE_MAX:-512}
  N8N_FORMDATA_FILE_SIZE_MAX: ${N8N_FORMDATA_FILE_SIZE_MAX:-2048}
  N8N_RUNNERS_TASK_TIMEOUT: ${N8N_RUNNERS_TASK_TIMEOUT:-1800}
  EXECUTIONS_TIMEOUT: ${EXECUTIONS_TIMEOUT:--1}
  EXECUTIONS_TIMEOUT_MAX: ${EXECUTIONS_TIMEOUT_MAX:-14400}
  N8N_COMMUNITY_PACKAGES_ENABLED: ${N8N_COMMUNITY_PACKAGES_ENABLED:-true}

x-n8n-volumes: &n8n-volumes
  - n8n_data:/home/node/.n8n
  - ./logs:/logs
  - ./n8n-files:/home/node/.n8n-files
  - ./data:/data

services:
  # ──────────────────────────────────────────────────────────
  # n8n — Main Application
  # ──────────────────────────────────────────────────────────
  n8n:
    build:
      context: .
      dockerfile: Dockerfile.n8n
      args:
        DOCKER_GID: ${DOCKER_GID:-999}
    container_name: n8n
    restart: unless-stopped
    environment:
      <<: *n8n-env
    volumes:
      - n8n_data:/home/node/.n8n
      - ./logs:/logs
      - ./n8n-files:/home/node/.n8n-files
      - ./data:/data
      - /var/run/docker.sock:/var/run/docker.sock:ro
    depends_on:
      n8n-postgres:
        condition: service_healthy
      n8n-redis:
        condition: service_healthy
    labels:
      - "traefik.enable=true"
      # HTTPS
      - "traefik.http.routers.n8n.rule=Host(`${DOMAIN}`)"
      - "traefik.http.routers.n8n.entrypoints=websecure"
      - "traefik.http.routers.n8n.tls.certresolver=letsencrypt"
      - "traefik.http.services.n8n.loadbalancer.server.port=5678"
      # HTTP → HTTPS redirect
      - "traefik.http.routers.n8n-http.rule=Host(`${DOMAIN}`)"
      - "traefik.http.routers.n8n-http.entrypoints=web"
      - "traefik.http.routers.n8n-http.middlewares=redirect-https"
      - "traefik.http.middlewares.redirect-https.redirectscheme.scheme=https"
      - "traefik.http.middlewares.redirect-https.redirectscheme.permanent=true"
      # Security headers
      - "traefik.http.routers.n8n.middlewares=secHeaders@docker"
      - "traefik.http.middlewares.secHeaders.headers.stsSeconds=31536000"
      - "traefik.http.middlewares.secHeaders.headers.stsIncludeSubdomains=true"
      - "traefik.http.middlewares.secHeaders.headers.stsPreload=true"
      - "traefik.http.middlewares.secHeaders.headers.forceSTSHeader=true"
      - "traefik.http.middlewares.secHeaders.headers.contentTypeNosniff=true"
      - "traefik.http.middlewares.secHeaders.headers.browserXssFilter=true"
      - "traefik.http.middlewares.secHeaders.headers.referrerPolicy=strict-origin-when-cross-origin"
    networks:
      - n8n-net
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:5678/healthz"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 90s

  # ──────────────────────────────────────────────────────────
  # n8n-worker — Worker for queue mode
  # ──────────────────────────────────────────────────────────
  n8n-worker:
    build:
      context: .
      dockerfile: Dockerfile.n8n
      args:
        DOCKER_GID: ${DOCKER_GID:-999}
    container_name: n8n-worker
    restart: unless-stopped
    command: worker
    environment:
      <<: *n8n-env
    volumes:
      - n8n_data:/home/node/.n8n
      - ./logs:/logs
      - ./n8n-files:/home/node/.n8n-files
      - ./data:/data
      - /var/run/docker.sock:/var/run/docker.sock:ro
    depends_on:
      n8n:
        condition: service_healthy
    networks:
      - n8n-net

  # ──────────────────────────────────────────────────────────
  # PostgreSQL 16
  # ──────────────────────────────────────────────────────────
  n8n-postgres:
    image: postgres:16-alpine
    container_name: n8n-postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}
      TZ: ${TZ}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - n8n-net
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s

  # ──────────────────────────────────────────────────────────
  # Redis 8
  # ──────────────────────────────────────────────────────────
  n8n-redis:
    image: redis:8-alpine
    container_name: n8n-redis
    restart: unless-stopped
    command: >
      redis-server
      --appendonly yes
      --requirepass ${REDIS_PASSWORD}
    environment:
      TZ: ${TZ}
    volumes:
      - redis_data:/data
    networks:
      - n8n-net
    healthcheck:
      test: ["CMD", "redis-cli", "--no-auth-warning", "-a", "${REDIS_PASSWORD}", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 10s

  # ──────────────────────────────────────────────────────────
  # Traefik v3 — Reverse Proxy + SSL
  # ──────────────────────────────────────────────────────────
  n8n-traefik:
    image: traefik:v3
    container_name: n8n-traefik
    restart: unless-stopped
    command:
      - "--api.dashboard=false"
      - "--ping=true"
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--certificatesresolvers.letsencrypt.acme.httpchallenge=true"
      - "--certificatesresolvers.letsencrypt.acme.httpchallenge.entrypoint=web"
      - "--certificatesresolvers.letsencrypt.acme.email=${EMAIL}"
      - "--certificatesresolvers.letsencrypt.acme.storage=/letsencrypt/acme.json"
      - "--log.level=WARN"
    environment:
      TZ: ${TZ}
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - traefik_certs:/letsencrypt
    networks:
      - n8n-net
    healthcheck:
      test: ["CMD", "traefik", "healthcheck", "--ping"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s

  # ──────────────────────────────────────────────────────────
  # Telegram Bot
  # ──────────────────────────────────────────────────────────
  n8n-bot:
    build:
      context: ./bot
      dockerfile: Dockerfile
    container_name: n8n-bot
    restart: unless-stopped
    environment:
      TG_BOT_TOKEN: ${TG_BOT_TOKEN}
      TG_USER_ID: ${TG_USER_ID}
      N8N_DIR: /opt/automator/n8n
      DOMAIN: ${DOMAIN}
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}
      TZ: ${TZ}
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - /opt/automator/n8n:/opt/automator/n8n:ro
      - ./logs:/logs
    networks:
      - n8n-net
    depends_on:
      n8n:
        condition: service_started

networks:
  n8n-net:
    driver: bridge

volumes:
  n8n_data:
  postgres_data:
  redis_data:
  traefik_certs:
COMPOSEOF

# Append Docker GID
echo "DOCKER_GID=${DOCKER_GID}" >> "$INSTALL_DIR/.env"

log_ok "docker-compose.yml created"

# ============================================================
# 8. TELEGRAM BOT
# ============================================================
log_step "8/11 · Creating Telegram bot"

# bot/Dockerfile
cat > "$INSTALL_DIR/bot/Dockerfile" << 'BDEOF'
FROM node:20-alpine
# docker-compose needed to stop/build/start containers from inside the bot
RUN apk add --no-cache docker-cli docker-compose bash curl openssl
WORKDIR /app
COPY package.json ./
RUN npm install --production
COPY bot.js ./
CMD ["node", "bot.js"]
BDEOF

# bot/package.json
cat > "$INSTALL_DIR/bot/package.json" << 'BPEOF'
{
  "name": "n8n-telegram-bot",
  "version": "4.0.0",
  "main": "bot.js",
  "scripts": { "start": "node bot.js" },
  "dependencies": { "node-telegram-bot-api": "^0.66.0" }
}
BPEOF

# bot/bot.js
cat > "$INSTALL_DIR/bot/bot.js" << 'BJEOF'
const TelegramBot = require('node-telegram-bot-api');
const { exec } = require('child_process');
const fs = require('fs');

const BOT_TOKEN = process.env.TG_BOT_TOKEN;
const AUTH_USER = process.env.TG_USER_ID;
const N8N_DIR = process.env.N8N_DIR || '/opt/automator/n8n';

if (!BOT_TOKEN || !AUTH_USER) {
    console.log('TG_BOT_TOKEN or TG_USER_ID not set. Bot disabled.');
    process.exit(0);
}

const bot = new TelegramBot(BOT_TOKEN, { polling: true });
const auth = (msg) => String(msg.from.id) === String(AUTH_USER);

const run = (cmd, timeout = 60000) => new Promise((resolve, reject) => {
    exec(cmd, { timeout, maxBuffer: 10 * 1024 * 1024 }, (err, stdout, stderr) => {
        if (err) reject(err);
        else resolve(stdout || stderr || 'OK');
    });
});

// Auto-detect docker compose command (V2 plugin = 'docker compose', V1 standalone = 'docker-compose')
let COMPOSE_CMD = null;
const getComposeCmd = async () => {
    if (COMPOSE_CMD) return COMPOSE_CMD;
    try {
        // Test Docker Compose V2 (plugin): 'docker compose version'
        await run('docker compose version', 5000);
        COMPOSE_CMD = 'docker compose';
    } catch {
        try {
            // Fallback to Docker Compose V1 (standalone binary)
            await run('docker-compose version', 5000);
            COMPOSE_CMD = 'docker-compose';
        } catch {
            COMPOSE_CMD = 'docker compose'; // last resort fallback
        }
    }
    console.log(`[bot] Using compose command: ${COMPOSE_CMD}`);
    return COMPOSE_CMD;
};

// /start, /help
bot.onText(/\/(start|help)/, (msg) => {
    if (!auth(msg)) return;
    bot.sendMessage(msg.chat.id, `*n8n Bot v4.0*\n
/status — Server status
/logs [N] — n8n logs (default 50 lines)
/update — Update n8n
/backup — Create backup
/restart — Restart n8n
/disk — Disk space
/urls — Service URLs`, { parse_mode: 'Markdown' });
});

// /status
bot.onText(/\/status/, async (msg) => {
    if (!auth(msg)) return;
    const cid = msg.chat.id;
    try {
        const [uptime, containers, disk, mem, ver] = await Promise.all([
            run('uptime -p').catch(() => run('uptime')),
            run('docker ps --format "{{.Names}}: {{.Status}}"'),
            run("df -h / | tail -1 | awk '{print $5\" of \"$2}'"),
            run("free -h | grep Mem | awk '{print $3\"/\"$2}'"),
            run('docker exec n8n n8n --version 2>/dev/null').catch(() => 'N/A')
        ]);
        bot.sendMessage(cid, `📊 *Status*\n\n⏱ ${uptime.trim()}\n💾 Disk: ${disk.trim()}\n🧠 RAM: ${mem.trim()}\n📦 n8n: v${ver.trim()}\n\n*Containers:*\n\`\`\`\n${containers.trim()}\n\`\`\``, { parse_mode: 'Markdown' });
    } catch (e) { bot.sendMessage(cid, `❌ ${e.message}`); }
});

// /logs
bot.onText(/\/logs(?:\s+(\d+))?/, async (msg, match) => {
    if (!auth(msg)) return;
    const cid = msg.chat.id;
    const lines = Math.min(parseInt(match[1]) || 50, 5000);
    try {
        const logs = await run(`docker logs n8n --tail ${lines} 2>&1`, 30000);
        if (!logs.trim()) { bot.sendMessage(cid, '📋 Logs are empty'); return; }
        if (logs.length > 3900) {
            const p = `/tmp/n8n_logs_${Date.now()}.txt`;
            fs.writeFileSync(p, logs);
            await bot.sendDocument(cid, p, { caption: `📋 ${lines} log lines` });
            fs.unlinkSync(p);
        } else {
            bot.sendMessage(cid, `📋 *Logs:*\n\`\`\`\n${logs.substring(0, 3800)}\n\`\`\``, { parse_mode: 'Markdown' });
        }
    } catch (e) { bot.sendMessage(cid, `❌ ${e.message}`); }
});

// /restart
bot.onText(/\/restart/, async (msg) => {
    if (!auth(msg)) return;
    const cid = msg.chat.id;
    await bot.sendMessage(cid, '🔄 Restarting n8n...');
    try {
        await run('docker restart n8n', 120000);
        await new Promise(r => setTimeout(r, 15000));
        const s = await run('docker ps --filter name=^n8n$ --format "{{.Status}}"');
        bot.sendMessage(cid, `✅ Restarted\n${s.trim()}`);
    } catch (e) { bot.sendMessage(cid, `❌ ${e.message}`); }
});

// /update
let isUpdating = false;
bot.onText(/\/update/, async (msg) => {
    if (!auth(msg)) return;
    const cid = msg.chat.id;
    if (isUpdating) { bot.sendMessage(cid, '⏳ Update already in progress, please wait...'); return; }
    isUpdating = true;
    try {
        await bot.sendMessage(cid, '🔍 Checking versions...');
        let cur = 'unknown', lat = 'unknown';
        try { cur = (await run('docker exec n8n n8n --version')).trim(); } catch {}
        try {
            const r = JSON.parse(await run('curl -s https://api.github.com/repos/n8n-io/n8n/releases/latest'));
            lat = (r.tag_name || '').replace('n8n@', '').replace('v', '') || 'unknown';
        } catch {}
        await bot.sendMessage(cid, `📦 Current: *${cur}*\n🆕 Latest: *${lat}*`, { parse_mode: 'Markdown' });
        if (cur === lat && cur !== 'unknown') { bot.sendMessage(cid, '✅ Already on the latest version!'); return; }

        // Get the correct compose command for this server
        const DC = await getComposeCmd();

        await bot.sendMessage(cid, '💾 Backing up...');
        // Use 'bash' explicitly so script runs even if mount is read-only
        await run(`bash ${N8N_DIR}/backup_n8n.sh`, 300000).catch(() => {});

        await bot.sendMessage(cid, '⏹ Stopping...');
        // Use 'cd' into N8N_DIR instead of '-f' flag (avoids V1/V2 compat issue)
        await run(`cd ${N8N_DIR} && ${DC} stop n8n n8n-worker`, 60000);

        await bot.sendMessage(cid, '🔨 Rebuilding (5-10 min)...');
        await run(`cd ${N8N_DIR} && ${DC} build --pull n8n`, 900000);

        await bot.sendMessage(cid, '🚀 Starting...');
        await run(`cd ${N8N_DIR} && ${DC} up -d n8n n8n-worker`, 120000);
        await new Promise(r => setTimeout(r, 20000));

        let nv = 'unknown';
        try { nv = (await run('docker exec n8n n8n --version')).trim(); } catch {}
        await run('docker image prune -f', 60000).catch(() => {});
        const s = await run('docker ps --filter name=^n8n$ --format "{{.Status}}"').catch(() => '?');
        bot.sendMessage(cid, `✅ *Updated!*\n\n📦 Old: ${cur}\n🆕 New: ${nv}\n📊 ${s.trim()}`, { parse_mode: 'Markdown' });
    } catch (e) { bot.sendMessage(cid, `❌ ${e.message}\n\nManual: \`cd ${N8N_DIR} && ./update_n8n.sh\``, { parse_mode: 'Markdown' }); }
    finally { isUpdating = false; }
});

// /backup
bot.onText(/\/backup/, async (msg) => {
    if (!auth(msg)) return;
    const cid = msg.chat.id;
    await bot.sendMessage(cid, '💾 Creating backup...');
    try {
        await run(`bash ${N8N_DIR}/backup_n8n.sh`, 300000);
        const info = await run(`ls -lhrt ${N8N_DIR}/backups/n8n_backup_*.tar.gz* 2>/dev/null | tail -1`).catch(() => '');
        bot.sendMessage(cid, `✅ Backup created!\n${info.trim()}`);
    } catch (e) { bot.sendMessage(cid, `❌ ${e.message}`); }
});

// /disk
bot.onText(/\/disk/, async (msg) => {
    if (!auth(msg)) return;
    const cid = msg.chat.id;
    try {
        const [d, dd] = await Promise.all([run('df -h /'), run('docker system df').catch(() => 'N/A')]);
        bot.sendMessage(cid, `💾 *Disk*\n\`\`\`\n${d.trim()}\n\`\`\`\n*Docker:*\n\`\`\`\n${dd.trim()}\n\`\`\``, { parse_mode: 'Markdown' });
    } catch (e) { bot.sendMessage(cid, `❌ ${e.message}`); }
});

// /urls
bot.onText(/\/urls/, (msg) => {
    if (!auth(msg)) return;
    const D = process.env.DOMAIN || '?';
    bot.sendMessage(msg.chat.id, `🌐 *n8n:* https://${D}`, { parse_mode: 'Markdown' });
});

bot.on('polling_error', (e) => console.error('Poll:', e.code || e.message));
process.on('SIGINT', () => { bot.stopPolling(); process.exit(0); });
process.on('SIGTERM', () => { bot.stopPolling(); process.exit(0); });
console.log(`🤖 Bot started | Auth: ${AUTH_USER}`);
BJEOF

log_ok "Telegram bot created"

# ============================================================
# 9. UTILITIES (backup, update, restore)
# ============================================================
log_step "9/11 · Creating utilities"

# ─── backup_n8n.sh ──────────────────────────────────────────
cat > "$INSTALL_DIR/backup_n8n.sh" << 'BKEOF'
#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [ -f .env ]; then set -a; source .env; set +a; fi

BACKUP_DIR="$SCRIPT_DIR/backups"
BACKUP_NAME="n8n_backup_$(date +%Y%m%d_%H%M%S)"
BACKUP_PATH="$BACKUP_DIR/$BACKUP_NAME"
RETENTION=${BACKUP_RETENTION_DAYS:-7}

mkdir -p "$BACKUP_PATH"

notify() {
    [ -n "${TG_BOT_TOKEN:-}" ] && [ -n "${TG_USER_ID:-}" ] && \
    curl -sf -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TG_USER_ID}" -d "text=$1" -d "parse_mode=Markdown" >/dev/null 2>&1 || true
}

echo "[$(date)] Backing up PostgreSQL..."
docker exec n8n-postgres pg_dump -U "${POSTGRES_USER:-n8n}" "${POSTGRES_DB:-n8n}" > "$BACKUP_PATH/database.sql"
[ ! -s "$BACKUP_PATH/database.sql" ] && { echo "ERROR: empty dump"; rm -rf "$BACKUP_PATH"; exit 1; }

echo "[$(date)] Backing up configuration..."
docker cp n8n:/home/node/.n8n "$BACKUP_PATH/n8n_data" 2>/dev/null || true

echo "[$(date)] Copying .env and docker-compose.yml..."
cp -f .env "$BACKUP_PATH/.env" 2>/dev/null || true
cp -f docker-compose.yml "$BACKUP_PATH/docker-compose.yml" 2>/dev/null || true

# Versions
{ echo "Date: $(date)"; docker exec n8n n8n --version 2>/dev/null || echo "n8n: N/A"; docker --version; } > "$BACKUP_PATH/versions.txt"

echo "[$(date)] Archiving..."
cd "$BACKUP_DIR"
tar -czf "${BACKUP_NAME}.tar.gz" "$BACKUP_NAME"

if [ -n "${N8N_ENCRYPTION_KEY:-}" ] && command -v openssl &>/dev/null; then
    openssl enc -aes-256-cbc -salt -pbkdf2 -iter 100000 \
        -in "${BACKUP_NAME}.tar.gz" -out "${BACKUP_NAME}.tar.gz.enc" \
        -pass pass:"$N8N_ENCRYPTION_KEY"
    rm "${BACKUP_NAME}.tar.gz"
    FINAL="${BACKUP_NAME}.tar.gz.enc"
else
    FINAL="${BACKUP_NAME}.tar.gz"
fi

rm -rf "$BACKUP_NAME"
find "$BACKUP_DIR" -name "n8n_backup_*.tar.gz*" -mtime +$RETENTION -delete 2>/dev/null || true

SIZE=$(du -h "$FINAL" | cut -f1)
COUNT=$(find "$BACKUP_DIR" -name "n8n_backup_*.tar.gz*" 2>/dev/null | wc -l)
echo "[$(date)] ✅ Backup: $FINAL ($SIZE) | Total: $COUNT"
notify "✅ Backup: \`$FINAL\` ($SIZE)"
echo "$BACKUP_DIR/$FINAL"
BKEOF
chmod +x "$INSTALL_DIR/backup_n8n.sh"

# ─── update_n8n.sh ──────────────────────────────────────────
cat > "$INSTALL_DIR/update_n8n.sh" << 'UPEOF'
#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [ -f .env ]; then set -a; source .env; set +a; fi
LOG="$SCRIPT_DIR/logs/update_$(date +%Y%m%d_%H%M%S).log"
mkdir -p "$SCRIPT_DIR/logs"
exec > >(tee -a "$LOG") 2>&1

notify() {
    [ -n "${TG_BOT_TOKEN:-}" ] && [ -n "${TG_USER_ID:-}" ] && \
    curl -sf -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TG_USER_ID}" -d "text=$1" -d "parse_mode=Markdown" >/dev/null 2>&1 || true
}

CUR=$(docker exec n8n n8n --version 2>/dev/null || echo "unknown")
LAT=$(curl -sf https://api.github.com/repos/n8n-io/n8n/releases/latest | grep '"tag_name"' | sed -E 's/.*"n8n@([^"]+)".*/\1/' || echo "unknown")

echo "Current: $CUR | Latest: $LAT"

if [ "$CUR" = "$LAT" ] && [ "$CUR" != "unknown" ]; then
    echo "✅ Already on latest version"; notify "✅ n8n $CUR is current"; exit 0
fi

notify "🔄 Updating n8n: $CUR → $LAT"

echo "Backing up..."
[ -f ./backup_n8n.sh ] && ./backup_n8n.sh || echo "⚠️  Backup not created"

echo "Stopping..."
docker compose stop n8n n8n-worker

echo "Rebuilding..."
docker compose build --pull n8n

echo "Starting..."
docker compose up -d n8n n8n-worker

echo "Waiting for healthcheck (60s max)..."
for i in {1..30}; do
    sleep 2
    docker exec n8n wget --spider -q http://localhost:5678/healthz 2>/dev/null && break
done

NEW=$(docker exec n8n n8n --version 2>/dev/null || echo "unknown")
docker image prune -f >/dev/null 2>&1 || true
docker builder prune -f >/dev/null 2>&1 || true

STATUS=$(docker ps --filter name=^n8n$ --format "{{.Status}}" 2>/dev/null)

if echo "$STATUS" | grep -q "Up"; then
    echo "✅ Updated: $CUR → $NEW"
    notify "✅ n8n updated: $CUR → $NEW"
else
    echo "❌ Container failed to start"
    notify "❌ Update error. Check: docker logs n8n"
    exit 1
fi
UPEOF
chmod +x "$INSTALL_DIR/update_n8n.sh"

# ─── restore_n8n.sh ─────────────────────────────────────────
cat > "$INSTALL_DIR/restore_n8n.sh" << 'RSEOF'
#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [ -f .env ]; then set -a; source .env; set +a; fi

if [ -z "$1" ]; then
    echo "Usage: $0 <path_to_backup>"
    echo ""; echo "Available backups:"
    ls -lhrt "$SCRIPT_DIR/backups/n8n_backup_"* 2>/dev/null || echo "  No backups found"
    exit 1
fi

BACKUP_FILE="$1"
[ ! -f "$BACKUP_FILE" ] && { echo "❌ File not found: $BACKUP_FILE"; exit 1; }

echo "⚠️  ALL current data will be REPLACED!"
read -p "Continue? (yes/no): " CONFIRM
[ "$CONFIRM" != "yes" ] && { echo "Cancelled."; exit 0; }

# Backup current state
echo "💾 Backing up current state..."
./backup_n8n.sh 2>/dev/null || true

echo "⏹  Stopping containers..."
docker compose down

TMPDIR=$(mktemp -d)
cd "$TMPDIR"

# Decrypt
if [[ "$BACKUP_FILE" == *.enc ]]; then
    [ -z "${N8N_ENCRYPTION_KEY:-}" ] && { echo "❌ N8N_ENCRYPTION_KEY not set"; rm -rf "$TMPDIR"; exit 1; }
    openssl enc -aes-256-cbc -d -salt -pbkdf2 -iter 100000 \
        -in "$BACKUP_FILE" -out backup.tar.gz -pass pass:"$N8N_ENCRYPTION_KEY"
    tar -xzf backup.tar.gz
else
    tar -xzf "$BACKUP_FILE"
fi

DATA_DIR=$(find . -maxdepth 1 -type d -name "n8n_backup_*" | head -1)
[ -z "$DATA_DIR" ] && { echo "❌ No data found in archive"; rm -rf "$TMPDIR"; exit 1; }

# Restore PostgreSQL
echo "🗄  Restoring PostgreSQL..."
docker compose -f "$SCRIPT_DIR/docker-compose.yml" up -d n8n-postgres
sleep 10
if [ -f "$DATA_DIR/database.sql" ]; then
    docker exec n8n-postgres psql -U "${POSTGRES_USER:-n8n}" -d postgres \
        -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='${POSTGRES_DB:-n8n}' AND pid<>pg_backend_pid();" 2>/dev/null || true
    docker exec n8n-postgres dropdb -U "${POSTGRES_USER:-n8n}" "${POSTGRES_DB:-n8n}" 2>/dev/null || true
    docker exec n8n-postgres createdb -U "${POSTGRES_USER:-n8n}" "${POSTGRES_DB:-n8n}"
    docker exec -i n8n-postgres psql -U "${POSTGRES_USER:-n8n}" -d "${POSTGRES_DB:-n8n}" < "$DATA_DIR/database.sql"
    echo "✅ Database restored"
fi

# Restore n8n configuration
if [ -d "$DATA_DIR/n8n_data" ]; then
    echo "📁 Restoring n8n configuration..."
    docker volume rm -f "$(basename $SCRIPT_DIR)_n8n_data" 2>/dev/null || true
    docker volume create "$(basename $SCRIPT_DIR)_n8n_data" 2>/dev/null || true
    docker run --rm -v "$(basename $SCRIPT_DIR)_n8n_data":/restore -v "$PWD/$DATA_DIR/n8n_data":/backup alpine sh -c "cp -r /backup/. /restore/"
    echo "✅ Configuration restored"
fi

# Restore .env
if [ -f "$DATA_DIR/.env" ]; then
    read -p "Restore .env? (yes/no): " RE
    if [ "$RE" = "yes" ]; then
        cp "$SCRIPT_DIR/.env" "$SCRIPT_DIR/.env.before_restore"
        cp "$DATA_DIR/.env" "$SCRIPT_DIR/.env"
        echo "✅ .env restored (old saved as .env.before_restore)"
    fi
fi

rm -rf "$TMPDIR"

echo "🚀 Starting..."
docker compose -f "$SCRIPT_DIR/docker-compose.yml" up -d
sleep 15

for i in {1..30}; do
    docker exec n8n wget --spider -q http://localhost:5678/healthz 2>/dev/null && { echo "✅ n8n is running!"; break; }
    sleep 2
done

echo ""; echo "✅ Restore completed!"
echo "🔗 https://${DOMAIN:-n8n}"
RSEOF
chmod +x "$INSTALL_DIR/restore_n8n.sh"

log_ok "Utilities: backup_n8n.sh, update_n8n.sh, restore_n8n.sh"

# ============================================================
# 10. BUILD IMAGES
# ============================================================
log_step "10/11 · Building Docker images  ⏱ ~5-15 min"

cd "$INSTALL_DIR"

log_info "Cleaning Docker build cache..."
docker builder prune -af 2>/dev/null || true

log_info "Building n8n custom image (this may take 5-15 minutes)..."
docker compose build --no-cache 2>&1 &
SPINNER_PID=$!
spinner "Building Docker images — please wait..."
wait $SPINNER_PID
BUILD_EXIT=$?
if [ $BUILD_EXIT -ne 0 ]; then
    log_error "Docker build failed (exit code $BUILD_EXIT)"
    exit 1
fi

log_ok "All images built successfully"

# ============================================================
# 11. START
# ============================================================
log_step "11/11 · Starting containers"

docker compose up -d

# Wait for n8n healthcheck  
log_info "Waiting for n8n to become healthy (up to 120 seconds)..."
N8N_OK=false
HC_FRAMES=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
HC_IDX=0
for i in {1..60}; do
    sleep 2
    if docker exec n8n wget --spider -q http://localhost:5678/healthz 2>/dev/null; then
        echo -ne "\r$(printf ' %.0s' $(seq 1 60))\r"
        N8N_OK=true
        break
    fi
    echo -ne "\r  ${CYAN}${HC_FRAMES[$HC_IDX]}${NC}  Waiting for n8n... ${DIM}(${i}/60)${NC}"
    HC_IDX=$(( (HC_IDX + 1) % ${#HC_FRAMES[@]} ))
done
echo ""

if $N8N_OK; then
    log_ok "n8n is up and responding!"
else
    log_warn "n8n did not respond within 120 seconds. Check: docker compose logs n8n"
fi

# ============================================================
# 12. CRON + FINALIZATION
# ============================================================
log_step "Finalization"

# Cron for backups
(crontab -l 2>/dev/null | grep -v "backup_n8n.sh"; \
 echo "0 2 * * * cd $INSTALL_DIR && ./backup_n8n.sh >> ./logs/backup_cron.log 2>&1") | crontab - 2>/dev/null || true
log_ok "Cron: daily backup at 2:00"

# n8n Version
N8N_VER=$(docker exec n8n n8n --version 2>/dev/null || echo "N/A")

# Telegram Notification
if [ -n "$TG_BOT_TOKEN" ] && [ -n "$TG_USER_ID" ]; then
    curl -sf -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TG_USER_ID}" \
        -d "text=✅ *n8n installed!*

🌐 https://${DOMAIN}
📦 Version: ${N8N_VER}

Commands: /start" \
        -d "parse_mode=Markdown" >/dev/null 2>&1 || true
fi

# ============================================================
# FINAL SUMMARY
# ============================================================

# Calculate elapsed time
END_TIME=$(date +%s)
ELAPSED=$(( END_TIME - START_TIME ))
ELAPSED_FMT="$((ELAPSED/60))m $((ELAPSED%60))s"

echo ""
echo -e "${GREEN}${BOLD}┌──────────────────────────────────────────────────────┐${NC}"
echo -e "${GREEN}${BOLD}│${NC}         ${GREEN}${BOLD}✅  INSTALLATION COMPLETED!${NC}              ${GREEN}${BOLD}│${NC}"
echo -e "${GREEN}${BOLD}├──────────────────────────────────────────────────────┤${NC}"
printf  "${GREEN}${BOLD}│${NC}  %-20s ${CYAN}%-31s${NC} ${GREEN}${BOLD}│${NC}\n" "🌐 n8n URL" "https://${DOMAIN}"
printf  "${GREEN}${BOLD}│${NC}  %-20s %-31s ${GREEN}${BOLD}│${NC}\n" "📦 n8n version" "v${N8N_VER}"
printf  "${GREEN}${BOLD}│${NC}  %-20s %-31s ${GREEN}${BOLD}│${NC}\n" "🗄  PostgreSQL" "16"
printf  "${GREEN}${BOLD}│${NC}  %-20s %-31s ${GREEN}${BOLD}│${NC}\n" "⚡ Redis" "7"
printf  "${GREEN}${BOLD}│${NC}  %-20s %-31s ${GREEN}${BOLD}│${NC}\n" "🔒 Traefik" "latest"
printf  "${GREEN}${BOLD}│${NC}  %-20s %-31s ${GREEN}${BOLD}│${NC}\n" "🖥  Server IP" "${PUBLIC_IP}"
printf  "${GREEN}${BOLD}│${NC}  %-20s %-31s ${GREEN}${BOLD}│${NC}\n" "⏱  Total time" "${ELAPSED_FMT}"
echo -e "${GREEN}${BOLD}├──────────────────────────────────────────────────────┤${NC}"
echo -e "${GREEN}${BOLD}│${NC}  ${BOLD}Useful commands:${NC}                                   ${GREEN}${BOLD}│${NC}"
printf  "${GREEN}${BOLD}│${NC}    %-50s ${GREEN}${BOLD}│${NC}\n" "cd ${INSTALL_DIR}"
printf  "${GREEN}${BOLD}│${NC}    ${DIM}%-50s${NC} ${GREEN}${BOLD}│${NC}\n" "docker compose ps"
printf  "${GREEN}${BOLD}│${NC}    ${DIM}%-50s${NC} ${GREEN}${BOLD}│${NC}\n" "docker compose logs -f n8n"
printf  "${GREEN}${BOLD}│${NC}    ${DIM}%-50s${NC} ${GREEN}${BOLD}│${NC}\n" "./update_n8n.sh"
printf  "${GREEN}${BOLD}│${NC}    ${DIM}%-50s${NC} ${GREEN}${BOLD}│${NC}\n" "./backup_n8n.sh"
printf  "${GREEN}${BOLD}│${NC}    ${DIM}%-50s${NC} ${GREEN}${BOLD}│${NC}\n" "./restore_n8n.sh <backup_file>"
echo -e "${GREEN}${BOLD}├──────────────────────────────────────────────────────┤${NC}"
printf  "${GREEN}${BOLD}│${NC}  📁 Passwords: %-37s ${GREEN}${BOLD}│${NC}\n" "${INSTALL_DIR}/.env"
printf  "${GREEN}${BOLD}│${NC}  📋 Install log: %-35s ${GREEN}${BOLD}│${NC}\n" "${LOG_FILE}"
echo -e "${GREEN}${BOLD}└──────────────────────────────────────────────────────┘${NC}"
echo ""

# Container Status
docker compose ps
