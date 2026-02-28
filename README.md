# n8n Universal Auto-Install v4.0

Complete one-click automatic installation of n8n 2.x on clean Ubuntu 22.04 / 24.04.

## 🚀 What's Installed

| Component | Version | Description |
|-----------|--------|----------|
| **n8n** | latest (2.x) | Automation platform |
| **n8n-worker** | latest | Worker for queue mode |
| **PostgreSQL** | 16-alpine | Database |
| **Redis** | 7-alpine | Cache and task queue |
| **Traefik** | v3.3 | Reverse proxy + SSL |
| **Telegram Bot** | Node 20 | Server management |

### Tools built into the n8n image

- **AI/ML:** OpenAI, LangChain
- **Media:** FFmpeg, ImageMagick, Ghostscript, GraphicsMagick
- **OCR:** Tesseract (Russian + English)
- **Browser:** Chromium + Puppeteer
- **Bots:** Telegram, Discord, VK
- **Data:** CSV, XLSX, XML, YAML parsers
- **30+ npm libraries** globally for Code-nodes

## 📋 Requirements

- **OS:** Ubuntu 22.04 or 24.04 (clean server)
- **RAM:** minimum 2GB (4GB recommended)
- **Disk:** minimum 10GB free
- **Domain** with a DNS A-record pointing to the server's IP
- **Ports 80 and 443** open
- **Root access**

## 🎯 Installation

### One-click

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/satriyabajuhitam/n8n-oto-install/main/install.sh)
```

### Or download and run

```bash
curl -fsSL https://raw.githubusercontent.com/satriyabajuhitam/n8n-oto-install/main/install.sh -o install.sh
chmod +x install.sh
sudo bash install.sh
```

### What the script will ask (4 questions total)

| Parameter | Example | Mandatory |
|----------|--------|:---:|
| n8n Domain | `n8n.example.com` | ✅ |
| Email for SSL | `admin@example.com` | ✅ |
| Telegram Bot Token | from @BotFather | ❌ |
| Telegram User ID | from @userinfobot | ❌ |

**Everything else is generated automatically:**
- PostgreSQL Password
- n8n Encryption Key (64 hex characters)
- Redis Password
- Timezone: Asia/Jakarta (can be changed in `.env` after installation)

## 📁 Project Structure

```
/opt/automator/n8n/
├── install.sh              # Installation script
├── docker-compose.yml      # Container configuration
├── Dockerfile.n8n          # Custom n8n image
├── .env                    # All passwords and settings
├── update_n8n.sh           # Update n8n
├── backup_n8n.sh           # Create backup
├── restore_n8n.sh          # Restore from backup
├── bot/
│   ├── bot.js              # Telegram bot
│   ├── Dockerfile          # Bot image
│   └── package.json        # Dependencies
├── n8n-files/              # n8n v2 Sandbox zone (Read/Write Binary Files)
├── data/                   # Custom working folder
├── logs/                   # Operation logs
└── backups/                # Backups
```

## 🔐 Access

After installation, all passwords are printed to the console and saved in `/opt/automator/n8n/.env`.

```
URL: https://n8n.example.com
The first user is created upon the first login.
```

Quick password view:

```bash
cd /opt/automator/n8n
grep PASSWORD .env
```

## 🤖 Telegram Bot

### Configuration

1. Create a bot: write to [@BotFather](https://t.me/BotFather) → `/newbot`
2. Get User ID: write to [@userinfobot](https://t.me/userinfobot)
3. Specify during installation or add later to `.env`:

```bash
nano /opt/automator/n8n/.env
# TG_BOT_TOKEN=123456:ABC-DEF...
# TG_USER_ID=987654321

docker compose -f /opt/automator/n8n/docker-compose.yml restart n8n-bot
```

### Commands

| Command | Description |
|---------|----------|
| `/start` `/help` | Help |
| `/status` | Uptime, RAM, disk, n8n version, container status |
| `/logs [N]` | Last N log lines (default 50) |
| `/update` | Update n8n (backup → rebuild → restart) |
| `/backup` | Create backup |
| `/restart` | Restart n8n |
| `/disk` | Disk space (system + Docker) |
| `/urls` | n8n URL |

### Bot Security

- Authorization by `TG_USER_ID` — only one user
- If token is not set — bot exits quietly (doesn't enter restart loop)

## 🛠️ Management

### Status

```bash
cd /opt/automator/n8n
docker compose ps
```

### Logs

```bash
# All services
docker compose logs -f

# n8n only
docker compose logs -f n8n

# Last 50 lines
docker logs n8n --tail 50
```

### Restart

```bash
cd /opt/automator/n8n

# Single service
docker compose restart n8n

# All
docker compose restart

# Full restart
docker compose down && docker compose up -d
```

### Updating n8n

```bash
cd /opt/automator/n8n
./update_n8n.sh
```

Or via Telegram: `/update`

The script automatically:
1. Checks versions (current vs latest)
2. Creates backup
3. Stops n8n + worker
4. Rebuilds image with `--pull` (new base n8n)
5. Starts containers
6. Checks healthcheck
7. Cleans up old images

## 💾 Backup

### Creating Backup

```bash
cd /opt/automator/n8n
./backup_n8n.sh
```

Or via Telegram: `/backup`

**What's included in the backup:**
- PostgreSQL dump (all workflows, credentials, settings)
- n8n configuration (`/home/node/.n8n`)
- `.env` and `docker-compose.yml` files
- Version information

**Encryption:** if `N8N_ENCRYPTION_KEY` is set in `.env`, the backup is encrypted using AES-256-CBC.

> ⚠️ **Important:** The `N8N_ENCRYPTION_KEY` is required to decrypt backups. If you lose this key, encrypted backups cannot be recovered. Always keep a copy of your `.env` file in a safe place.

### Automatic Backups

Configured during installation via cron — daily at 2:00.

```bash
# Check schedule
crontab -l

# Edit
crontab -e
```

### Restore

```bash
cd /opt/automator/n8n

# List backups
ls -lhrt backups/

# Restore
./restore_n8n.sh backups/n8n_backup_20250101_020000.tar.gz.enc
```

The script:
1. Creates a backup of the current state (just in case)
2. Stops all containers
3. Decrypts and extracts
4. Restores PostgreSQL
5. Restores n8n configuration
6. Prompts to restore `.env` (optional)
7. Starts everything

### Storage

- Backups are stored in `/opt/automator/n8n/backups/`
- Auto-deletion older than 7 days (configured by: `BACKUP_RETENTION_DAYS` in `.env`)

## ⚙️ n8n 2.x — File System Security

### File Zones

| Path | Purpose |
|------|------------|
| `/home/node/.n8n-files` | Standard n8n v2 sandbox zone |
| `/data` | Custom project working folder |

Both zones are added to the `N8N_RESTRICT_FILE_ACCESS_TO` whitelist.

### Usage in Nodes

**Read/Write Binary Files:**

```
/home/node/.n8n-files/report.pdf    ✅ Works
/data/project/document.xlsx          ✅ Works
/tmp/file.txt                        ❌ Forbidden
```

**Execute Command:**

```bash
echo "data" > /home/node/.n8n-files/output.txt   # ✅
cp file.csv /data/reports/                         # ✅
```

### Key Settings

```env
NODES_EXCLUDE=[]                                          # Execute Command allowed
N8N_RESTRICT_FILE_ACCESS_TO=/home/node/.n8n-files;/data   # Whitelist
N8N_RUNNERS_ENABLED=false                                 # false = faster
N8N_COMMUNITY_PACKAGES_ENABLED=true                       # Community packages
```

## 🌐 Architecture

```
Internet
    │
    ▼
┌─────────┐
│ Traefik │ :80 / :443 (SSL Let's Encrypt)
│   v3.3  │
└────┬────┘
     │
     └── n8n.example.com → n8n :5678
                             │
              ┌──────────────┤
              │              │
         ┌────┴────┐  ┌─────┴─────┐
         │ n8n-app │◄►│ n8n-worker│
         └────┬────┘  └─────┬─────┘
              │              │
         ┌────┴────┐  ┌─────┴─────┐
         │Postgres │  │   Redis   │
         │   16    │  │     7     │
         └─────────┘  └───────────┘
```

**Queue mode:** n8n-app handles webhooks and UI, n8n-worker executes workflows. Both read tasks from Redis.

## 🔧 Configuration

All settings in `/opt/automator/n8n/.env`. After modifications:

```bash
cd /opt/automator/n8n
docker compose down && docker compose up -d
```

### Key Variables

| Variable | Description | Default |
|------------|----------|:---:|
| `DOMAIN` | n8n Domain | — |
| `N8N_BINARY_DATA_MODE` | File storage | `filesystem` |
| `N8N_LOG_LEVEL` | Log level | `info` |
| `N8N_RUNNERS_ENABLED` | Task runners | `false` |
| `EXECUTIONS_MODE` | Execution mode | `queue` |
| `BACKUP_RETENTION_DAYS` | Backup retention (days) | `7` |
| `PROXY_URL` | External proxy | empty |

### Proxy

If n8n needs to access the internet via a proxy:

```env
PROXY_URL=http://user:pass@proxy-server:port
NO_PROXY=localhost,127.0.0.1,::1,.local,postgres,redis,traefik,n8n,n8n-postgres,n8n-redis,n8n-traefik
```

## 🔒 Security

### Recommendations

1. **SSH:** key-only, disable root password
2. **Firewall:** only ports 80, 443 (and 22 for SSH) open
3. **Updates:** regular updates via `/update` in the bot
4. **Backups:** enabled by default (daily at 2:00)
5. **Monitoring:** `/status` in the bot

### Isolation

- PostgreSQL and Redis are **NOT accessible** from the internet — Docker internal network only
- For direct connection, use an SSH tunnel:

```bash
# PostgreSQL
ssh -L 5432:localhost:5432 user@server

# Redis
ssh -L 6379:localhost:6379 user@server
```

## 🐛 Troubleshooting

### n8n Not Starting

```bash
cd /opt/automator/n8n
docker compose logs n8n --tail 50
docker compose ps
```

### Traefik Unhealthy

```bash
# Check Traefik health status
docker inspect n8n-traefik --format='{{json .State.Health.Status}}'

# Check Traefik ping endpoint (should return 200)
docker exec n8n-traefik wget -qO- http://localhost:8080/ping

# Traefik logs
docker compose logs n8n-traefik --tail 30
```

### SSL Certificates Not Issued

1. Check DNS: `dig n8n.example.com` → your IP
2. Ports 80/443 open: `ss -tlnp | grep -E ':(80|443)'`
3. Traefik logs: `docker compose logs n8n-traefik`

### Bot Not Responding

```bash
docker compose logs n8n-bot --tail 20
grep TG_ /opt/automator/n8n/.env
docker compose restart n8n-bot
```

### Insufficient Memory (OOM)

```bash
# Check SWAP
free -h
swapon --show

# Add if missing
fallocate -l 4G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab
```

### Disk Cleanup

```bash
# Old images
docker image prune -a

# Build cache
docker builder prune -af

# All unused
docker system prune -a --volumes
```

## 📊 Monitoring

### Telegram Bot

`/status` shows: uptime, RAM, disk, n8n version, all containers.

### Useful Commands

```bash
# Real-time container resources
docker stats

# n8n version
docker exec n8n n8n --version

# Database size
docker exec n8n-postgres psql -U n8n -c "SELECT pg_size_pretty(pg_database_size('n8n'));"

# Testing tools inside the container
docker exec n8n sh -c "ffmpeg -version 2>&1 | head -1"
docker exec n8n sh -c "python3 --version"
docker exec n8n sh -c "chromium-browser --version"
docker exec n8n sh -c "tesseract --version 2>&1 | head -1"
```

## 📝 Command Cheat Sheet

```bash
cd /opt/automator/n8n

# ─── Status ──────────────────────────────
docker compose ps                    # All containers

# ─── Logs ────────────────────────────────
docker compose logs -f n8n           # Follow logs
docker logs n8n --tail 100           # Last 100 lines

# ─── Management ─────────────────────────
docker compose restart n8n           # Restart n8n
docker compose down && docker compose up -d  # Full restart

# ─── Update ─────────────────────────
./update_n8n.sh                      # Update n8n

# ─── Backups ─────────────────────────────
./backup_n8n.sh                      # Create backup
./restore_n8n.sh backups/FILE        # Restore
ls -lhrt backups/                    # List backups

# ─── Passwords / Secrets ─────────────────────────────
grep -E 'PASSWORD|KEY|TOKEN' .env      # All secrets

# ─── Diagnostics ────────────────────────
docker stats                         # Resources
df -h                                # Disk
free -h                              # RAM + SWAP
docker system df                     # Docker storage
```

## 📜 License

MIT License — feel free to use for personal and commercial projects.

---
