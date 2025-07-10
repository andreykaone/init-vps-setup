#!/bin/bash
set -e  # Прерывать выполнение при ошибках


# Проверка прав root
if [ "$EUID" -ne 0 ]; then 
  echo "Please run as root"
  echo "EUID: $EUID"
  echo "USER: $USER"
  exit 1
fi

apt update && apt full-upgrade -y