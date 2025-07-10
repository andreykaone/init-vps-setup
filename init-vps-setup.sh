#!/bin/bash
set -e  # Прерывать выполнение при ошибках


# Проверка прав root
if [ "$EUID" -ne 0 ]; then 
  echo "Please run as root"
  exit 1
fi


# Обновление системы
apt update && apt full-upgrade -y
apt install -y ufw fail2ban unattended-upgrades

# Создание пользователя
if id "$1" >/dev/null 2>&1; then
    echo "user " $USERNAME " already exists"
else
    adduser --disabled-password --gecos "" $USERNAME
    usermod -aG sudo $USERNAME
    echo "user " $USERNAME " created"
fi