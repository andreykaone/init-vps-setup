#!/bin/bash
set -e  # Прерывать выполнение при ошибках

# Разбор аргументов
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--user)
            USERNAME="$2"
            ;;
        *)
    esac
done


echo "перед проверкой рута"


# Проверка прав root
if [ "$EUID" -ne 0 ]; then 
  echo "Пожалуйста, запускайте скрипт из-под пользователя root"
  exit 1
fi

echo "после проверки рута"


# Использование параметров
echo "USERNAME: $USERNAME"


# Создание пользователя
if id "$1" >/dev/null 2>&1; then
    echo "пользователь " $USERNAME " уже существует"
else
    adduser --disabled-password --gecos "" $USERNAME
    echo "пользователь " $USERNAME " создан"
fi

usermod -aG sudo $USERNAME