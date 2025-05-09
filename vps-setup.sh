#!/bin/bash
# VPS Wiederherstellungs-/Installationsskript für Pangolin, Gerbil und Traefik
# Basisstruktur ohne produktive Tunnelkonfiguration

set -e

echo "🔧 System aktualisieren & benötigte Pakete installieren..."
apt update && apt upgrade -y
apt install -y docker.io curl nano cron unzip

echo "📦 Swap-Datei (1 GB) einrichten..."
fallocate -l 1G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
grep -q "/swapfile" /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab

echo "📝 RAM-/Swap-Logging-Skript installieren..."
cat << 'EOF' > /usr/local/bin/log-mem-status.sh
#!/bin/bash
timestamp=$(date +"%Y-%m-%d %H:%M:%S")
meminfo=$(free -m | grep -E 'Mem|Swap' | awk '{print $1 ": " $3 "/" $2 " MB"}')
echo "$timestamp | $meminfo" >> /var/log/memwatch.log
EOF
chmod +x /usr/local/bin/log-mem-status.sh

echo "🕒 Cronjobs einrichten..."
# Logging jede Minute
( crontab -l 2>/dev/null; echo "* * * * * /usr/local/bin/log-mem-status.sh" ) | crontab -
# APT Cleanup sonntags um 04:00
( crontab -l 2>/dev/null; echo "0 4 * * 0 apt clean && apt autoremove --purge -y" ) | crontab -
# Täglicher Reboot um 03:00
( crontab -l 2>/dev/null; echo "0 3 * * * /sbin/reboot" ) | crontab -

echo "🌐 Docker-Netzwerk vorbereiten..."
docker network create web || true

echo "📁 Leere Konfigurationsordner anlegen..."
mkdir -p /etc/pangolin
mkdir -p /opt/traefik
mkdir -p /opt/gerbil

cat << 'EOF' > /opt/traefik/traefik.toml
# Leere Traefik-Konfiguration
[entryPoints]
  [entryPoints.http]
    address = ":80"
EOF

echo "🐳 Docker-Container starten (mit leeren Konfigurationen)..."
# Traefik
docker run -d   --name traefik   --network web   -p 80:80 -p 443:443   -v /opt/traefik/traefik.toml:/etc/traefik/traefik.toml   -v /var/run/docker.sock:/var/run/docker.sock   traefik:v3.3.5

# Pangolin mit offiziellen Parametern, aber leerer Config
docker run -d   --name pangolin   --cap-add=NET_ADMIN   --network host   -v /etc/pangolin:/etc/pangolin   fosrl/pangolin:latest

# Gerbil
docker run -d   --name gerbil   --network web   fosrl/gerbil:1.0.0-beta.3

echo "✅ Setup abgeschlossen! Container laufen mit leerer Konfiguration."
free -m
df -h
