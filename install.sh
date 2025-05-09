#!/bin/bash

# --- Schritt 1: System aktualisieren ---
echo "🛠  Führe apt update & upgrade aus..."
sudo apt update && sudo apt upgrade -y

# --- Schritt 2: Cronjobs einrichten ---
echo "📆 Füge benutzerdefinierte Cronjobs hinzu..."

TMP_CRON=$(mktemp)
crontab -l 2>/dev/null > "$TMP_CRON"

echo "0 3 * * * /sbin/shutdown -r now" >> "$TMP_CRON"
echo "0 4 * * 0 apt clean && apt autoremove --purge -y" >> "$TMP_CRON"
echo "* * * * * /usr/local/bin/log-mem-status.sh" >> "$TMP_CRON"
echo "0 5 * * * /usr/local/bin/analyze-memwatch.sh" >> "$TMP_CRON"

crontab "$TMP_CRON"
rm "$TMP_CRON"

# --- Schritt 3: Pangolin-Installer herunterladen ---
echo "⬇️  Lade Pangolin-Installer herunter..."

ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
URL="https://github.com/fosrl/pangolin/releases/download/1.3.1/installer_linux_$ARCH"

# Zielpfad mit Fallback
if [ -w /usr/local/bin ]; then
  INSTALLER_PATH="/usr/local/bin/pangolin_installer"
  USE_SUDO=true
elif [ -d "$HOME/.local/bin" ] && [ -w "$HOME/.local/bin" ]; then
  INSTALLER_PATH="$HOME/.local/bin/pangolin_installer"
  USE_SUDO=false
else
  INSTALLER_PATH="$(mktemp /tmp/pangolin_installer.XXXXXX)"
  USE_SUDO=false
fi

# Herunterladen
if [ "$USE_SUDO" = true ]; then
  sudo wget -O "$INSTALLER_PATH" "$URL"
  sudo chmod +x "$INSTALLER_PATH"
else
  wget -O "$INSTALLER_PATH" "$URL"
  chmod +x "$INSTALLER_PATH"
fi

# Pfadprüfung
if [ ! -x "$INSTALLER_PATH" ]; then
  echo "❌ Fehler: Installer konnte nicht heruntergeladen oder ausführbar gemacht werden."
  exit 1
fi

# Kommandovorschlag
if [ "$USE_SUDO" = true ]; then
  RUN_CMD="sudo $INSTALLER_PATH"
else
  RUN_CMD="$INSTALLER_PATH"
fi

# --- Abschlussmeldung ---
echo ""
echo "✅ Das Skript wurde erfolgreich ausgeführt."
echo ""
echo "👉 Starte jetzt die interaktive Einrichtung mit:"
echo ""
echo "    $RUN_CMD"
echo ""
