#!/bin/bash

# Скрипт для начальной настройки VPS (Ubuntu/Debian)
# Включает: Безопасность, Swap, Timezone, UFW, Fail2Ban

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== VPS Initial Setup Script ===${NC}"

# Проверка прав root
if [ "$EUID" -ne 0 ]; then 
  echo -e "${RED}Пожалуйста, запускайте скрипт из-под пользователя root${NC}"
  exit 1
fi

# Функция для интерактивного вопроса (Y/n)
confirm() {
    read -p "$1 [Y/n]: " response
    case "$response" in
        [yY][eE][sS]|[yY]|"") 
            true
            ;;
        *)
            false
            ;;
    esac
}

# 1. Основные параметры
echo -e "\n${YELLOW}--- 1. Базовые настройки ---${NC}"
read -p "Введите имя нового пользователя: " USERNAME
read -p "Введите желаемый SSH порт (например, 2222): " SSH_PORT
read -p "Введите Hostname сервера (например, my-vps): " NEW_HOSTNAME
read -p "Введите Timezone (например, Europe/Moscow): " TIMEZONE
read -p "Размер Swap в ГБ (например, 2): " SWAP_SIZE_GB

# 2. Обновление системы и установка базового ПО
echo -e "\n${YELLOW}--- 2. Обновление системы и установка ПО ---${NC}"
apt update && apt upgrade -y
apt install -y curl git ufw fail2ban unattended-upgrades sudo tzdata htop

# 3. Настройка Hostname
echo -e "\n${YELLOW}--- 3. Настройка Hostname ---${NC}"
hostnamectl set-hostname $NEW_HOSTNAME
echo "127.0.0.1 localhost $NEW_HOSTNAME" >> /etc/hosts

# 4. Создание пользователя и sudo
echo -e "\n${YELLOW}--- 4. Создание пользователя ---${NC}"
if id "$USERNAME" >/dev/null 2>&1; then
    echo "Пользователь $USERNAME уже существует"
else
    adduser --gecos "" $USERNAME
    usermod -aG sudo $USERNAME
    echo -e "${GREEN}Пользователь $USERNAME создан и добавлен в sudo${NC}"
fi

# 5. Настройка Swap
if confirm "Создать Swap файл ($SWAP_SIZE_GB ГБ)?"; then
    fallocate -l ${SWAP_SIZE_GB}G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
    echo -e "${GREEN}Swap файл создан${NC}"
fi

# 6. Настройка Timezone
echo -e "\n${YELLOW}--- 6. Настройка времени ---${NC}"
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
dpkg-reconfigure -f noninteractive tzdata

# 7. Безопасность SSH
echo -e "\n${YELLOW}--- 7. Настройка SSH безопасности ---${NC}"
if confirm "Настроить SSH (смена порта, запрет паролей, запрет root)?"; then
    # Подготовка директории .ssh для пользователя
    mkdir -p /home/$USERNAME/.ssh
    chmod 700 /home/$USERNAME/.ssh
    
    echo -e "${YELLOW}ВАЖНО: Вставьте ваш PUBLIC SSH KEY (начинается на ssh-rsa или ed25519):${NC}"
    read SSH_KEY
    echo "$SSH_KEY" > /home/$USERNAME/.ssh/authorized_keys
    chmod 600 /home/$USERNAME/.ssh/authorized_keys
    chown -R $USERNAME:$USERNAME /home/$USERNAME/.ssh

    # Бэкап конфига
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

    # Модификация sshd_config
    sed -i "s/#Port 22/Port $SSH_PORT/" /etc/ssh/sshd_config
    sed -i "s/PermitRootLogin yes/PermitRootLogin no/" /etc/ssh/sshd_config
    sed -i "s/#PermitRootLogin prohibit-password/PermitRootLogin no/" /etc/ssh/sshd_config
    sed -i "s/PasswordAuthentication yes/PasswordAuthentication no/" /etc/ssh/sshd_config
    sed -i "s/#PasswordAuthentication no/PasswordAuthentication no/" /etc/ssh/sshd_config
    
    systemctl restart ssh
    echo -e "${GREEN}SSH настроен и перезапущен. Порт: $SSH_PORT. Вход по паролю запрещен.${NC}"
fi

# 8. Настройка UFW
if confirm "Настроить Firewall (UFW)?"; then
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow $SSH_PORT/tcp
    ufw allow 80/tcp
    ufw allow 443/tcp
    echo "y" | ufw enable
    echo -e "${GREEN}Firewall включен. Разрешены порты: $SSH_PORT, 80, 443${NC}"
fi

# 9. Настройка Fail2Ban
if confirm "Настроить Fail2Ban (базовая защита от брутфорса)?"; then
    cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
# Использовать systemd для чтения логов (решает проблему отсутствия /var/log/auth.log)
backend = systemd
# Время бана
bantime  = 1h
# Окно поиска попыток
findtime = 10m
# Количество попыток до бана
maxretry = 5

[sshd]
enabled = true
port    = $SSH_PORT
EOF
    systemctl enable fail2ban
    systemctl restart fail2ban
    echo -e "${GREEN}Fail2Ban настроен и запущен (используется backend systemd)${NC}"
fi

# 10. Unattended Upgrades
if confirm "Включить автоматические обновления безопасности?"; then
    dpkg-reconfigure -f noninteractive unattended-upgrades
    echo -e "${GREEN}Автоматические обновления включены${NC}"
fi

# 11. Установка Docker
echo -e "\n${YELLOW}--- 11. Установка Docker & Docker Compose ---${NC}"
if confirm "Установить Docker и Docker Compose (через get.docker.com)?"; then
    echo "Скачивание и запуск официального скрипта установки..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh
    
    # Добавление пользователя в группу docker
    usermod -aG docker $USERNAME
    
    echo -e "${GREEN}Docker установлен. Пользователь $USERNAME добавлен в группу docker.${NC}"
fi

# 12. Очистка системы
echo -e "\n${YELLOW}--- 12. Очистка системы ---${NC}"
apt-get autoremove -y
apt-get autoclean -y
echo -e "${GREEN}Кэш пакетов очищен, неиспользуемые зависимости удалены${NC}"

if confirm "Настройка завершена. Рекомендуется перезагрузить сервер. Сделать это сейчас?"; then
    reboot
fi

echo -e "\n${GREEN}=== Настройка завершена! ===${NC}"
echo -e "Теперь вы можете подключиться: ${YELLOW}ssh -p $SSH_PORT $USERNAME@$(curl -s https://ifconfig.me)${NC}"
echo -e "${RED}НЕ ЗАКРЫВАЙТЕ ТЕКУЩУЮ СЕССИЮ, пока не проверите доступ в новом окне терминала!${NC}"
