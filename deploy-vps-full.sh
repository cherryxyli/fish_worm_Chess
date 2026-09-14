#!/usr/bin/env bash
set -e

# ================================================
# PikaFish Full VPS Deployment Script
# ================================================
# This script prepares a public deployment environment
# for the local engine + web frontend.
#
# Usage:
#   sudo bash deploy-vps-full.sh
#
# Before running:
#   - upload project files to /home/ubuntu/pika
#   - ensure your domain is already pointing to this server
# ================================================

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root or with sudo."
  exit 1
fi

PROJECT_DIR="/home/ubuntu/pika"
DOMAIN="your-domain.com"

mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"

if [ ! -f "index.html" ] || [ ! -f "pikafish_ucci.py" ]; then
  echo "Missing project files in $PROJECT_DIR"
  echo "Required files: index.html, pikafish_ucci.py"
  exit 1
fi

ENGINE_CANDIDATES=(
  "$PROJECT_DIR/pikafish.exe"
  "$PROJECT_DIR/pikafish"
  "$PROJECT_DIR/pikafish-linux"
  "$PROJECT_DIR/pikafish_x64"
)

ENGINE_FOUND=""
for candidate in "${ENGINE_CANDIDATES[@]}"; do
  if [ -f "$candidate" ]; then
    ENGINE_FOUND="$candidate"
    break
  fi
done

if [ -z "$ENGINE_FOUND" ]; then
  echo "No engine binary found. Please upload a compatible Pikafish engine to $PROJECT_DIR"
  echo "Tried: ${ENGINE_CANDIDATES[*]}"
  exit 1
fi

if [ ! -f "$PROJECT_DIR/pikafish.nnue" ]; then
  echo "Missing pikafish.nnue in $PROJECT_DIR"
  exit 1
fi

apt update
apt install -y python3 python3-venv nginx certbot python3-certbot-nginx

if [ ! -d "$PROJECT_DIR/.venv" ]; then
  python3 -m venv "$PROJECT_DIR/.venv"
fi

source "$PROJECT_DIR/.venv/bin/activate"
pip install --upgrade pip
pip install websockets

cat > "$PROJECT_DIR/start.sh" <<'EOF'
#!/usr/bin/env bash
set -e

cd /home/ubuntu/pika
source .venv/bin/activate

export PIKAFISH_HOST=0.0.0.0
export PIKAFISH_PORT=8888

python pikafish_ucci.py
EOF

cat > "$PROJECT_DIR/serve.sh" <<'EOF'
#!/usr/bin/env bash
set -e

cd /home/ubuntu/pika
python3 -m http.server 8080
EOF

chmod +x "$PROJECT_DIR/start.sh"
chmod +x "$PROJECT_DIR/serve.sh"

cat > "$PROJECT_DIR/nginx-pika.conf" <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    root $PROJECT_DIR;
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location /ws {
        proxy_pass http://127.0.0.1:8888;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_read_timeout 600s;
    }
}
EOF

ln -sf "$PROJECT_DIR/nginx-pika.conf" /etc/nginx/sites-available/pika
ln -sf /etc/nginx/sites-available/pika /etc/nginx/sites-enabled/pika
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl restart nginx

# Generate production-safe frontend WebSocket config
cat > "$PROJECT_DIR/index.html" <<'EOF'
<!DOCTYPE html>
<html lang="zh-TW">
<head>
    <meta charset="UTF-8">
    <meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>皮卡魚·棋境 - 中國象棋專業級 AI 深度分析引擎</title>
    <link rel="stylesheet" href="./tailwind.css">
</head>
<body class="bg-slate-950 text-slate-100 min-h-screen">
    <script>
        const protocol = window.location.protocol === 'https:' ? 'wss' : 'ws';
        const host = window.location.hostname || 'localhost';
        const isLocal = host === 'localhost' || host === '127.0.0.1' || host === '::1';
        const wsUrl = isLocal
            ? `${protocol}://${host}:8888`
            : `${protocol}://${host}/ws`;

        console.log('Connecting to:', wsUrl);
        const socket = new WebSocket(wsUrl);

        socket.onopen = () => {
            console.log('Connected');
        };

        socket.onmessage = (event) => {
            console.log('Received:', event.data);
        };

        socket.onclose = () => {
            console.log('Closed');
        };

        socket.onerror = () => {
            console.log('Connection error');
        };
    </script>
</body>
</html>
EOF

cat > "$PROJECT_DIR/README.md" <<EOF
# PikaFish Public Deployment Guide

This project is designed for public deployment on a VPS or cloud server.

## Features

- frontend served over HTTP
- WebSocket bridge to the native engine
- public host / domain compatible configuration
- nginx reverse proxy for `/ws`

## Required files

Make sure the following files exist in the project directory:

- `index.html`
- `pikafish_ucci.py`
- `pikafish.nnue`
- engine binary matching your OS

## Deploy on VPS

### 1) Upload files to the project directory

```bash
cd /home/ubuntu/pika
```

### 2) Start the bridge

```bash
cd /home/ubuntu/pika
./start.sh
```

### 3) Start the frontend service

```bash
cd /home/ubuntu/pika
./serve.sh
```

### 4) Access the app

```text
http://$DOMAIN
```

The frontend uses:

```text
wss://$DOMAIN/ws
```

or

```text
ws://localhost:8888
```

for local development.

## Notes

- `localhost` is only for local use.
- GitHub pages cannot directly access a local engine on your machine.
- This deployment uses a server-side engine bridge, not a webhook-based approach.

## Troubleshooting

- If WebSocket fails, check whether `pikafish_ucci.py` is running.
- If nginx fails, run `sudo nginx -t`.
- If the engine fails to start, verify the engine binary exists and is compatible with the OS.
EOF

# Optional TLS setup with certbot
if [ -n "$DOMAIN" ] && [ "$DOMAIN" != "your-domain.com" ]; then
  certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m admin@$DOMAIN || true
fi

cat <<EOF
========================================================
Deployment finished.

Files created:
- $PROJECT_DIR/start.sh
- $PROJECT_DIR/serve.sh
- $PROJECT_DIR/nginx-pika.conf
- $PROJECT_DIR/README.md

Important:
- Replace 'your-domain.com' in the config with your real domain.
- Start the bridge: cd $PROJECT_DIR && ./start.sh
- Start the frontend: cd $PROJECT_DIR && ./serve.sh
- Open: http://$DOMAIN or https://$DOMAIN

Engine detected at: $ENGINE_FOUND
========================================================
EOF
