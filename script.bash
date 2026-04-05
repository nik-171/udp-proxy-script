#!/bin/bash

echo "=== Hysteria2 UDP Proxy Setup with Firewall and SSH Port Change ==="

# Проверка root
if [ "$EUID" -ne 0 ]; then
  echo "Запусти скрипт от root (sudo)"
  exit 1
fi

# --- Ввод данных ---
read -p "Введи IP backend сервера: " BACKEND_IP

read -p "Введи порт Hysteria2 (по умолчанию 443): " PORT
PORT=${PORT:-443}

read -p "Введи новый порт SSH (по умолчанию 22): " SSH_PORT
SSH_PORT=${SSH_PORT:-22}

# Проверка порта SSH
if ! [[ "$SSH_PORT" =~ ^[0-9]+$ ]] || [ "$SSH_PORT" -lt 1 ] || [ "$SSH_PORT" -gt 65535 ]; then
    echo "Неверное значение порта SSH"
    exit 1
fi

echo ""
echo "Настройка Hysteria2 прокси → $BACKEND_IP:$PORT"
echo "SSH доступ на порт $SSH_PORT"
echo ""

# --- Установка необходимых пакетов ---
apt update -y
DEBIAN_FRONTEND=noninteractive apt install -y iptables-persistent ufw curl openssh-server

# --- Смена порта SSH ---
sed -i "s/^#Port .*/Port $SSH_PORT/" /etc/ssh/sshd_config
sed -i "s/^Port .*/Port $SSH_PORT/" /etc/ssh/sshd_config

systemctl daemon-reload
systemctl restart ssh

echo "Порт SSH изменён на: $SSH_PORT"

# --- Настройка ip_forward для NAT ---
echo 1 > /proc/sys/net/ipv4/ip_forward
if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
  echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
fi
sysctl -p

# --- Очистка старых правил iptables ---
iptables -F
iptables -t nat -F
iptables -X

# --- Базовая политика ---
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# --- Разрешаем loopback ---
iptables -A INPUT -i lo -j ACCEPT

# --- Разрешаем уже установленные соединения ---
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# --- Разрешаем SSH ---
iptables -A INPUT -p tcp --dport $SSH_PORT -j ACCEPT

# --- DNAT и FORWARD для Hysteria2 ---
iptables -t nat -A PREROUTING -p udp --dport $PORT -j DNAT --to-destination $BACKEND_IP:$PORT
iptables -t nat -A POSTROUTING -p udp -d $BACKEND_IP --dport $PORT -j MASQUERADE
iptables -A FORWARD -p udp -d $BACKEND_IP --dport $PORT -j ACCEPT
iptables -A FORWARD -p udp -s $BACKEND_IP --sport $PORT -j ACCEPT

# --- Отключаем пинг (ICMP Echo Request) ---
iptables -A INPUT -p icmp --icmp-type echo-request -j DROP

# --- Сохраняем правила ---
netfilter-persistent save

# --- Настройка UFW (для контроля и безопасности) ---
ufw allow $SSH_PORT/tcp
ufw allow $PORT/udp
ufw default deny incoming
ufw default allow outgoing
ufw disable && ufw enable

echo ""
echo "Готово! Прокси работает."
echo "Подключайся к IP этого сервера на порт $PORT (Hysteria2) и $SSH_PORT (SSH)"
ufw status numbered