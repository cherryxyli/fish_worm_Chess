# PikaFish VPS Deployment Guide

A public deployment version of the local Pikafish chess analysis project.

This project uses:

- a static frontend served by nginx / Python HTTP server
- a WebSocket bridge that connects the browser to the native engine
- a public host or domain instead of `localhost`

This is designed for deployment to a VPS or cloud server, not for direct GitHub Pages access to a local engine.

## Architecture

```text
Browser
  |
  +--> https://your-domain.com
            |
            v
        VPS / Server
            |
            +--> Frontend (index.html)
            |
            +--> WebSocket bridge (pikafish_ucci.py)
            |
            +--> Native engine (pikafish)
```

## Requirements

- Ubuntu/Debian VPS or equivalent Linux host
- Python 3
- nginx
- access to a valid domain or public IP
- a native Pikafish engine binary compatible with the target OS

## Project Files

- `index.html` — frontend UI
- `pikafish_ucci.py` — WebSocket bridge to engine
- `pikafish.exe` or Linux engine binary — native engine
- `pikafish.nnue` — engine NNUE file
- `start.sh` — runs the bridge server
- `serve.sh` — serves the frontend via Python HTTP server
- `nginx-pika.conf` — nginx config for public deployment

## 1) Install Server Dependencies

```bash
sudo apt update
sudo apt install -y python3 python3-venv nginx
```

## 2) Prepare the Project on the VPS

Upload the project files to `/home/ubuntu/pika`.

Example structure:

```text
/home/ubuntu/pika/
├── index.html
├── pikafish_ucci.py
├── pikafish.nnue
├── pikafish.exe      # or Linux engine binary
├── start.sh
├── serve.sh
├── nginx-pika.conf
└── .venv/
```

## 3) Create the Python Environment

```bash
cd /home/ubuntu/pika
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install websockets
```

## 4) Start the WebSocket Bridge

```bash
cd /home/ubuntu/pika
source .venv/bin/activate
export PIKAFISH_HOST=0.0.0.0
export PIKAFISH_PORT=8888
python pikafish_ucci.py
```

This binds the engine bridge to:

```text
ws://0.0.0.0:8888
```

## 5) Start the Frontend Server

```bash
cd /home/ubuntu/pika
python3 -m http.server 8080
```

Then the frontend is available at:

```text
http://SERVER_IP:8080
```

## 6) Configure nginx

Create the nginx site config:

```bash
sudo nano /etc/nginx/sites-available/pika
```

Paste:

```nginx
server {
    listen 80;
    server_name your-domain.com;

    root /home/ubuntu/pika;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }

    location /ws {
        proxy_pass http://127.0.0.1:8888;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 600s;
    }
}
```

Enable the site:

```bash
sudo ln -s /etc/nginx/sites-available/pika /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl restart nginx
```

Then update `server_name` to your actual domain.

## 7) Frontend WebSocket Connection Logic

Use this pattern in the frontend:

```js
const protocol = window.location.protocol === 'https:' ? 'wss' : 'ws';
const host = window.location.hostname || 'localhost';
const isLocal = host === 'localhost' || host === '127.0.0.1' || host === '::1';
const wsUrl = isLocal
    ? `${protocol}://${host}:8888`
    : `${protocol}://${host}/ws`;
```

This works for:

- local testing via `localhost`
- VPS/public deployment via a domain or IP
- nginx `/ws` proxy forwarding

## 8) Start Script

Create `/home/ubuntu/pika/start.sh`:

```bash
#!/usr/bin/env bash
set -e

cd /home/ubuntu/pika

if [ ! -d ".venv" ]; then
  python3 -m venv .venv
fi

source .venv/bin/activate

pip install --upgrade pip
pip install websockets

export PIKAFISH_HOST=0.0.0.0
export PIKAFISH_PORT=8888

python pikafish_ucci.py
```

Run:

```bash
chmod +x /home/ubuntu/pika/start.sh
./start.sh
```

## 9) Serve Script

Create `/home/ubuntu/pika/serve.sh`:

```bash
#!/usr/bin/env bash
set -e

cd /home/ubuntu/pika
python3 -m http.server 8080
```

Run:

```bash
chmod +x /home/ubuntu/pika/serve.sh
./serve.sh
```

## 10) Public Access

After deployment, use:

```text
http://your-domain.com
```

The browser will connect to:

```text
wss://your-domain.com/ws
```

which nginx forwards to the Python bridge on port 8888.

## 11) Important Notes

- `localhost` only works on the same machine.
- GitHub pages cannot directly access a local engine running on your personal machine.
- `webhook` is not the right tool for this problem.
- The engine must be deployed on a public or accessible server if you want public online access.

## 12) Troubleshooting

### WebSocket connection fails
- check whether `pikafish_ucci.py` is running and listening on port 8888
- verify nginx proxy rules are active
- check firewall rules for 80/443/8888

### Frontend does not load
- ensure the static server is running on 8080
- verify nginx is serving the correct folder

### Engine startup fails
- ensure the engine binary exists
- ensure the NNUE file exists
- confirm the OS is compatible with the engine binary

## 13) Summary

This deployment model is the correct public-access version of the project:

- static frontend on a public server
- WebSocket bridge on a public server
- native engine runs on the same machine as the bridge
- public URL points to the host, not to localhost

This is the correct architecture for B-mode deployment.
