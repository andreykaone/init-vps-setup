#!/bin/bash
set -e  # Прерывать выполнение при ошибках

echo -n "New username: "
read -r $USERNAME

echo "creating user: $USERNAME"
