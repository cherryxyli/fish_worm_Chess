#!/usr/bin/env bash
set -e

# ==============================
# PikaFish VPS One-click Deployment
# ==============================

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root or with sudo."
  exit 1
fi

PROJECT_DIR="/home/ubuntu/pika"
DOMAIN="your-domain.com"

mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"

# Detect if project files exist; if not, stop early.
if [ ! -f "index.html" ] || [ ! -f "pikafish_ucci.py" ]; then
  echo "Missing project files in $PROJECT_DIR"
  echo "Please upload index.html, pikafish_ucci.py, and engine files first."
  exit 1
fi

# Install dependencies
apt update
apt install -y python3 python3-venv nginx

# Create Python environment if needed
if [ ! -d ".venv" ]; then
  python3 -m venv .venv
fi

source .venv/bin/activate
pip install --upgrade pip
pip install websockets

# Create start script
cat > "$PROJECT_DIR/start.sh" <<'EOF'
#!/usr/bin/env bash
set -e

cd /home/ubuntu/pika
source .venv/bin/activate

export PIKAFISH_HOST=0.0.0.0
export PIKAFISH_PORT=8888

python pikafish_ucci.py
EOF

# Create frontend serve script
cat > "$PROJECT_DIR/serve.sh" <<'EOF'
#!/usr/bin/env bash
set -e

cd /home/ubuntu/pika
python3 -m http.server 8080
EOF

chmod +x "$PROJECT_DIR/start.sh"
chmod +x "$PROJECT_DIR/serve.sh"

# Create nginx config
cat > /etc/nginx/sites-available/pika <<EOF
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

ln -sf /etc/nginx/sites-available/pika /etc/nginx/sites-enabled/pika
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl restart nginx

echo "========================================================"
echo " VPS deployment setup finished."
echo " Next steps:"
echo " 1) Make sure the engine and NNUE files are in $PROJECT_DIR"
echo " 2) Start the bridge: cd $PROJECT_DIR && ./start.sh"
echo " 3) Start the frontend: cd $PROJECT_DIR && ./serve.sh"
echo " 4) Open http://$DOMAIN or http://SERVER_IP"
echo "========================================================"
