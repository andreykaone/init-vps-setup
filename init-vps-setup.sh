#!/bin/bash
set -e  # Прерывать выполнение при ошибках

# Разбор аргументов
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--user)
            ENV="$2"
            ;;
        -b|--branch)
            BRANCH="$2"
            ;;
        -f|--force)
            FORCE=true
            ;;
        *)
    esac
done


# Использование параметров
echo "Environment: $ENV"
echo "Branch: $BRANCH"
echo "Force mode: $FORCE"

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
