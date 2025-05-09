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

echo "✅ Container Startbefehle wurden ausgeführt."

# --- Warte, bis der Pangolin-Container wirklich läuft ---
echo "⏳ Warte auf Start des Pangolin Containers..."
TIMEOUT=60 # Maximale Wartezeit in Sekunden
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
  # Überprüfe den Status des Containers. --format '{{.State.Running}}' gibt 'true' oder 'false' zurück.
  # 2>/dev/null unterdrückt Fehlermeldungen, falls der Container z.B. noch nicht existiert
  CONTAINER_STATUS=$(docker inspect --format '{{.State.Running}}' pangolin 2>/dev/null || echo "false")

  if [ "$CONTAINER_STATUS" = "true" ]; then
    echo "✅ Pangolin Container läuft."
    break # Schleife verlassen, da Container läuft
  fi

  # Warte 5 Sekunden vor der nächsten Überprüfung
  sleep 5
  ELAPSED=$((ELAPSED + 5))
  echo "Warte noch ($ELAPSED/$TIMEOUT Sekunden)..."
done

# Überprüfe, ob die Schleife aufgrund eines Timeouts beendet wurde
if [ $ELAPSED -ge $TIMEOUT ]; then
  echo "❌ Zeitüberschreitung beim Warten auf den Pangolin Container."
  echo "Der Container ist nach $TIMEOUT Sekunden nicht gestartet."
  echo "Bitte überprüfe den Status und die Logs des Containers manuell, um das Problem zu finden:"
  echo "  docker ps -a"
  echo "  docker logs pangolin"
  exit 1 # Skript mit Fehler beenden
fi
# --- Ende der Warte-Logik ---


echo "✅ Pangolin-Setup wird jetzt automatisiert gestartet..."

# Versuche den interaktiven Setup-Befehl in einer erzwungenen TTY-Umgebung auszuführen
# /dev/null wird verwendet, um die von 'script' erstellte typescript-Datei zu verwerfen
script -c 'docker exec -it pangolin pangolin setup' /dev/null

echo "✅ Setup-Skript abgeschlossen."
