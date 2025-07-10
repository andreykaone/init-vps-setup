#!/bin/bash
set -e  # Прерывать выполнение при ошибках


# Проверка прав root
if [ "$EUID" -ne 0 ]; then 
  echo "Please run as root"
  exit 1
fi

# Проверка наличия публичного ключа
if [ -z "$1" ] || [ ! -f "$1" ]; then
  echo "Usage: $0 /path/to/your/public_key.pub"
  echo "Example: ./server-secure-init.sh ~/.ssh/id_ed25519.pub"
  exit 1
fi

# Основные переменные
PUB_KEY_PATH="$1"
USERNAME="deploy"
SSH_PORT=22222


echo "=== Starting security setup with key: $PUB_KEY_PATH ==="


# Обновление системы
apt update && apt full-upgrade -y
apt install -y ufw fail2ban unattended-upgrades

# Создание пользователя
adduser --disabled-password --gecos "" $USERNAME
usermod -aG sudo $USERNAME

# Настройка SSH
mkdir -p /home/$USERNAME/.ssh
curl -sSf $PUB_KEY_URL > /home/$USERNAME/.ssh/authorized_keys
chown -R $USERNAME:$USERNAME /home/$USERNAME/.ssh
chmod 700 /home/$USERNAME/.ssh
chmod 600 /home/$USERNAME/.ssh/authorized_keys


# Бэкап и настройка SSH
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

sed -i "s/#Port 22/Port $SSH_PORT/" /etc/ssh/sshd_config
sed -i "s/PermitRootLogin yes/PermitRootLogin no/" /etc/ssh/sshd_config
sed -i "s/#PasswordAuthentication yes/PasswordAuthentication no/" /etc/ssh/sshd_config
echo "AllowUsers $USERNAME" >> /etc/ssh/sshd_config
systemctl restart sshd


# Настройка UFW
ufw default deny incoming
ufw default allow outgoing
ufw allow $SSH_PORT
ufw --force enable

# Настройка Fail2Ban
cat <<EOL > /etc/fail2ban/jail.d/sshd.local
[sshd]
enabled = true
port = $SSH_PORT
maxretry = 3
EOL
systemctl restart fail2ban

# Автообновления
echo 'Unattended-Upgrade::Automatic-Reboot "true";' > /etc/apt/apt.conf.d/50unattended-upgrades
dpkg-reconfigure -f noninteractive unattended-upgrades

# Оптимизация сетевых параметров
cat <<EOL >> /etc/sysctl.conf
net.ipv4.tcp_syncookies=1
net.ipv4.tcp_synack_retries=2
net.ipv4.tcp_max_syn_backlog=2048
net.ipv4.tcp_rfc1337=1
EOL
sysctl -p

echo "=== Setup complete! ==="
echo "- SSH port changed to: $SSH_PORT"
echo "- Login with: ssh -p $SSH_PORT $USERNAME@$(hostname -I | awk '{print $1}')"