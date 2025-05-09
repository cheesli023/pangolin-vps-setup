#!/bin/bash
# VPS Setup-Skript mit verbesserter Konfigurationsübergabe und Startreihenfolge

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
timestamp=$(date +"%Y-%m-%m %H:%M:%S")
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

echo "📁 Konfig-Ordner anlegen und minimale Konfigurationen erstellen..."
mkdir -p /etc/pangolin /opt/traefik /opt/gerbil

# Create minimal Traefik configuration
cat << 'EOF' > /opt/traefik/traefik.toml
# Leere Traefik-Konfiguration
[entryPoints]
  [entryPoints.http]
    address = ":80"
EOF

# Create minimal Pangolin configuration - REQUIRED for container to start
cat << 'EOF' > /etc/pangolin/config.yml
# Minimal Pangolin configuration - modify via interactive setup
app:
  dashboard_url: http://localhost # Platzhalter - wird vom Setup wahrscheinlich geändert
server:
  hostname: pangolin # Muss dem Containernamen entsprechen
# Füge weitere notwendige minimale Sektionen hinzu, falls bekannt
traefik:
  http_entrypoint: web
  https_entrypoint: websecure # Gehe davon aus, dass HTTPS später konfiguriert wird
EOF

# Sicherstellen, dass die Dateien auf das Dateisystem geschrieben werden
sync
sleep 1 # Eine kurze Pause nach der Dateierstellung

echo "🐳 Starte Traefik Container..."
# Traefik
docker run -d   --name traefik   --network web   -p 80:80 -p 443:443   -v /opt/traefik/traefik.toml:/etc/traefik/traefik.toml   -v /var/run/docker.sock:/var/run/docker.sock   traefik:v3.3.5

echo "🐳 Erstelle Pangolin Container und kopiere Konfiguration..."
# Pangolin (erst erstellen, dann Konfig kopieren, dann starten)
# Verwende docker create anstelle von docker run -d
docker create   --name pangolin   --cap-add=NET_ADMIN   --network host   -v /etc/pangolin:/etc/pangolin   fosrl/pangolin:latest

# Kopiere die erstellte Konfigurationsdatei in den Container
# Dies umgeht potenzielle Timing-Probleme beim Volume-Mount direkt nach docker run
docker cp /etc/pangolin/config.yml pangolin:/etc/pangolin/config.yml

echo "🐳 Starte Pangolin Container..."
# Starte den Pangolin Container nach dem Kopieren der Konfig
docker start pangolin


echo "✅ Traefik und Pangolin Container (erstellt/gestartet) Startbefehle wurden ausgeführt."

# --- Warte, bis der Pangolin-Container wirklich läuft ---
echo "⏳ Warte auf Start des Pangolin Containers..."
TIMEOUT=90 # Erhöhte Wartezeit, da Startprobleme auftreten
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
  # Überprüfe den Status des Containers. --format '{{.State.Running}}' gibt 'true' oder 'false' zurück.
  CONTAINER_STATUS=$(docker inspect --format '{{.State.Running}}' pangolin 2>/dev/null || echo "false")

  if [ "$CONTAINER_STATUS" = "true" ]; then
    echo "✅ Pangolin Container läuft."
    break # Schleife verlassen, da Container läuft
  fi

  # Überprüfe auch, ob der Container existiert, aber im Zustand 'exited' ist
  CONTAINER_EXISTS=$(docker inspect pangolin >/dev/null 2>&1)
  if [ $? -eq 0 ]; then
      CONTAINER_RUNNING=$(docker inspect --format '{{.State.Running}}' pangolin 2>/dev/null || echo "false")
      if [ "$CONTAINER_RUNNING" != "true" ]; then
          echo "❌ Pangolin Container existiert, läuft aber nicht. Aktueller Status: $(docker inspect --format '{{.State.Status}}' pangolin 2>/dev/null)."
          echo "Bitte überprüfe die Logs des Containers manuell:"
          echo "  docker logs pangolin"
          # Hinweis: Gerbil wird jetzt später gestartet
          exit 1 # Skript mit Fehler beenden
      fi
  fi

  sleep 5
  ELAPSED=$((ELAPSED + 5))
  echo "Warte noch ($ELAPSED/$TIMEOUT Sekunden)..."
done

if [ $ELAPSED -ge $TIMEOUT ]; then
  echo "❌ Zeitüberschreitung beim Warten auf den Pangolin Container."
  echo "Der Container ist nach $TIMEOUT Sekunden nicht gestartet."
  echo "Bitte überprüfe den Status und die Logs des Containers manuell, um das Problem zu finden:"
  echo "  docker ps -a"
  echo "  docker logs pangolin"
  # Hinweis: Gerbil wird jetzt später gestartet
  exit 1 # Skript mit Fehler beenden
fi
# --- Ende der Warte-Logik ---


# --- Starte Gerbil erst, nachdem Pangolin läuft ---
echo "🐳 Starte Gerbil Container (Pangolin läuft)..."
docker run -d   --name gerbil   --network web   fosrl/gerbil:1.0.0-beta.3
echo "✅ Gerbil Startbefehl wurde ausgeführt."
sleep 5 # Kurze Pause, damit Gerbil Zeit hat, Pangolin zu kontaktieren


echo "✅ Pangolin-Setup wird jetzt automatisiert gestartet..."

# Versuche den interaktiven Setup-Befehl in einer erzwungenen TTY-Umgebung auszuführen
# /dev/null wird verwendet, um die von 'script' erstellte typescript-Datei zu verwerfen
script -c 'docker exec -it pangolin pangolin setup' /dev/null

echo "✅ Setup-Skript abgeschlossen."
