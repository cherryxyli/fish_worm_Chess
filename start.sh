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
