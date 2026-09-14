# PikaFish VPS 部署說明

這份說明適用於公開部署版本。目標是將前端頁面和原生皮卡魚橋接伺服器部署在 VPS / 雲端主機上，而不是使用本機 localhost。

## 1. 伺服器環境

```bash
sudo apt update
sudo apt install -y python3 python3-venv nginx
```

## 2. 上傳專案檔案

將以下檔案放到伺服器：

- `index.html`
- `pikafish_ucci.py`
- `pikafish.exe`（如果是 Windows 伺服器）
- `pikafish.nnue`
- `start.sh`
- `serve.sh`

如果你是 Linux VPS，請確保有對應的 Linux 版皮卡魚執行檔，而不是 `pikafish.exe`。

## 3. 啟動橋接伺服器

```bash
cd /home/ubuntu/pika
chmod +x start.sh
./start.sh
```

這會將橋接伺服器綁定到：

```text
0.0.0.0:8888
```

## 4. 啟動前端靜態伺服器

```bash
cd /home/ubuntu/pika
chmod +x serve.sh
./serve.sh
```

這會將前端站點提供在：

```text
http://伺服器IP:8080
```

## 5. 配置 nginx

```bash
sudo cp /home/ubuntu/pika/nginx-pika.conf /etc/nginx/sites-available/pika
sudo ln -s /etc/nginx/sites-available/pika /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl restart nginx
```

注意：將 `server_name your-domain.com;` 改成你的真實域名。

## 6. 公開使用 URL

如果你有域名，通常使用：

```text
http://your-domain.com
```

WebSocket 會經由 nginx 轉發到：

```text
wss://your-domain.com/ws
```

## 7. 前端 WebSocket 連線設定

請使用以下邏輯：

```js
const protocol = window.location.protocol === 'https:' ? 'wss' : 'ws';
const host = window.location.hostname || 'localhost';
const isLocal = host === 'localhost' || host === '127.0.0.1' || host === '::1';
const wsUrl = isLocal
    ? `${protocol}://${host}:8888`
    : `${protocol}://${host}/ws`;
```

這樣可以同時支援：

- 本機測試
- VPS / 公網部署
- nginx `/ws` 轉發

## 8. 重要規則

- `localhost` 只能用在本機，不能公開使用。
- `GitHub` 網址不能直接連到本機的皮卡魚。
- `webhook` 不適用於這個需求。
- 需要把引擎放在可公開存取的伺服器上。

## 9. 常見排錯

1. `WebSocket` 連線失敗
   - 檢查 `pikafish_ucci.py` 是否在 8888 埠監聽
   - 檢查 nginx 是否正確轉發 `/ws`
2. 前端載入失敗
   - 檢查 `python3 -m http.server 8080` 是否正在運行
   - 檢查 nginx 是否已啟用站點
3. 引擎啟動失敗
   - 檢查 `pikafish.exe` / Linux 執行檔是否存在
   - 檢查 `.nnue` 檔案是否存在

## 10. 結論

這個架構可讓你在公開網域上使用皮卡魚，而不再依賴 `localhost`。真正的部署核心不是 GitHub，也不是 webhook，而是：

- 公開伺服器
- WebSocket bridge
- nginx 轉發
- 動態連線網址
