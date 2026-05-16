# Panduan Production Hardening

> **Prasyarat:** Panduan ini dijalankan **setelah** `install.sh` selesai dan semua container n8n sudah berjalan (`docker compose ps` menampilkan status `healthy`).
>
> Urutan: `install.sh` → verifikasi deploy → **panduan ini**

Panduan ini melengkapi `install.sh` dengan langkah-langkah keamanan tambahan untuk deployment production. Ikuti secara berurutan setelah instalasi dasar selesai.

---

## Daftar Isi

1. [Hardening SSH](#1-hardening-ssh)
2. [Firewall UFW](#2-firewall-ufw)
3. [Fail2ban — Blokir Brute Force](#3-fail2ban--blokir-brute-force)
4. [Automatic Security Updates](#4-automatic-security-updates)
5. [Traefik — HTTP Redirect & Rate Limiting](#5-traefik--http-redirect--rate-limiting)
6. [n8n — Konfigurasi Tambahan](#6-n8n--konfigurasi-tambahan)
7. [Monitoring & Alerting](#7-monitoring--alerting)
8. [Backup & Disaster Recovery](#8-backup--disaster-recovery)
9. [Checklist Production](#9-checklist-production)

---

## 1. Hardening SSH

Pilih salah satu cara membuat dan mendaftarkan SSH key:

---

### Opsi A — Terminal / CLI

**Buat SSH Key (di komputer lokal):**

```bash
ssh-keygen -t ed25519 -C "vps-n8n" -f ~/.ssh/n8n_vps
```

**Copy Public Key ke VPS:**

```bash
ssh-copy-id -i ~/.ssh/n8n_vps.pub root@<IP_VPS>
```

---

### Opsi B — Termius

**Langkah 1 — Buat key di Termius:**

1. Buka Termius → menu **Keychain** (ikon kunci di sidebar)
2. Klik **+ New Key**
3. Pilih tipe: `Ed25519`
4. Beri nama: `vps-n8n`
5. Klik **Generate** → key tersimpan di Keychain Termius

**Langkah 2 — Salin Public Key:**

1. Di Keychain, klik key yang baru dibuat
2. Klik **Copy Public Key** (atau ikon copy di sebelah public key)

**Langkah 3 — Daftarkan ke VPS:**

Login ke VPS (masih dengan password), lalu jalankan:

```bash
mkdir -p ~/.ssh && chmod 700 ~/.ssh

# Paste public key dari Termius
echo "PASTE_PUBLIC_KEY_DI_SINI" >> ~/.ssh/authorized_keys

chmod 600 ~/.ssh/authorized_keys
```

**Langkah 4 — Konfigurasi host di Termius:**

1. Buka host VPS di Termius → **Edit**
2. Pada bagian **Keys** → pilih key `vps-n8n` yang sudah dibuat
3. Simpan dan coba koneksi — harus berhasil tanpa password

---

### Konfigurasi SSH Server (berlaku untuk kedua opsi)

```bash
nano /etc/ssh/sshd_config
```

Ubah / tambahkan baris berikut:

```
# Nonaktifkan login password
PasswordAuthentication no
ChallengeResponseAuthentication no

# Nonaktifkan root login via password (izinkan key saja)
PermitRootLogin prohibit-password

# Batasi percobaan login
MaxAuthTries 3
MaxSessions 5

# Timeout koneksi idle (5 menit)
ClientAliveInterval 300
ClientAliveCountMax 2

# Nonaktifkan fitur yang tidak dipakai
X11Forwarding no
AllowAgentForwarding no
AllowTcpForwarding no
```

Restart SSH:

```bash
systemctl restart ssh
```

> ⚠️ **Jangan tutup sesi yang sedang aktif** sebelum memastikan login dengan key berhasil dari sesi/tab baru:
> - **Terminal:** `ssh -i ~/.ssh/n8n_vps root@<IP_VPS>`
> - **Termius:** buka tab baru → connect ke host VPS


---

## 2. Firewall UFW

### Aktifkan dengan rules yang ketat

```bash
# Reset ke default
ufw --force reset

# Default: tolak semua masuk, izinkan semua keluar
ufw default deny incoming
ufw default allow outgoing

# Izinkan SSH
ufw allow 22/tcp comment 'SSH'

# Izinkan HTTP dan HTTPS untuk Traefik
ufw allow 80/tcp comment 'HTTP Traefik'
ufw allow 443/tcp comment 'HTTPS Traefik'

# Aktifkan
ufw --force enable

# Verifikasi
ufw status numbered
```

Output yang diharapkan:

```
Status: active

     To                         Action      From
     --                         ------      ----
[ 1] 22/tcp                     ALLOW IN    Anywhere
[ 2] 80/tcp                     ALLOW IN    Anywhere
[ 3] 443/tcp                    ALLOW IN    Anywhere
```

> **Catatan:** Port PostgreSQL (5432), Redis (6379), dan n8n (5678) **tidak** dibuka — hanya bisa diakses melalui Docker internal network `n8n-net`.

---

## 3. Fail2ban — Blokir Brute Force

### Install

```bash
apt install -y fail2ban
```

### Konfigurasi

```bash
cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 5
backend  = systemd

[sshd]
enabled  = true
port     = 22
logpath  = %(sshd_log)s
maxretry = 3
bantime  = 86400
EOF
```

### Aktifkan

```bash
systemctl enable fail2ban
systemctl start fail2ban

# Cek status
fail2ban-client status
fail2ban-client status sshd
```

---

## 4. Automatic Security Updates

### Install dan konfigurasi unattended-upgrades

```bash
apt install -y unattended-upgrades apt-listchanges
```

```bash
cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF
```

```bash
# Baca email dari .env yang sudah terpasang
EMAIL=$(grep "^EMAIL=" /opt/automator/n8n/.env | cut -d'=' -f2-)

cat > /etc/apt/apt.conf.d/50unattended-upgrades << EOF
Unattended-Upgrade::Allowed-Origins {
    "\${distro_id}:\${distro_codename}-security";
};
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Mail "$EMAIL";
EOF
```

### Test dry-run

```bash
unattended-upgrade --dry-run --debug 2>&1 | head -20
```

---

## 5. Traefik — HTTP Redirect & Rate Limiting

### Tambahkan HTTP → HTTPS redirect

Script instalasi membuka port 80 dan 443, tapi **belum** mengkonfigurasi redirect otomatis HTTP → HTTPS. Tambahkan sekarang:

```bash
cd /opt/automator/n8n
nano docker-compose.yml
```

Pada bagian `command:` service `n8n-traefik`, tambahkan **setelah** baris `--entrypoints.web.address=:80`:

```yaml
      - "--entrypoints.web.http.redirections.entrypoint.to=websecure"
      - "--entrypoints.web.http.redirections.entrypoint.scheme=https"
      - "--entrypoints.web.http.redirections.entrypoint.permanent=true"
```

### Tambahkan Rate Limiting

Pada bagian `labels:` service `n8n`, tambahkan:

```yaml
      - "traefik.http.middlewares.n8n-ratelimit.ratelimit.average=100"
      - "traefik.http.middlewares.n8n-ratelimit.ratelimit.burst=50"
      - "traefik.http.middlewares.n8n-ratelimit.ratelimit.period=1m"
      - "traefik.http.routers.n8n.middlewares=n8n-ratelimit@docker"
```

### Apply perubahan

```bash
docker compose down && docker compose up -d
```

### Verifikasi redirect

```bash
# Harus redirect ke https (301)
curl -I http://$(grep "^DOMAIN=" /opt/automator/n8n/.env | cut -d'=' -f2-)
```

---

## 6. n8n — Konfigurasi Tambahan

### Variabel `.env` yang relevan untuk production

Nilai default yang dipasang oleh `install.sh`:

```bash
nano /opt/automator/n8n/.env
```

| Variabel | Default (install.sh) | Rekomendasi production |
|----------|---------------------|----------------------|
| `N8N_LOG_LEVEL` | `info` | `warn` — kurangi noise log |
| `EXECUTIONS_TIMEOUT` | `-1` (unlimited) | Sesuaikan kebutuhan, misal `3600` |
| `N8N_PAYLOAD_SIZE_MAX` | `512` MB | Turunkan jika tidak butuh payload besar |
| `N8N_COMMUNITY_PACKAGES_ENABLED` | `true` | `false` jika tidak dipakai |

Contoh penyesuaian:

```env
N8N_LOG_LEVEL=warn
```

Setelah edit:

```bash
docker compose down && docker compose up -d
```

### Buat non-root user untuk SSH (opsional tapi disarankan)

```bash
adduser --disabled-password --gecos "" deployer
usermod -aG sudo deployer
usermod -aG docker deployer

# Copy authorized keys dari root
mkdir -p /home/deployer/.ssh
cp /root/.ssh/authorized_keys /home/deployer/.ssh/
chown -R deployer:deployer /home/deployer/.ssh
chmod 700 /home/deployer/.ssh
chmod 600 /home/deployer/.ssh/authorized_keys
```

---

## 7. Monitoring & Alerting

Script monitoring ini membaca konfigurasi dari `.env` yang sudah ada, termasuk `TG_BOT_TOKEN` dan `TG_USER_ID`.

### Cron monitoring — alert jika container down

```bash
cat > /opt/automator/n8n/check_health.sh << 'SCRIPT'
#!/bin/bash
cd /opt/automator/n8n

CONTAINERS=("n8n" "n8n-worker" "n8n-postgres" "n8n-redis" "n8n-traefik" "n8n-bot")
FAILED=()

for c in "${CONTAINERS[@]}"; do
    STATUS=$(docker inspect --format='{{.State.Status}}' "$c" 2>/dev/null)
    if [[ "$STATUS" != "running" ]]; then
        FAILED+=("$c (status: ${STATUS:-not found})")
    fi
done

if [[ ${#FAILED[@]} -gt 0 ]]; then
    source /opt/automator/n8n/.env
    MSG="⚠️ *n8n Health Alert*%0A%0AContainer bermasalah:%0A"
    for f in "${FAILED[@]}"; do
        MSG+="• $f%0A"
    done
    curl -sf -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TG_USER_ID}" \
        -d "text=${MSG}" \
        -d "parse_mode=Markdown" > /dev/null 2>&1
fi
SCRIPT

chmod +x /opt/automator/n8n/check_health.sh

# Jalankan setiap 5 menit
(crontab -l 2>/dev/null | grep -v check_health; \
 echo "*/5 * * * * /opt/automator/n8n/check_health.sh") | crontab -

# Verifikasi
crontab -l
```

### Monitoring disk — alert jika hampir penuh

```bash
cat > /opt/automator/n8n/check_disk.sh << 'SCRIPT'
#!/bin/bash
THRESHOLD=80
USAGE=$(df / | awk 'NR==2{print $5}' | tr -d '%')

if (( USAGE >= THRESHOLD )); then
    source /opt/automator/n8n/.env
    curl -sf -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TG_USER_ID}" \
        -d "text=⚠️ *Disk Alert*%0A%0ADisk usage: ${USAGE}%%0AServer: $(hostname)" \
        -d "parse_mode=Markdown" > /dev/null 2>&1
fi
SCRIPT

chmod +x /opt/automator/n8n/check_disk.sh

# Jalankan setiap jam
(crontab -l 2>/dev/null | grep -v check_disk; \
 echo "0 * * * * /opt/automator/n8n/check_disk.sh") | crontab -
```

### Test manual

Ikuti 3 langkah berurutan:

**Step 1 — Verifikasi bot token & koneksi Telegram**

```bash
source /opt/automator/n8n/.env

curl -s "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
  -d "chat_id=${TG_USER_ID}" \
  -d "text=✅ Test notifikasi dari VPS: $(hostname)" | jq .ok
```

Output harus `true`. Jika `false`, periksa `TG_BOT_TOKEN` dan `TG_USER_ID` di `.env`.

**Step 2 — Test health alert (paksa trigger)**

```bash
# Stop 1 container sementara
docker stop n8n-bot

# Jalankan script — harus kirim alert ke Telegram
bash /opt/automator/n8n/check_health.sh

# Hidupkan kembali
docker start n8n-bot
```

**Step 3 — Test disk alert (paksa trigger)**

```bash
# Jalankan dengan threshold sementara = 1% untuk memaksa alert
THRESHOLD=1 bash -c '
source /opt/automator/n8n/.env
USAGE=$(df / | awk "NR==2{print \$5}" | tr -d "%")
if (( USAGE >= THRESHOLD )); then
    curl -sf -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TG_USER_ID}" \
        -d "text=✅ *Disk alert test OK*%0ADisk: ${USAGE}%%" \
        -d "parse_mode=Markdown" > /dev/null && echo "Alert terkirim"
fi
'
```


---

## 8. Backup & Disaster Recovery

### Backup sudah terjadwal otomatis

`install.sh` sudah mengkonfigurasi cron backup harian pukul 02:00:

```bash
# Verifikasi jadwal
crontab -l | grep backup

# Buat backup manual sekarang
cd /opt/automator/n8n && ./backup_n8n.sh

# Lihat hasil backup
ls -lh /opt/automator/n8n/backups/
```

### Strategi 3-2-1 — backup ke remote

- **3** salinan | **2** media berbeda | **1** offsite

```bash
# Install rclone
curl https://rclone.org/install.sh | sudo bash

# Konfigurasi provider (S3, GCS, Backblaze B2, dll)
rclone config
```

Setelah rclone dikonfigurasi, tambahkan sync di akhir `backup_n8n.sh`:

```bash
nano /opt/automator/n8n/backup_n8n.sh

# Tambahkan sebelum baris exit terakhir:
# rclone copy /opt/automator/n8n/backups/ remote:n8n-backups/ --min-age 1m
```

### Test restore — wajib dilakukan sebelum production

```bash
cd /opt/automator/n8n

# 1. Buat backup
./backup_n8n.sh

# 2. Lihat file backup yang dihasilkan
ls -lh backups/

# 3. Jalankan restore (ke staging/test server)
./restore_n8n.sh backups/<nama_file_backup>
```

> ⚠️ Backup yang belum pernah di-test adalah backup yang tidak berguna. Lakukan test restore minimal sekali ke environment staging.

---

## 9. Checklist Production

Jalankan script ini setelah semua langkah di atas selesai. Script membaca domain dari `.env` yang ada:

```bash
#!/bin/bash
source /opt/automator/n8n/.env

echo "=== Production Readiness Checklist ==="
echo "Domain: $DOMAIN"
echo ""

# 1. SSH Key login
echo -n "[SSH]    Key-based auth: "
grep -q "PasswordAuthentication no" /etc/ssh/sshd_config && echo "✅" || echo "❌ — jalankan Bagian 1"

# 2. UFW aktif
echo -n "[UFW]    Firewall aktif: "
ufw status | grep -q "Status: active" && echo "✅" || echo "❌ — jalankan Bagian 2"

# 3. Fail2ban aktif
echo -n "[F2BAN]  Fail2ban aktif: "
systemctl is-active fail2ban &>/dev/null && echo "✅" || echo "❌ — jalankan Bagian 3"

# 4. Auto-updates
echo -n "[APT]    Auto security updates: "
[[ -f /etc/apt/apt.conf.d/20auto-upgrades ]] && echo "✅" || echo "❌ — jalankan Bagian 4"

# 5. HTTP redirect ke HTTPS
echo -n "[TRAEFIK] HTTP → HTTPS redirect: "
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://${DOMAIN}" 2>/dev/null)
[[ "$HTTP_CODE" == "301" || "$HTTP_CODE" == "308" ]] && echo "✅" || echo "❌ (HTTP code: $HTTP_CODE) — jalankan Bagian 5"

# 6. Container semua running
echo -n "[DOCKER] Semua container healthy: "
UNHEALTHY=$(docker ps --filter "health=unhealthy" --format "{{.Names}}" | wc -l)
NOT_RUNNING=$(docker ps -a --filter "status=exited" --format "{{.Names}}" | grep -E "n8n" | wc -l)
[[ "$UNHEALTHY" -eq 0 && "$NOT_RUNNING" -eq 0 ]] && echo "✅" || echo "❌ ($UNHEALTHY unhealthy, $NOT_RUNNING exited)"

# 7. HTTPS / SSL valid
echo -n "[SSL]    Sertifikat valid: "
EXPIRY=$(echo | openssl s_client -servername "${DOMAIN}" \
    -connect "${DOMAIN}:443" 2>/dev/null | \
    openssl x509 -noout -dates 2>/dev/null | grep notAfter | cut -d= -f2)
[[ -n "$EXPIRY" ]] && echo "✅ (exp: $EXPIRY)" || echo "❌"

# 8. Backup terjadwal
echo -n "[CRON]   Backup terjadwal: "
crontab -l 2>/dev/null | grep -q "backup_n8n" && echo "✅" || echo "❌ — cek install.sh"

# 9. Health monitoring
echo -n "[CRON]   Health monitoring: "
crontab -l 2>/dev/null | grep -q "check_health" && echo "✅" || echo "❌ — jalankan Bagian 7"

# 10. Disk monitoring
echo -n "[CRON]   Disk monitoring: "
crontab -l 2>/dev/null | grep -q "check_disk" && echo "✅" || echo "❌ — jalankan Bagian 7"

# 11. SWAP
echo -n "[SWAP]   SWAP configured: "
swapon --show | grep -q "/" && echo "✅" || echo "❌ — install.sh seharusnya sudah set ini"

echo ""
echo "=== Selesai ==="
```

Simpan dan jalankan:

```bash
nano /opt/automator/n8n/check_production.sh
# paste script di atas, lalu:
chmod +x /opt/automator/n8n/check_production.sh
bash /opt/automator/n8n/check_production.sh
```

---

## Referensi Versi (Mei 2026)

| Komponen | Versi |
|----------|-------|
| n8n | 2.20.9 |
| Redis | 8.6.3 |
| Traefik | v3 |
| PostgreSQL | 16 |
| Docker | 29.5.0 |
| Ubuntu | 24.04 LTS |

---

*Panduan ini adalah pelengkap dari `install.sh` v4.0.*
