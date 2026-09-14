#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
=============================================================================
  皮卡魚 (Pikafish Native) 本地 WebSocket <-> UCCI 橋接代理服務器
  
  功能：
  1. 通過子進程 stdio 雙向串接本機 pikafish.exe (支援 AVX2 / AVX-512 原生算力)
  2. 監聽 ws://localhost:8888，將網頁前端的分析請求無縫轉發至皮卡魚
  3. 將皮卡魚輸出的百萬級 NPS 遙測 (info depth, score cp, nps, pv) 即時推播回網頁
=============================================================================
"""

import asyncio
import os
import sys
import socket
import subprocess
import json

# 嘗試載入 websockets，若未安裝則提示一鍵安裝指令
try:
    import websockets
except ImportError:
    print("\n[!] 缺少 websockets 庫，請先執行以下指令安裝：")
    print("    pip install websockets\n")
    sys.exit(1)

# 默認皮卡魚本機路徑 (可依個人安裝目錄修改，亦支援透過命令列參數傳入)
DEFAULT_ENGINE_PATH = os.path.join(os.path.dirname(__file__), "pikafish.exe")
PORT = int(os.environ.get("PIKAFISH_PORT", 8888))
HOST = os.environ.get("PIKAFISH_HOST", "localhost")


def find_free_port():
    """尋找可用 TCP 埠號，避免固定 8888 被其他程式占用。"""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind((HOST, 0))
        return sock.getsockname()[1]


def ensure_port_available(port):
    """檢查指定埠是否可被本程式使用，否則拋出明確錯誤。"""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        try:
            sock.bind((HOST, port))
        except OSError as exc:
            raise RuntimeError(
                f"Port {port} 已被其他程式佔用，請關閉該程式或使用其他埠。"
            ) from exc


class PikafishBridge:
    def __init__(self, engine_path):
        self.engine_path = engine_path
        self.process = None
        self.connected_clients = set()

    def start_engine(self):
        """啟動本機皮卡魚原生進程"""
        if not os.path.exists(self.engine_path):
            print(f"[!] 找不到皮卡魚執行檔: {self.engine_path}")
            print("    請將 pikafish.exe 放置於腳本同目錄，或啟動時帶入路徑: python pikafish_bridge.py <路徑>")
            return False

        try:
            print(f"[*] 正在啟動原生皮卡魚引擎: {self.engine_path}")
            self.process = subprocess.Popen(
                [self.engine_path],
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
                encoding="utf-8",
                errors="replace"
            )
            # 發送初始化 UCCI 指令
            self.send_to_engine("ucci")
            self.send_to_engine("isready")
            print("[+] 皮卡魚進程啟動成功！")
            return True
        except Exception as e:
            print(f"[!] 啟動引擎失敗: {e}")
            return False

    def send_to_engine(self, cmd):
        """將指令寫入引擎的 stdin"""
        if self.process and self.process.stdin:
            try:
                self.process.stdin.write(cmd.strip() + "\n")
                self.process.stdin.flush()
            except Exception as e:
                print(f"[!] 發送指令至引擎錯誤: {e}")

    async def engine_stdout_reader(self):
        """異步監聽引擎的 stdout 輸出，並廣播給所有連線的前端網頁"""
        loop = asyncio.get_event_loop()
        while True:
            if not self.process:
                await asyncio.sleep(1)
                continue

            line = await loop.run_in_executor(None, self.process.stdout.readline)
            if not line:
                await asyncio.sleep(0.01)
                continue

            clean_line = line.strip()
            if not clean_line:
                continue

            # 轉發給網頁客戶端
            if self.connected_clients:
                msg = json.dumps({"type": "ENGINE_OUTPUT", "raw": clean_line})
                # 並行發送至所有活躍的 websocket 連線
                await asyncio.gather(
                    *[client.send(msg) for client in self.connected_clients],
                    return_exceptions=True
                )

    async def handle_client(self, websocket):
        """處理網頁前端發來的 WebSocket 請求"""
        self.connected_clients.add(websocket)
        client_addr = websocket.remote_address
        print(f"[+] 網頁前端已連線: {client_addr}")

        # 發送當前引擎連線就緒狀態
        status_msg = json.dumps({
            "type": "STATUS",
            "connected": bool(self.process),
            "enginePath": self.engine_path
        })
        await websocket.send(status_msg)

        try:
            async for message in websocket:
                try:
                    data = json.loads(message)
                    cmd_type = data.get("type")
                    if cmd_type == "COMMAND":
                        cmd = data.get("command", "")
                        self.send_to_engine(cmd)
                    elif cmd_type == "STOP":
                        self.send_to_engine("stop")
                    elif cmd_type == "PING":
                        await websocket.send(json.dumps({"type": "PONG"}))
                except json.JSONDecodeError:
                    # 純文本模式直接作為 UCCI 指令轉發
                    self.send_to_engine(message)
        except websockets.exceptions.ConnectionClosed:
            pass
        finally:
            self.connected_clients.remove(websocket)
            print(f"[-] 網頁前端斷開連線: {client_addr}")

    def stop(self):
        """優雅關閉引擎進程"""
        if self.process:
            try:
                self.send_to_engine("quit")
                self.process.terminate()
            except Exception:
                pass


async def main():
    engine_path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_ENGINE_PATH
    bridge = PikafishBridge(engine_path)

    try:
        ensure_port_available(PORT)
    except RuntimeError as exc:
        print(f"[!] {exc}")
        print(f"    可用方案：關閉佔用 {PORT} 的程式，或啟動時指定其他埠：")
        print(f"    $env:PIKAFISH_PORT=8889")
        print(f"    .\\.venv\\Scripts\\python.exe .\\pikafish_ucci.py")
        sys.exit(1)

    # 嘗試啟動引擎
    engine_ok = bridge.start_engine()
    if not engine_ok:
        print("[!] 引擎啟動失敗，橋接服務器仍將啟動，等待您放置 pikafish.exe 後重連...")

    # 啟動引擎標準輸出讀取任務
    asyncio.create_task(bridge.engine_stdout_reader())

    print(f"\n============================================================")
    print(f"  皮卡魚本地橋接服務已就緒！")
    print(f"  監聽位址: ws://{HOST}:{PORT}")
    print(f"  請在網頁分析系統頂部將【引擎來源】切換為【🚀 本地皮卡魚原版】")
    print(f"============================================================\n")

    try:
        async with websockets.serve(bridge.handle_client, HOST, PORT):
            await asyncio.Future()  # 持續運行
    except OSError as exc:
        print(f"[!] 無法啟動 WebSocket 服務: {exc}")
        print(f"    請確認 {PORT} 埠號沒有被其他程式佔用，或改用 PIKAFISH_PORT 變數。）")
        sys.exit(1)

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\n[*] 正在關閉橋接服務...")
        sys.exit(0)