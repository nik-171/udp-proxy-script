#!/bin/bash

echo "=== Hysteria2 UDP Proxy Setup with Firewall ==="

# Проверка root
if [ "$EUID" -ne 0 ]; then
  echo "Запусти скрипт от root (sudo)"
  exit 1
fi

# Ввод данных
read -p "Введи IP backend сервера: " BACKEND_IP
read -p "Введи порт Hysteria2 (по умолчанию 443): " PORT
PORT=${PORT:-443}

read -p "Введи порт SSH (по умолчанию 22): " SSH_PORT
SSH_PORT=${SSH_PORT:-22}

echo ""
echo "Настройка прокси → $BACKEND_IP:$PORT"
echo "SSH доступ на порт $SSH_PORT"
echo ""

# Устанавливаем iptables-persistent (для сохранения правил)
apt update
DEBIAN_FRONTEND=noninteractive apt install -y iptables-persistent

# Включаем форвардинг
echo 1 > /proc/sys/net/ipv4/ip_forward
if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
  echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
fi
sysctl -p

# Очищаем старые правила
iptables -F
iptables -t nat -F
iptables -X

# --- Базовый DROP policy ---
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# --- Разрешаем loopback ---
iptables -A INPUT -i lo -j ACCEPT

# --- Разрешаем уже установленные соединения ---
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# --- Разрешаем SSH ---
iptables -A INPUT -p tcp --dport $SSH_PORT -j ACCEPT

# --- DNAT: перенаправление Hysteria2 ---
iptables -t nat -A PREROUTING -p udp --dport $PORT -j DNAT --to-destination $BACKEND_IP:$PORT
iptables -t nat -A POSTROUTING -p udp -d $BACKEND_IP --dport $PORT -j MASQUERADE

# --- FORWARD для Hysteria2 ---
iptables -A FORWARD -p udp -d $BACKEND_IP --dport $PORT -j ACCEPT
iptables -A FORWARD -p udp -s $BACKEND_IP --sport $PORT -j ACCEPT

# --- Ограничиваем все остальные входящие UDP/TCP ---
# INPUT policy уже DROP, поэтому лишние порты заблокированы автоматически

# Сохраняем правила
netfilter-persistent save

echo ""
echo "Готово! Прокси работает."
echo "Подключайся к IP этого сервера на порт $PORT (Hysteria2) и $SSH_PORT (SSH)"