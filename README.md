# 🐧 Pangolin VPS Setup Script

Ein einfaches, automatisiertes Setup-Skript für VPS-Server mit Debian oder Ubuntu.  
Es übernimmt grundlegende Systemvorbereitungen und lädt den offiziellen Pangolin-Installer herunter.

---

## 🚀 Schnellstart

Führe diesen Befehl auf deinem Server aus:

```bash
wget -O - https://raw.githubusercontent.com/cheesli023/pangolin-vps-setup/main/install.sh | bash
```

Nach dem Durchlauf bekommst du einen direkten Befehl angezeigt, um die interaktive Pangolin-Installation zu starten.

---

## 🧰 Was wird eingerichtet?

| Schritt | Beschreibung                             |
|--------:|------------------------------------------|
| 1️⃣      | `apt update` und `apt upgrade -y`        |
| 2️⃣      | Einrichtung nützlicher Cronjobs          |
| 3️⃣      | Download des Pangolin Installers         |
| ✅      | Ausgabe des Startbefehls zur Installation |

---

## 🕒 Cronjobs im Detail

Das Skript richtet vier automatische Aufgaben (Cronjobs) ein:

| Zeitplan        | Befehl                                              | Zweck                                                                 |
|-----------------|-----------------------------------------------------|-----------------------------------------------------------------------|
| `0 3 * * *`      | `/sbin/shutdown -r now`                             | ⚙️ Täglicher Neustart um 03:00 Uhr für Stabilität                     |
| `0 4 * * 0`      | `apt clean && apt autoremove --purge -y`           | 🧹 Wöchentliche Systembereinigung am Sonntag um 04:00 Uhr              |
| `* * * * *`      | `/usr/local/bin/log-mem-status.sh`                 | 🧠 Minütliche RAM-Status-Protokollierung                              |
| `0 5 * * *`      | `/usr/local/bin/analyze-memwatch.sh`               | 📈 Tägliche RAM-Analyse um 05:00 Uhr                                   |

> ⚠️ Hinweis: Die Skripte `log-mem-status.sh` und `analyze-memwatch.sh` müssen vorhanden und ausführbar sein.

---

## 🔒 Sicherheit

- ✅ Nur `cheesli023` kann Änderungen am Skript vornehmen (Branch-Schutz aktiv)
- 🔓 Das Repository ist öffentlich lesbar, aber write-geschützt
- 📦 Der Pangolin-Installer wird direkt von der offiziellen GitHub-Release-Seite geladen

---

## 🧠 Hinweise

- Das Skript führt **keine automatische Pangolin-Installation** durch – es bereitet alles vor
- Die Ausführung des Installers erfolgt bewusst manuell durch den Benutzer (`sudo /usr/local/bin/pangolin_installer`)
- Kompatibel mit `x86_64` (amd64) und `aarch64` (arm64)

---

## 💬 Fragen?

Fragen oder Verbesserungsvorschläge?  
→ [Issue erstellen](https://github.com/cheesli023/pangolin-vps-setup/issues) oder Repo forken 🙌
