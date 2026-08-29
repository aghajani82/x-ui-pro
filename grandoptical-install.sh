#!/usr/bin/env bash
set -Eeuo pipefail

# GrandOptical x-ui-pro custom installer
# Ubuntu 24.04 + Nginx + Certbot + 3x-UI 3.7.0 + Xray/XHTTP + Subscription
# Deliberately excludes v2rayA, sing-box/ArgosBX, WARP and Tor.

XUI_VERSION="${XUI_VERSION:-v3.7.0}"
SSH_PORT="${SSH_PORT:-5055}"
TIMEZONE="${TIMEZONE:-Asia/Tehran}"
SWAP_SIZE="${SWAP_SIZE:-2G}"
UFW_ENABLE="${UFW_ENABLE:-on}"
DOMAIN="${DOMAIN:-}"
XUI_PANEL_PORT="${XUI_PANEL_PORT:-}"
XUI_USERNAME="${XUI_USERNAME:-}"
XUI_PASSWORD="${XUI_PASSWORD:-}"
XUI_WEB_BASE_PATH="${XUI_WEB_BASE_PATH:-}"

log(){ printf '\033[1;36m[INFO]\033[0m %s\n' "$*"; }
ok(){ printf '\033[1;32m[ OK ]\033[0m %s\n' "$*"; }
warn(){ printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
die(){ printf '\033[1;31m[FAIL]\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage:
  sudo bash grandoptical-install.sh -d panel.example.com

Options:
  -d, --domain DOMAIN        Domain used by Nginx/SSL/Subscription
  -s, --ssh-port PORT        SSH port (default: 5055)
  --xui-version VERSION      3x-UI tag (default: v3.7.0)
  --timezone TZ              default: Asia/Tehran
  --swap SIZE                default: 2G
  --no-ufw                   do not enable UFW
EOF
}

while (($#)); do
  case "$1" in
    -d|--domain) DOMAIN="${2:-}"; shift 2;;
    -s|--ssh-port) SSH_PORT="${2:-}"; shift 2;;
    --xui-version) XUI_VERSION="${2:-}"; shift 2;;
    --timezone) TIMEZONE="${2:-}"; shift 2;;
    --swap) SWAP_SIZE="${2:-}"; shift 2;;
    --no-ufw) UFW_ENABLE="off"; shift;;
    -h|--help) usage; exit 0;;
    *) die "Unknown option: $1";;
  esac
done

[[ $EUID -eq 0 ]] || die "Run as root."
[[ -f /etc/os-release ]] || die "Cannot detect OS."
. /etc/os-release
[[ "$ID" == "ubuntu" ]] || die "This custom installer currently targets Ubuntu."
[[ "${VERSION_ID:-}" == "24.04" ]] || warn "Tested target is Ubuntu 24.04; detected ${PRETTY_NAME:-unknown}."

is_port(){ [[ "$1" =~ ^[0-9]+$ ]] && ((1 <= 10#$1 && 10#$1 <= 65535)); }
is_domain(){ [[ "$1" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$ ]]; }

[[ -n "$DOMAIN" ]] || read -r -p "Domain: " DOMAIN
DOMAIN="${DOMAIN//[[:space:]]/}"
is_domain "$DOMAIN" || die "Invalid domain: $DOMAIN"
is_port "$SSH_PORT" || die "Invalid SSH port: $SSH_PORT"

log "Installing base packages..."
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  nginx nginx-full certbot python3-certbot-nginx sqlite3 curl wget jq openssl ufw ca-certificates cron

timedatectl set-timezone "$TIMEZONE"
ok "Timezone: $(timedatectl show -p Timezone --value)"

if swapon --show --noheadings | grep -q .; then
  ok "Swap already exists; leaving it unchanged."
else
  fallocate -l "$SWAP_SIZE" /swapfile
  chmod 600 /swapfile
  mkswap /swapfile >/dev/null
  swapon /swapfile
  grep -qE '^/swapfile[[:space:]]' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  ok "Swap enabled: $SWAP_SIZE"
fi

cat >/etc/sysctl.d/99-grandoptical.conf <<'EOF'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
vm.swappiness=10
EOF
sysctl --system >/dev/null
ok "BBR/qdisc/swappiness configured."

# On a fresh server, the stock OpenSSH configuration normally has no explicit
# Port directive. Comment any existing explicit ports before adding our port.
sed -ri 's/^([[:space:]]*Port[[:space:]]+[0-9]+.*)$/# \1/' /etc/ssh/sshd_config 2>/dev/null || true
for f in /etc/ssh/sshd_config.d/*.conf; do
  [[ -f "$f" ]] || continue
  sed -ri 's/^([[:space:]]*Port[[:space:]]+[0-9]+.*)$/# \1/' "$f" 2>/dev/null || true
done
install -d -m 755 /etc/ssh/sshd_config.d
cat >/etc/ssh/sshd_config.d/99-grandoptical.conf <<EOF
Port $SSH_PORT
EOF
sshd -t || die "sshd configuration test failed."

if [[ "$UFW_ENABLE" == "on" ]]; then
  ufw --force reset >/dev/null
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow "${SSH_PORT}/tcp"
  ufw allow 80/tcp
  ufw allow 443/tcp
  ufw --force enable >/dev/null
  ok "UFW prepared for SSH $SSH_PORT and web ports."
fi

systemctl reload ssh
ok "SSH configured on port $SSH_PORT"

XUI_INSTALL_URL="https://raw.githubusercontent.com/MHSanaei/3x-ui/${XUI_VERSION}/install.sh"
log "Installing 3x-UI ${XUI_VERSION}..."
XUI_NONINTERACTIVE=1 \
XUI_SSL_MODE=none \
XUI_PANEL_PORT="${XUI_PANEL_PORT}" \
XUI_USERNAME="${XUI_USERNAME}" \
XUI_PASSWORD="${XUI_PASSWORD}" \
XUI_WEB_BASE_PATH="${XUI_WEB_BASE_PATH}" \
bash <(curl -fsSL "$XUI_INSTALL_URL") || die "3x-UI installation failed."

XUI_BIN="/usr/local/x-ui/x-ui"
XUI_DB="/etc/x-ui/x-ui.db"
[[ -x "$XUI_BIN" && -f "$XUI_DB" ]] || die "3x-UI did not install correctly."

PANEL_PORT="$($XUI_BIN setting -show true | awk -F': ' '/^port:/{print $2; exit}' | tr -d '[:space:]')"
WEB_BASE_PATH="$($XUI_BIN setting -show true | awk -F': ' '/^webBasePath:/{print $2; exit}' | tr -d '[:space:]' | sed 's#^/##;s#/$##')"
[[ "$PANEL_PORT" =~ ^[0-9]+$ ]] || die "Could not read 3x-UI panel port."
[[ -n "$WEB_BASE_PATH" ]] || die "Could not read 3x-UI webBasePath."
PANEL_PATH="/${WEB_BASE_PATH}/"

# Certbot uses standalone HTTP-01 here. Renewal hooks stop/start Nginx so port 80
# is available whenever a renewal is actually attempted.
log "Issuing Let's Encrypt certificate for $DOMAIN..."
systemctl stop nginx
if ! certbot certonly --standalone --non-interactive --agree-tos \
    --register-unsafely-without-email --keep-until-expiring -d "$DOMAIN"; then
  systemctl start nginx || true
  die "Certificate issuance failed. Check DNS and port 80."
fi
systemctl start nginx

CERT_DIR="/etc/letsencrypt/live/$DOMAIN"
[[ -s "$CERT_DIR/fullchain.pem" && -s "$CERT_DIR/privkey.pem" ]] || die "Certificate files missing."

mkdir -p /etc/letsencrypt/renewal-hooks/pre /etc/letsencrypt/renewal-hooks/post /etc/letsencrypt/renewal-hooks/deploy
cat >/etc/letsencrypt/renewal-hooks/pre/10-grandoptical-stop-nginx <<'EOF'
#!/usr/bin/env bash
systemctl stop nginx
EOF
cat >/etc/letsencrypt/renewal-hooks/post/10-grandoptical-start-nginx <<'EOF'
#!/usr/bin/env bash
systemctl start nginx
EOF
cat >/etc/letsencrypt/renewal-hooks/deploy/10-grandoptical-reload-nginx <<'EOF'
#!/usr/bin/env bash
systemctl reload nginx
EOF
chmod 755 /etc/letsencrypt/renewal-hooks/pre/10-grandoptical-stop-nginx \
  /etc/letsencrypt/renewal-hooks/post/10-grandoptical-start-nginx \
  /etc/letsencrypt/renewal-hooks/deploy/10-grandoptical-reload-nginx

# Subscription settings used by the reference installation.
sqlite3 "$XUI_DB" <<SQL
INSERT INTO settings(key,value) VALUES
 ('subEnable','true'),
 ('subListen',''),
 ('subPort','2096'),
 ('subPath','/sub/'),
 ('subDomain','$DOMAIN'),
 ('subURI','https://$DOMAIN/2096/sub/')
ON CONFLICT(key) DO UPDATE SET value=excluded.value;
SQL
$XUI_BIN restart >/dev/null 2>&1
sleep 2

# Keep Cloudflare real-IP files available even when CDN enforcement is off.
cat >/etc/nginx/cloudflareips.sh <<'EOF'
#!/usr/bin/env bash
set -e
R=/etc/nginx/conf.d
mkdir -p "$R"
tmp_r=$(mktemp); tmp_w=$(mktemp)
trap 'rm -f "$tmp_r" "$tmp_w"' EXIT
echo 'geo $realip_remote_addr $cloudflare_ip { default 0;' >"$tmp_w"
for t in v4 v6; do
  curl -fsSL --connect-timeout 9 "https://www.cloudflare.com/ips-$t" |
    grep -E '^[0-9a-fA-F:.]+(/[0-9]+)?$' |
    while read -r ip; do
      printf 'set_real_ip_from %s;\n' "$ip" >>"$tmp_r"
      printf '    %s 1;\n' "$ip" >>"$tmp_w"
    done
done
echo 'real_ip_header X-Forwarded-For;' >>"$tmp_r"
echo '}' >>"$tmp_w"
mv -f "$tmp_r" "$R/cloudflare_real_ips.conf"
mv -f "$tmp_w" "$R/cloudflare_whitelist.conf"
EOF
chmod 700 /etc/nginx/cloudflareips.sh
/etc/nginx/cloudflareips.sh

cat >/etc/nginx/nginx.conf <<EOF
user www-data;
worker_processes auto;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;
worker_rlimit_nofile 65535;
events { worker_connections 65535; use epoll; multi_accept on; }
http {
  access_log /var/log/nginx/access.log;
  error_log /var/log/nginx/error.log;
  gzip on;
  sendfile on;
  tcp_nopush on;
  default_type application/octet-stream;
  include /etc/nginx/mime.types;
  include /etc/nginx/conf.d/*.conf;
  include /etc/nginx/sites-enabled/*;
}
EOF

cat >/etc/nginx/sites-available/$DOMAIN <<EOF
server {
  server_tokens off;
  server_name $DOMAIN *.$DOMAIN;
  listen 80;
  listen [::]:80;
  listen 443 ssl http2;
  listen [::]:443 ssl http2;
  root /var/www/html;
  index index.html;
  ssl_protocols TLSv1.2 TLSv1.3;
  ssl_certificate $CERT_DIR/fullchain.pem;
  ssl_certificate_key $CERT_DIR/privkey.pem;

  # 3x-UI panel. WebSocket upgrade headers are required by the reference setup.
  location $PANEL_PATH {
    proxy_redirect off;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_pass http://127.0.0.1:$PANEL_PORT;
  }

  # Subscription Web UI and assets.
  location /sub/ {
    proxy_ssl_verify off;
    proxy_ssl_server_name on;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_pass https://127.0.0.1:2096/sub/;
  }

  # Subscription URL generated by the panel: https://DOMAIN/2096/sub/TOKEN
  location ~ ^/2096/sub/(?<subpath>.*)\$ {
    proxy_ssl_verify off;
    proxy_ssl_server_name on;
    proxy_ssl_name \$host;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_pass https://127.0.0.1:2096/sub/\$subpath\$is_args\$args;
  }

  # Xray protocol paths (XHTTP/WS/gRPC/etc.) are forwarded to local listeners.
  location ~ ^/(?<fwdport>[0-9]+)/(?<fwdpath>.*)\$ {
    client_max_body_size 0;
    client_body_timeout 1d;
    proxy_read_timeout 1d;
    proxy_http_version 1.1;
    proxy_buffering off;
    proxy_request_buffering off;
    proxy_socket_keepalive on;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_pass http://127.0.0.1:\$fwdport\$is_args\$args;
  }

  location / { try_files \$uri \$uri/ =404; }
}
EOF

ln -sfn /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/$DOMAIN
rm -f /etc/nginx/sites-enabled/default /etc/nginx/sites-available/default
nginx -t
systemctl enable --now nginx
systemctl reload nginx
ok "Nginx configured."

cat >/etc/cron.d/grandoptical-xui-backup <<'EOF'
0 2 * * * root mkdir -p /var/backups && cp /etc/x-ui/x-ui.db "/var/backups/x-ui.db.$(date +\%F-\%H-\%M-\%S)" && find /var/backups -name 'x-ui.db.*' -mtime +7 -delete
EOF
chmod 644 /etc/cron.d/grandoptical-xui-backup
systemctl restart cron

a="$($XUI_BIN -v 2>/dev/null || true)"
echo
ok "Installation complete."
echo "Domain:        $DOMAIN"
echo "3x-UI version: ${a}"
echo "Panel port:    $PANEL_PORT"
echo "Panel path:    $PANEL_PATH"
echo "Subscription:  https://$DOMAIN/2096/sub/"
echo "SSH port:      $SSH_PORT"
echo "Timezone:      $(timedatectl show -p Timezone --value)"
echo
warn "Create your XHTTP/VLESS inbounds in 3x-UI after login; the installer does not invent users/inbounds."
