#!/bin/bash
# VPS Setup-Skript mit automatischem Pangolin CLI-Wizard nach Containerstart

set -e

echo "🔧 System aktualisieren & Pakete installieren..."
apt update && apt upgrade -y
apt install -y docker.io curl nano cron unzip -y

echo "📦 Swap prüfen..."
if grep -q "SwapTotal: 0" /proc/meminfo; then
  echo "➡️  Kein Swap vorhanden – versuche Swap-Datei anzulegen..."
  fallocate -l 1G /swapfile &&   chmod 600 /swapfile &&   mkswap /swapfile &&   swapon /swapfile &&   grep -q "/swapfile" /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  echo "✅ Swap-Datei erfolgreich eingerichtet."
else
  echo "⚠️  Swap bereits vorhanden oder vom Provider verwaltet – überspringe Einrichtung."
fi

echo "📝 Logging-Skript installieren..."
cat << 'EOF' > /usr/local/bin/log-mem-status.sh
#!/bin/bash
timestamp=$(date +"%Y-%m-%d %H:%M:%S")
meminfo=$(free -m | grep -E 'Mem|Swap' | awk '{print $1 ": " $3 "/" $2 " MB"}')
echo "$timestamp | $meminfo" >> /var/log/memwatch.log
EOF
chmod +x /usr/local/bin/log-mem-status.sh

echo "🕒 Cronjobs einrichten..."
( crontab -l 2>/dev/null; echo "* * * * * /usr/local/bin/log-mem-status.sh" ) | crontab -
( crontab -l 2>/dev/null; echo "0 4 * * 0 apt clean && apt autoremove --purge -y" ) | crontab -
( crontab -l 2>/dev/null; echo "0 3 * * * /sbin/reboot" ) | crontab -

echo "🌐 Docker-Netzwerk vorbereiten..."
docker network create web || true

echo "📁 Leere Konfig-Ordner anlegen..."
mkdir -p /etc/pangolin /opt/traefik /opt/gerbil

cat << 'EOF' > /opt/traefik/traefik.toml
# Leere Traefik-Konfiguration
[entryPoints]
  [entryPoints.http]
    address = ":80"
EOF

echo "🐳 Starte Docker-Container mit leerer Konfiguration..."

# Traefik
docker run -d   --name traefik   --network web   -p 80:80 -p 443:443   -v /opt/traefik/traefik.toml:/etc/traefik/traefik.toml   -v /var/run/docker.sock:/var/run/docker.sock   traefik:v3.3.5

# Pangolin
docker run -d   --name pangolin   --cap-add=NET_ADMIN   --network host   -v /etc/pangolin:/etc/pangolin   fosrl/pangolin:latest

# Gerbil
docker run -d   --name gerbil   --network web   fosrl/gerbil:1.0.0-beta.3

echo "✅ Container laufen. Pangolin-Setup wird jetzt automatisiert gestartet..."

sleep 10 # Kurze Pause, um sicherzustellen, dass Container wirklich bereit sind

# Versuche den interaktiven Setup-Befehl in einer erzwungenen TTY-Umgebung auszuführen
# /dev/null wird verwendet, um die von 'script' erstellte typescript-Datei zu verwerfen
script -c 'docker exec -it pangolin pangolin setup' /dev/null

echo "✅ Setup-Skript abgeschlossen."
