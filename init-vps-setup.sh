#!/bin/bash

# Скрипт для начальной настройки VPS (Ubuntu/Debian)
# Включает: Безопасность, Swap, Timezone, UFW, Fail2Ban, Docker

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

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
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Очистка экрана для аккуратности
clear
echo -e "${GREEN}=== VPS Initial Setup Script (Safe Mode) ===${NC}"
echo -e "Этот скрипт сначала соберет все настройки, подтвердит их, и только затем применит."
echo ""

# --- ФАЗА 1: СБОР ИНФОРМАЦИИ ---

echo -e "${CYAN}--- 1. Пользователь и Доступ ---${NC}"
read -p "Введите имя нового пользователя: " USERNAME
while [[ -z "$USERNAME" ]]; do
    echo -e "${RED}Имя пользователя не может быть пустым!${NC}"
    read -p "Введите имя нового пользователя: " USERNAME
done

read -p "Введите желаемый SSH порт [2222]: " SSH_PORT
SSH_PORT=${SSH_PORT:-2222}

read -p "Введите Hostname сервера [$(hostname)]: " NEW_HOSTNAME
NEW_HOSTNAME=${NEW_HOSTNAME:-$(hostname)}

echo -e "\n${CYAN}--- 2. Система ---${NC}"
read -p "Введите Timezone [Europe/Moscow]: " TIMEZONE
TIMEZONE=${TIMEZONE:-Europe/Moscow}

DO_SWAP=false
SWAP_SIZE_GB=0
if confirm "Настроить Swap (файл подкачки)?"; then
    DO_SWAP=true
    read -p "Размер Swap в ГБ [2]: " SWAP_SIZE_GB
    SWAP_SIZE_GB=${SWAP_SIZE_GB:-2}
fi

echo -e "\n${CYAN}--- 3. Безопасность и Компоненты ---${NC}"

DO_SSH_HARDENING=false
SSH_KEY=""
if confirm "Усилить безопасность SSH (запрет root, вход только по ключу)?"; then
    DO_SSH_HARDENING=true
    echo -e "${YELLOW}Вставьте ваш PUBLIC SSH KEY (начинается на ssh-rsa или ed25519):${NC}"
    # Используем read -r для сохранения бэкслешей если они есть, хотя в ключах обычно нет
    read -r SSH_KEY
    while [[ -z "$SSH_KEY" ]]; do
        echo -e "${RED}SSH ключ обязателен для отключения входа по паролю!${NC}"
        echo -e "Если вы передумали, нажмите Ctrl+C для выхода и начните заново."
        read -r SSH_KEY
    done
fi

DO_UFW=false
if confirm "Настроить Firewall (UFW) (открыты только SSH, 80, 443)?"; then
    DO_UFW=true
fi

DO_FAIL2BAN=false
if confirm "Установить и настроить Fail2Ban?"; then
    DO_FAIL2BAN=true
fi

DO_UNATTENDED_UPDATES=false
if confirm "Включить автоматические обновления безопасности?"; then
    DO_UNATTENDED_UPDATES=true
fi

DO_DOCKER=false
if confirm "Установить Docker и Docker Compose?"; then
    DO_DOCKER=true
fi

# --- ФАЗА 2: ПОДТВЕРЖДЕНИЕ ---

clear
echo -e "${GREEN}=== ПРОВЕРКА КОНФИГУРАЦИИ ===${NC}"
echo -e "Пользователь:       ${YELLOW}$USERNAME${NC}"
echo -e "Hostname:           ${YELLOW}$NEW_HOSTNAME${NC}"
echo -e "SSH Порт:           ${YELLOW}$SSH_PORT${NC}"
echo -e "Timezone:           ${YELLOW}$TIMEZONE${NC}"
echo -e "Swap:               ${YELLOW}$( [ "$DO_SWAP" = true ] && echo "${SWAP_SIZE_GB}GB" || echo "Нет" )${NC}"
echo -e "Hardened SSH:       ${YELLOW}$( [ "$DO_SSH_HARDENING" = true ] && echo "Да (Key provided)" || echo "Нет" )${NC}"
echo -e "Firewall (UFW):     ${YELLOW}$( [ "$DO_UFW" = true ] && echo "Да" || echo "Нет" )${NC}"
echo -e "Fail2Ban:           ${YELLOW}$( [ "$DO_FAIL2BAN" = true ] && echo "Да" || echo "Нет" )${NC}"
echo -e "Auto Updates:       ${YELLOW}$( [ "$DO_UNATTENDED_UPDATES" = true ] && echo "Да" || echo "Нет" )${NC}"
echo -e "Docker:             ${YELLOW}$( [ "$DO_DOCKER" = true ] && echo "Да" || echo "Нет" )${NC}"

echo ""
if ! confirm "Всё верно? Начать установку?"; then
    echo -e "${RED}Отмена операции. Изменения не внесены.${NC}"
    exit 0
fi

# --- ФАЗА 3: ВЫПОЛНЕНИЕ ---

echo -e "\n${GREEN}=== НАЧАЛО УСТАНОВКИ ===${NC}"

# 1. Обновление системы
echo -e "\n${YELLOW}>>> 1. Обновление системы...${NC}"
apt update && apt upgrade -y
apt install -y curl git sudo tzdata htop

# 2. Настройка Hostname
echo -e "\n${YELLOW}>>> 2. Настройка Hostname ($NEW_HOSTNAME)...${NC}"
hostnamectl set-hostname "$NEW_HOSTNAME"
if ! grep -q "$NEW_HOSTNAME" /etc/hosts; then
    echo "127.0.0.1 $NEW_HOSTNAME" >> /etc/hosts
fi

# 3. Настройка Timezone
echo -e "\n${YELLOW}>>> 3. Настройка Timezone ($TIMEZONE)...${NC}"
ln -sf /usr/share/zoneinfo/"$TIMEZONE" /etc/localtime
dpkg-reconfigure -f noninteractive tzdata

# 4. Создание пользователя
echo -e "\n${YELLOW}>>> 4. Создание пользователя $USERNAME...${NC}"
if id "$USERNAME" >/dev/null 2>&1; then
    echo "Пользователь $USERNAME уже существует"
else
    adduser --gecos "" "$USERNAME"
    usermod -aG sudo "$USERNAME"
    echo -e "${GREEN}Пользователь $USERNAME создан${NC}"
fi

# 5. Swap
if [ "$DO_SWAP" = true ]; then
    echo -e "\n${YELLOW}>>> 5. Настройка Swap ($SWAP_SIZE_GB GB)...${NC}"
    if [ -f /swapfile ]; then
        echo "Swap файл уже существует, пропускаем."
    else
        fallocate -l "${SWAP_SIZE_GB}G" /swapfile
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
        echo -e "${GREEN}Swap активирован${NC}"
    fi
fi

# 6. SSH Hardening
if [ "$DO_SSH_HARDENING" = true ]; then
    echo -e "\n${YELLOW}>>> 6. Настройка безопасности SSH...${NC}"
    mkdir -p "/home/$USERNAME/.ssh"
    chmod 700 "/home/$USERNAME/.ssh"
    
    echo "$SSH_KEY" > "/home/$USERNAME/.ssh/authorized_keys"
    chmod 600 "/home/$USERNAME/.ssh/authorized_keys"
    chown -R "$USERNAME:$USERNAME" "/home/$USERNAME/.ssh"

    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

    # Используем sed для замены параметров. Обрабатываем и дефолтный 22 и уже измененный порт.
    sed -i "s/^#\?Port .*/Port $SSH_PORT/" /etc/ssh/sshd_config
    sed -i "s/^#\?PermitRootLogin .*/PermitRootLogin no/" /etc/ssh/sshd_config
    sed -i "s/^#\?PasswordAuthentication .*/PasswordAuthentication no/" /etc/ssh/sshd_config
    
    # Проверка синтаксиса SSH конфига перед рестартом
    if sshd -t; then
        systemctl restart ssh
        echo -e "${GREEN}SSH настроен. Порт: $SSH_PORT${NC}"
    else
        echo -e "${RED}Ошибка в конфигурации SSH! Изменения не применены.${NC}"
    fi
fi

# 7. UFW
if [ "$DO_UFW" = true ]; then
    echo -e "\n${YELLOW}>>> 7. Настройка UFW...${NC}"
    apt install -y ufw
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow "$SSH_PORT"/tcp
    ufw allow 80/tcp
    ufw allow 443/tcp
    # Force enable without prompt
    echo "y" | ufw enable
    echo -e "${GREEN}UFW включен${NC}"
fi

# 8. Fail2Ban
if [ "$DO_FAIL2BAN" = true ]; then
    echo -e "\n${YELLOW}>>> 8. Настройка Fail2Ban...${NC}"
    apt install -y fail2ban
    cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
backend = systemd
bantime  = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true
port    = $SSH_PORT
EOF
    systemctl enable fail2ban
    systemctl restart fail2ban
    echo -e "${GREEN}Fail2Ban настроен${NC}"
fi

# 9. Unattended Upgrades
if [ "$DO_UNATTENDED_UPDATES" = true ]; then
    echo -e "\n${YELLOW}>>> 9. Настройка автообновлений...${NC}"
    apt install -y unattended-upgrades
    dpkg-reconfigure -f noninteractive unattended-upgrades
    echo -e "${GREEN}Автообновления включены${NC}"
fi

# 10. Docker
if [ "$DO_DOCKER" = true ]; then
    echo -e "\n${YELLOW}>>> 10. Установка Docker...${NC}"
    if command -v docker >/dev/null 2>&1; then
        echo "Docker уже установлен"
    else
        curl -fsSL https://get.docker.com -o get-docker.sh
        sh get-docker.sh
        rm get-docker.sh
        usermod -aG docker "$USERNAME"
        echo -e "${GREEN}Docker установлен${NC}"
    fi
fi

# 11. Очистка
echo -e "\n${YELLOW}>>> 11. Очистка системы...${NC}"
apt-get autoremove -y
apt-get autoclean -y

echo -e "\n${GREEN}=== ГОТОВО! ===${NC}"
echo -e "Для подключения используйте команду:"
echo -e "${YELLOW}ssh -p $SSH_PORT $USERNAME@$(curl -s https://ifconfig.me)${NC}"
echo -e "${RED}ВАЖНО: Проверьте подключение в новом окне терминала ПЕРЕД закрытием этой сессии!${NC}"

if confirm "Перезагрузить сервер сейчас?"; then
    reboot
fi
