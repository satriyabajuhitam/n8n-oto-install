# n8n Universal Auto-Install v4.0

Instalasi otomatis n8n 2.x di Ubuntu 22.04 / 24.04 dengan satu perintah. Termasuk PostgreSQL, Redis, Traefik SSL, Queue Mode, FFmpeg, dan Telegram Bot untuk manajemen server.

## 🚀 Stack yang Diinstal

| Komponen | Versi | Keterangan |
|----------|-------|------------|
| **n8n** | latest (2.x) | Platform otomasi workflow |
| **n8n-worker** | latest (2.x) | Worker untuk Queue Mode |
| **PostgreSQL** | 16-alpine | Database utama |
| **Redis** | 8-alpine | Message broker & task queue |
| **Traefik** | v3 | Reverse proxy + SSL otomatis |
| **FFmpeg** | Alpine (latest) | Pemrosesan audio/video via Exec Node |
| **Telegram Bot** | Node 20 | Manajemen server via Telegram |

### npm Modules Tersedia di Code Node

Module-module berikut sudah tersedia untuk digunakan dengan `require()` di Code node:

**Built-in Node.js:** `crypto`, `fs`, `path`, `url`, `util`, `stream`, `buffer`, `os`, `querystring`, `zlib`

**External npm:** `axios`, `node-fetch`, `form-data`, `date-fns`, `lodash`, `fs-extra`, `csv-parser`, `xml2js`, `js-yaml`, `xlsx`, `jsonwebtoken`, `uuid`, `openai`, `ioredis`, `validator`, `winston`, `dotenv`

## 📋 Persyaratan

- **OS:** Ubuntu 22.04 atau 24.04 (server bersih)
- **RAM:** minimal 2 GB (4 GB direkomendasikan)
- **Disk:** minimal 10 GB free
- **Domain** dengan DNS A-record yang mengarah ke IP server
- **Port 80 dan 443** terbuka ke internet
- **Akses root**

## 🎯 Instalasi

### One-liner

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/satriyabajuhitam/n8n-oto-install/main/install.sh)
```

### Download dan jalankan

```bash
curl -fsSL https://raw.githubusercontent.com/satriyabajuhitam/n8n-oto-install/main/install.sh -o install.sh
chmod +x install.sh
sudo bash install.sh
```

### Input yang diperlukan (4 pertanyaan)

| Parameter | Contoh | Wajib |
|-----------|--------|:-----:|
| Domain n8n | `n8n.example.com` | ✅ |
| Email untuk SSL | `admin@example.com` | ✅ |
| Telegram Bot Token | dari @BotFather | ❌ |
| Telegram User ID | dari @userinfobot | ❌ |

**Dibuat otomatis oleh script:**
- Password PostgreSQL
- n8n Encryption Key (64 hex karakter)
- Password Redis
- Timezone: Asia/Jakarta (bisa diubah di `.env` setelah instalasi)

## 📁 Struktur Direktori

```
/opt/automator/n8n/
├── install.sh              # Script instalasi
├── docker-compose.yml      # Konfigurasi container
├── Dockerfile.n8n          # Custom n8n image (termasuk FFmpeg)
├── .env                    # Semua password dan konfigurasi
├── update_n8n.sh           # Script update n8n
├── backup_n8n.sh           # Script backup
├── restore_n8n.sh          # Script restore
├── bot/
│   ├── bot.js              # Telegram bot
│   ├── Dockerfile          # Bot image
│   └── package.json        # Dependencies bot
├── n8n-files/              # Sandbox zone n8n (Read/Write Binary Files)
├── data/                   # Folder kerja kustom n8n
├── media/                  # ← FFmpeg: file input/output (di-mount sebagai /files)
├── logs/                   # Log operasional
└── backups/                # Hasil backup
```

## 🌐 Arsitektur

```
Internet
    │
    ▼
┌─────────┐
│ Traefik │  :80 / :443 (SSL Let's Encrypt otomatis)
│   v3    │
└────┬────┘
     │
     └── n8n.example.com ──► n8n :5678
                               │
              ┌────────────────┤
              │                │
         ┌────┴────┐    ┌──────┴─────┐
         │  n8n    │◄──►│ n8n-worker │
         │  (UI +  │    │  (eksekusi │
         │ webhook)│    │  workflow) │
         └────┬────┘    └──────┬─────┘
              │                │
         ┌────┴────┐    ┌──────┴─────┐
         │Postgres │    │   Redis    │
         │   16    │    │     8      │
         └─────────┘    └────────────┘
```

**Queue Mode:** n8n (main) menangani webhook dan UI. n8n-worker mengeksekusi workflow. Keduanya membaca task dari Redis.

## 🔐 Akses

Setelah instalasi, semua password ditampilkan di konsol dan tersimpan di `/opt/automator/n8n/.env`.

```
URL: https://n8n.example.com
User pertama dibuat saat login pertama kali.
```

Lihat password dengan cepat:

```bash
cd /opt/automator/n8n
grep -E 'PASSWORD|KEY|TOKEN' .env
```

## 🤖 Telegram Bot

### Setup

1. Buat bot: kirim pesan ke [@BotFather](https://t.me/BotFather) → `/newbot`
2. Dapatkan User ID: kirim pesan ke [@userinfobot](https://t.me/userinfobot)
3. Masukkan saat instalasi **atau** tambahkan ke `.env` setelah instalasi:

```bash
nano /opt/automator/n8n/.env
# TG_BOT_TOKEN=123456:ABC-DEF...
# TG_USER_ID=987654321

cd /opt/automator/n8n && docker compose restart n8n-bot
```

### Perintah Bot

| Perintah | Fungsi |
|----------|--------|
| `/start` `/help` | Tampilkan bantuan |
| `/status` | Uptime, RAM, disk, versi n8n, status container |
| `/logs [N]` | N baris log terakhir (default 50) |
| `/update` | Update n8n (backup → rebuild → restart) |
| `/backup` | Buat backup |
| `/restart` | Restart n8n |
| `/disk` | Informasi disk (sistem + Docker) |
| `/urls` | Tampilkan URL n8n |

### Keamanan Bot

- Akses hanya untuk `TG_USER_ID` yang terdaftar
- Jika token tidak di-set, bot berhenti diam-diam (tidak masuk restart loop)

## ⚙️ Konfigurasi

Semua pengaturan ada di `/opt/automator/n8n/.env`. Setelah diubah, jalankan:

```bash
cd /opt/automator/n8n
docker compose down && docker compose up -d
```

### Variabel Penting

| Variabel | Deskripsi | Default |
|----------|-----------|:-------:|
| `DOMAIN` | Domain n8n | — |
| `N8N_BINARY_DATA_MODE` | Mode penyimpanan binary | `default` |
| `EXECUTIONS_MODE` | Mode eksekusi | `queue` |
| `OFFLOAD_MANUAL_EXECUTIONS_TO_WORKERS` | Delegasi ke worker | `true` |
| `N8N_LOG_LEVEL` | Level log | `info` |
| `BACKUP_RETENTION_DAYS` | Retensi backup (hari) | `7` |
| `PROXY_URL` | Proxy eksternal | kosong |
| `NODE_FUNCTION_ALLOW_EXTERNAL` | npm modules untuk Code node | *(lihat .env)* |
| `NODE_FUNCTION_ALLOW_BUILTIN` | Built-in modules untuk Code node | *(lihat .env)* |

### Code Node — Menggunakan `require()`

Module yang diizinkan dikonfigurasi via `.env`:

```env
NODE_FUNCTION_ALLOW_BUILTIN=crypto,fs,path,url,util,stream,buffer,os,querystring,zlib
NODE_FUNCTION_ALLOW_EXTERNAL=axios,node-fetch,openai,lodash,date-fns,...
```

Contoh penggunaan di Code node:

```javascript
// Gunakan OpenAI
const { OpenAI } = require('openai');

// Gunakan axios
const axios = require('axios');

// Gunakan crypto
const crypto = require('crypto');
```

### Proxy Eksternal

Jika n8n perlu akses internet melalui proxy:

```env
PROXY_URL=http://user:pass@proxy-server:port
NO_PROXY=localhost,127.0.0.1,::1,.local,postgres,redis,traefik,n8n,n8n-postgres,n8n-redis,n8n-traefik
```

## 📂 Keamanan File System

### Zona yang Diizinkan

| Path container | Path host | Fungsi |
|----------------|-----------|--------|
| `/home/node/.n8n-files` | `./n8n-files/` | Sandbox standar n8n (Read/Write Binary Files) |
| `/data` | `./data/` | Folder kerja kustom n8n |
| `/files` | `./media/` | **Staging area FFmpeg** (input/output media) |

Ketiga path ini terdaftar di `N8N_RESTRICT_FILE_ACCESS_TO`.

### Contoh Penggunaan

```
/home/node/.n8n-files/laporan.pdf    ✅ Diizinkan
/data/project/dokumen.xlsx           ✅ Diizinkan
/files/input.mp4                     ✅ Diizinkan (FFmpeg)
/files/output.mp3                    ✅ Diizinkan (FFmpeg)
/tmp/file.txt                        ❌ Diblokir
```

## 🎬 FFmpeg — Pemrosesan Audio & Video

FFmpeg sudah terpasang di dalam container n8n dan n8n-worker. Bisa langsung dipakai dari **Execute Command Node** tanpa konfigurasi tambahan.

### Direktori Media

File input/output FFmpeg disimpan **terpisah** dari data n8n:

| Lokasi | Path |
|--------|------|
| **Di host** | `/opt/automator/n8n/media/` |
| **Di container** | `/files/` |

Upload file ke host via SCP/SFTP, lalu akses dari n8n via `/files/`.

### Alur Workflow yang Direkomendasikan

```
[Webhook / HTTP Trigger]
        ↓
[Write Binary File → /files/input.xxx]   ← simpan file ke disk
        ↓
[Execute Command: ffmpeg -i /files/input.xxx ... /files/output.xxx]
        ↓
[Read Binary File ← /files/output.xxx]   ← ambil hasil
        ↓
[Upload / kirim / proses selanjutnya]
```

### Contoh Command di Execute Command Node

```bash
# Konversi audio OGA/OGG → WAV
ffmpeg -y -i /files/input.oga -acodec pcm_s16le -ar 44100 /files/output.wav

# Extract audio dari video
ffmpeg -i /files/input.mp4 -q:a 0 -map a /files/output.mp3

# Kompres video
ffmpeg -i /files/input.mp4 -vcodec libx264 -crf 28 /files/output_compressed.mp4

# Potong video (detik 10 sampai 40)
ffmpeg -i /files/input.mp4 -ss 10 -to 40 -c copy /files/clip.mp4

# Cek versi FFmpeg (untuk verifikasi)
ffmpeg -version
```

> **Tips:** Selalu gunakan path absolut (`/files/...`) di Execute Command Node. Gunakan flag `-y` agar FFmpeg otomatis overwrite output tanpa konfirmasi.

### Manajemen File dari Host

```bash
# Upload file ke server
scp video.mp4 user@server:/opt/automator/n8n/media/

# Lihat file di direktori media
ls -lh /opt/automator/n8n/media/

# Bersihkan file lama
find /opt/automator/n8n/media/ -mtime +7 -delete
```

### Verifikasi Instalasi

```bash
# Cek FFmpeg tersedia di container
docker exec n8n ffmpeg -version
docker exec n8n which ffmpeg    # → /usr/bin/ffmpeg

# Cek worker juga punya akses
docker exec n8n-worker ffmpeg -version
```

## 🛠️ Manajemen Server

### Status Container

```bash
cd /opt/automator/n8n
docker compose ps
```

### Logs

```bash
# Semua service
docker compose logs -f

# n8n saja
docker compose logs -f n8n

# 50 baris terakhir
docker logs n8n --tail 50
```

### Restart

```bash
cd /opt/automator/n8n

# Service tertentu
docker compose restart n8n

# Semua service
docker compose restart

# Full restart (down + up)
docker compose down && docker compose up -d
```

## 🔄 Update n8n

```bash
cd /opt/automator/n8n
./update_n8n.sh
```

Atau via Telegram: `/update`

Script otomatis:
1. Cek versi saat ini vs latest
2. Buat backup
3. Stop n8n + worker
4. Rebuild image dengan `--pull` (base image n8n terbaru)
5. Jalankan kembali
6. Verifikasi healthcheck
7. Bersihkan image lama

## 💾 Backup & Restore

### Buat Backup

```bash
cd /opt/automator/n8n
./backup_n8n.sh
```

Atau via Telegram: `/backup`

**Isi backup:**
- Dump PostgreSQL (semua workflow, credentials, settings)
- Konfigurasi n8n (`/home/node/.n8n`)
- File `.env` dan `docker-compose.yml`
- Informasi versi

**Enkripsi:** Backup dienkripsi AES-256-CBC menggunakan `N8N_ENCRYPTION_KEY`.

> ⚠️ **Penting:** Simpan file `.env` di tempat yang aman. Tanpa `N8N_ENCRYPTION_KEY`, backup terenkripsi tidak bisa dipulihkan.

### Backup Otomatis

Dikonfigurasi via cron — setiap hari pukul 02:00.

```bash
# Lihat jadwal
crontab -l

# Edit jadwal
crontab -e
```

### Restore

```bash
cd /opt/automator/n8n

# Lihat daftar backup
ls -lhrt backups/

# Restore dari backup
./restore_n8n.sh backups/n8n_backup_20260101_020000.tar.gz.enc
```

Script restore akan:
1. Buat backup kondisi saat ini (jaga-jaga)
2. Stop semua container
3. Dekripsi dan ekstrak
4. Restore PostgreSQL
5. Restore konfigurasi n8n
6. Tanya apakah `.env` ikut di-restore (opsional)
7. Jalankan kembali semua service

### Penyimpanan

- Lokasi: `/opt/automator/n8n/backups/`
- Auto-hapus setelah `BACKUP_RETENTION_DAYS` hari (default: 7)

## 🔒 Keamanan

### Rekomendasi

1. **SSH:** Gunakan key-based auth, nonaktifkan login password root
2. **Firewall:** Buka hanya port 80, 443, dan 22
3. **Update rutin:** gunakan `/update` via bot
4. **Backup harian:** aktif secara default (02:00)
5. **Monitoring:** gunakan `/status` di bot

### Isolasi Jaringan

PostgreSQL dan Redis **tidak dapat diakses dari internet** — hanya dari internal Docker network `n8n-net`.

Untuk koneksi langsung dari lokal, gunakan SSH tunnel:

```bash
# PostgreSQL
ssh -L 5432:localhost:5432 user@server

# Redis
ssh -L 6379:localhost:6379 user@server
```

## 🐛 Troubleshooting

### n8n tidak mau start

```bash
cd /opt/automator/n8n
docker compose logs n8n --tail 50
docker compose ps
```

### Traefik unhealthy

```bash
# Cek status health
docker inspect n8n-traefik --format='{{json .State.Health.Status}}'

# Cek ping endpoint (harus 200)
docker exec n8n-traefik wget -qO- http://localhost:8080/ping

# Lihat log Traefik
docker compose logs n8n-traefik --tail 30
```

### SSL tidak terbit

1. Cek DNS: `dig n8n.example.com` → harus ke IP server
2. Cek port terbuka: `ss -tlnp | grep -E ':(80|443)'`
3. Lihat log Traefik: `docker compose logs n8n-traefik`

### Bot tidak merespons

```bash
docker compose logs n8n-bot --tail 20
grep TG_ /opt/automator/n8n/.env
docker compose restart n8n-bot
```

### Kehabisan memori (OOM)

```bash
# Cek SWAP
free -h
swapon --show

# Tambah SWAP jika belum ada
fallocate -l 4G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab
```

### Bersihkan disk

```bash
# Image lama
docker image prune -a

# Build cache
docker builder prune -af

# Semua yang tidak terpakai
docker system prune -a --volumes
```

## 📊 Monitoring

### Via Telegram Bot

`/status` menampilkan: uptime, RAM, disk, versi n8n, status semua container.

### Perintah Berguna

```bash
# Resource container real-time
docker stats

# Versi n8n
docker exec n8n n8n --version

# Ukuran database
docker exec n8n-postgres psql -U n8n -c "SELECT pg_size_pretty(pg_database_size('n8n'));"

# Status Redis
docker exec n8n-redis redis-cli --no-auth-warning -a "$REDIS_PASSWORD" info server | grep redis_version
```

## 📝 Cheat Sheet

```bash
cd /opt/automator/n8n

# ─── Status ───────────────────────────────────
docker compose ps                          # Semua container
docker stats                               # Resource real-time

# ─── Logs ─────────────────────────────────────
docker compose logs -f n8n                 # Follow log n8n
docker logs n8n --tail 100                 # 100 baris terakhir

# ─── Restart ──────────────────────────────────
docker compose restart n8n                 # Restart n8n saja
docker compose down && docker compose up -d  # Full restart

# ─── Update ───────────────────────────────────
./update_n8n.sh                            # Update n8n

# ─── Backup ───────────────────────────────────
./backup_n8n.sh                            # Buat backup
./restore_n8n.sh backups/FILE              # Restore backup
ls -lhrt backups/                          # Daftar backup

# ─── Secrets ──────────────────────────────────
grep -E 'PASSWORD|KEY|TOKEN' .env          # Lihat semua secret

# ─── Diagnostik ───────────────────────────────
df -h                                      # Disk
free -h                                    # RAM + SWAP
docker system df                           # Storage Docker

# ─── FFmpeg ───────────────────────────────────
docker exec n8n ffmpeg -version            # Cek versi FFmpeg
ls -lh media/                              # Daftar file media
find media/ -mtime +7 -delete             # Hapus file >7 hari
```

## 📜 Lisensi

MIT License — bebas digunakan untuk proyek personal maupun komersial.

---

*n8n Universal Auto-Install v4.0 — dioptimasi untuk n8n 2.20.x, Mei 2026 · FFmpeg built-in*
