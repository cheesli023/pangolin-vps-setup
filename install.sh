#!/bin/bash

# --- Schritt 1: System aktualisieren ---
echo "Führe apt update & upgrade aus..."
sudo apt update && sudo apt upgrade -y

# --- Schritt 2: Cronjobs einrichten ---
echo "Füge benutzerdefinierte Cronjobs hinzu..."

TMP_CRON=$(mktemp)
crontab -l 2>/dev/null > "$TMP_CRON"

echo "0 3 * * * /sbin/shutdown -r now" >> "$TMP_CRON"
echo "0 4 * * 0 apt clean && apt autoremove --purge -y" >> "$TMP_CRON"
echo "* * * * * /usr/local/bin/log-mem-status.sh" >> "$TMP_CRON"
echo "0 5 * * * /usr/local/bin/analyze-memwatch.sh" >> "$TMP_CRON"

crontab "$TMP_CRON"
rm "$TMP_CRON"

# --- Schritt 3: Installer nur herunterladen ---
echo "Lade Pangolin-Installer herunter..."

ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
URL="https://github.com/fosrl/pangolin/releases/download/1.3.1/installer_linux_$ARCH"
INSTALLER_PATH="/tmp/pangolin_installer"

wget -O "$INSTALLER_PATH" "$URL"

if [ $? -ne 0 ]; then
  echo "Download fehlgeschlagen von $URL"
  exit 1
fi

chmod +x "$INSTALLER_PATH"

echo ""
echo "✅ Installer wurde erfolgreich heruntergeladen nach: $INSTALLER_PATH"
echo "👉 Starte ihn jetzt manuell mit:"
echo ""
echo "    $INSTALLER_PATH"
echo ""
echo "Du wirst dann nach dem Admin-Passwort gefragt."
