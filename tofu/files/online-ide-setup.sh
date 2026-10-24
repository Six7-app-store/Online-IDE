#!/usr/bin/env bash
# Richtet die Online-IDE beim ersten Start der Team-VM ein. cloud-init hat
# vorher die Linux-Nutzer angelegt und abgelegt:
#
#   /etc/online-ide/users           "<nutzer> <port>" je Zeile
#   /etc/online-ide/passwords/<n>   Passwort je Nutzer, nur für root lesbar
#   /opt/online-ide/aufgaben/       Standard-Aufgaben (Java)
#   /var/lib/online-ide/upload/     hochgeladene Aufgabe des Teams (optional)
#
# Jede Person bekommt einen eigenen code-server. Er lauscht nur auf
# 127.0.0.1; nginx reicht ihn auf ihrem öffentlichen Port weiter, und zwar
# für IPv4 und IPv6 (code-server selbst bindet nur eine Adresse).
#
# Bricht das Skript ab, scheitert cloud-final.service, und der App Store
# meldet das Deployment als fehlgeschlagen (ADR 0011 im deployment-Repo).
set -euo pipefail

log() { echo "[online-ide] $*"; }

USERS_FILE=/etc/online-ide/users
UPLOAD_DIR=/var/lib/online-ide/upload
# code-server lauscht intern 10000 Ports über dem öffentlichen Port.
INTERNAL_OFFSET=10000

export DEBIAN_FRONTEND=noninteractive
# cloud-init startet runcmd ohne HOME; das code-server-Installationsskript
# (set -u) braucht es.
export HOME=/root

# Beim ersten Boot hält oft apt-daily die dpkg-Sperre; warten statt scheitern.
apt_get() { apt-get -y -q -o DPkg::Lock::Timeout=600 "$@"; }

log "Pakete installieren"
apt_get update
apt_get install --no-install-recommends \
  build-essential \
  ca-certificates \
  curl \
  git \
  nginx \
  openjdk-21-jdk-headless \
  python3 \
  python3-pip \
  python3-venv \
  unzip

log "code-server installieren"
curl -fsSL https://code-server.dev/install.sh | sh
code-server --version

# Nutzerliste vorab lesen: Befehle in einer "while read"-Schleife würden
# sonst die restlichen Zeilen von stdin verschlucken.
users=()
ports=()
while read -r user port; do
  [ -n "$user" ] || continue
  users+=("$user")
  ports+=("$port")
done <"$USERS_FILE"

nginx_conf=/etc/nginx/sites-available/online-ide
: >"$nginx_conf"

for i in "${!users[@]}"; do
  user=${users[$i]}
  port=${ports[$i]}
  internal=$((port + INTERNAL_OFFSET))
  home=$(getent passwd "$user" | cut -d: -f6)
  group=$(id -gn "$user")
  log "$user einrichten (Port $port)"

  # Aufgabe aus dem Wizard: ZIPs entpacken, alles andere kopieren. Ohne
  # Upload gibt es die Standard-Aufgaben.
  workdir="$home/Coding-Aufgabe"
  mkdir -p "$workdir"
  if compgen -G "$UPLOAD_DIR/*" >/dev/null; then
    for src in "$UPLOAD_DIR"/*; do
      case "${src,,}" in
        *.zip) unzip -o -q "$src" -d "$workdir" -x '__MACOSX/*' ;;
        *)     cp "$src" "$workdir/" ;;
      esac
    done
  else
    cp /opt/online-ide/aufgaben/*.java "$workdir/"
  fi
  chown -R "$user:$group" "$workdir"

  runuser -u "$user" -- mkdir -p \
    "$home/.config/code-server" \
    "$home/.local/share/code-server/User" </dev/null

  # Passwort in Anführungszeichen, damit YAML nichts davon umdeutet.
  (
    umask 077
    cat >"$home/.config/code-server/config.yaml" <<EOF
bind-addr: 127.0.0.1:${internal}
auth: password
password: "$(cat "/etc/online-ide/passwords/$user")"
cert: false
disable-telemetry: true
disable-update-check: true
EOF
  )
  chown "$user:$group" "$home/.config/code-server/config.yaml"

  settings="$home/.local/share/code-server/User/settings.json"
  if [ ! -e "$settings" ]; then
    cat >"$settings" <<'EOF'
{
  "security.workspace.trust.enabled": false,
  "workbench.startupEditor": "none",
  "telemetry.telemetryLevel": "off",
  "terminal.integrated.defaultProfile.linux": "bash"
}
EOF
    chown "$user:$group" "$settings"
  fi

  # Der Dienst code-server@ kommt mit dem Paket.
  systemctl enable --now "code-server@$user"

  # code-server braucht WebSockets, daher Upgrade und HTTP/1.1.
  cat >>"$nginx_conf" <<EOF
server {
    listen ${port};
    listen [::]:${port};
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:${internal};
        proxy_http_version 1.1;
        proxy_set_header Host \$http_host;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection upgrade;
        proxy_set_header Accept-Encoding gzip;
        client_max_body_size 50M;
    }
}

EOF
done

rm -rf "$UPLOAD_DIR" /etc/online-ide/passwords

log "nginx einrichten"
ln -sf "$nginx_conf" /etc/nginx/sites-enabled/online-ide
rm -f /etc/nginx/sites-enabled/default
nginx -t
# restart statt reload: reload scheitert, falls nginx nach der Installation
# nicht gestartet wurde
systemctl enable nginx
systemctl restart nginx

# Erst fertig melden, wenn jede IDE über nginx antwortet
for port in "${ports[@]}"; do
  ok=
  for _ in $(seq 1 30); do
    if curl -sf -o /dev/null "http://localhost:${port}/healthz"; then
      ok=1
      break
    fi
    sleep 2
  done
  if [ -z "$ok" ]; then
    log "IDE auf Port $port antwortet nicht"
    exit 1
  fi
done

log "Alle IDEs erreichbar"
