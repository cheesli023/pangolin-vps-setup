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
# Füge hier eine minimale config.yml Struktur ein
cat << 'EOF' > /etc/pangolin/config.yml
# Minimal Pangolin configuration - modify via interactive setup
# Diese minimale Datei erlaubt dem Container zu starten.
# Das interaktive Setup-Tool wird diese wahrscheinlich erweitern/ändern.
app:
  dashboard_url: http://localhost # Platzhalter - wird vom Setup wahrscheinlich geändert
server:
  hostname: pangolin # Muss dem Containernamen entsprechen
# Füge weitere notwendige minimale Sektionen hinzu, falls bekannt
traefik:
  http_entrypoint: web
  https_entrypoint: websecure # Gehe davon aus, dass HTTPS später konfiguriert wird
EOF

# --- NEUE SCHRITTE: Sync und kurze Pause nach Dateierstellung ---
sync # Stellt sicher, dass die Datei auf die Festplatte geschrieben wird
sleep 2 # Eine kurze zusätzliche Pause
# --- ENDE NEUE SCHRITTE ---


echo "🐳 Starte Docker-Container..."

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
  CONTAINER_STATUS=$(docker inspect --format '{{.State.Running}}' pangolin 2>/dev/null || echo "false")

  if [ "$CONTAINER_STATUS" = "true" ]; then
    echo "✅ Pangolin Container läuft."
    break # Schleife verlassen, da Container läuft
  fi

  # Überprüfe auch, ob der Container existiert, aber im Zustand 'exited' ist
  # Dies hilft, den Fehler "container is not running" schneller zu diagnostizieren, wenn er existiert aber nicht läuft
  CONTAINER_EXISTS=$(docker inspect pangolin >/dev/null 2>&1)
  if [ $? -eq 0 ]; then # Prüfe, ob der Befehl erfolgreich war (Container existiert)
      CONTAINER_RUNNING=$(docker inspect --format '{{.State.Running}}' pangolin 2>/dev/null || echo "false")
      if [ "$CONTAINER_RUNNING" != "true" ]; then
          echo "❌ Pangolin Container existiert, läuft aber nicht. Aktueller Status: $(docker inspect --format '{{.State.Status}}' pangolin 2>/dev/null)."
          echo "Bitte überprüfe die Logs des Containers manuell:"
          echo "  docker logs pangolin"
          # Füge auch Gerbil hinzu, falls der auch fehlschlägt
          echo "  docker logs gerbil"
          exit 1 # Skript mit Fehler beenden, wenn Container nicht läuft, aber existiert
      fi
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
  # Füge auch Gerbil hinzu, falls der auch fehlschlägt
  echo "  docker logs gerbil"
  exit 1 # Skript mit Fehler beenden
fi
# --- Ende der Warte-Logik ---


echo "✅ Pangolin-Setup wird jetzt automatisiert gestartet..."

# Versuche den interaktiven Setup-Befehl in einer erzwungenen TTY-Umgebung auszuführen
# /dev/null wird verwendet, um die von 'script' erstellte typescript-Datei zu verwerfen
script -c 'docker exec -it pangolin pangolin setup' /dev/null

echo "✅ Setup-Skript abgeschlossen."
