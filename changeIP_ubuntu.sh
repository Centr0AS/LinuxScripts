#!/bin/bash
# change_ip.sh — смена IP сервера в netplan и v2ray.json
# Запуск: sudo bash change_ip.sh

# ====== ПУТИ К ФАЙЛАМ (проверь под свой сервер) ======
NETPLAN_FILE="/etc/netplan/01-netcfg.yaml"
V2RAY_FILE="/etc/shadowsocks-libev/v2ray.json"
# =====================================================

# Скрипт должен работать от root
if [ "$EUID" -ne 0 ]; then
    echo "Запусти скрипт от root: sudo bash $0"
    exit 1
fi

# Проверка наличия файлов
for f in "$NETPLAN_FILE" "$V2RAY_FILE"; do
    if [ ! -f "$f" ]; then
        echo "Файл не найден: $f"
        exit 1
    fi
done

# Запрос нового IP
read -r -p "Введите новый IP адрес сервера: " NEW_IP

# Проверка формата IPv4 (каждый октет 0-255)
if ! [[ "$NEW_IP" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]]; then
    echo "Ошибка: неверный формат IP адреса."
    exit 1
fi
for octet in "${BASH_REMATCH[@]:1}"; do
    if [ "$octet" -gt 255 ]; then
        echo "Ошибка: октет $octet больше 255."
        exit 1
    fi
done

# Шлюз = первые три октета + .1
NEW_GW="${NEW_IP%.*}.1"

echo
echo "Новый IP сервера: $NEW_IP"
echo "Новый шлюз:       $NEW_GW"
read -r -p "Продолжить? (y/n): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[YyДд]$ ]]; then
    echo "Отменено."
    exit 0
fi

# 1) netplan: addresses (маска сохраняется как есть)
sed -i -E "s|(addresses: \[ *\")[0-9]{1,3}(\.[0-9]{1,3}){3}(/[0-9]+\")|\1${NEW_IP}\3|" "$NETPLAN_FILE"

# 2) netplan: шлюз (via)
sed -i -E "s|(via: *)[0-9]{1,3}(\.[0-9]{1,3}){3}|\1${NEW_GW}|" "$NETPLAN_FILE"

# 3) v2ray.json: "server"
sed -i -E "s|(\"server\" *: *\")[0-9]{1,3}(\.[0-9]{1,3}){3}(\")|\1${NEW_IP}\3|" "$V2RAY_FILE"

echo
echo "Результат замены:"
grep -n "addresses: \[" "$NETPLAN_FILE"
grep -n "via:" "$NETPLAN_FILE"
grep -n "\"server\"" "$V2RAY_FILE"
echo

# Проверка конфигурации netplan до применения
if ! netplan generate; then
    echo "Ошибка в конфигурации netplan! Применение и перезагрузка отменены."
    exit 1
fi

echo "Применяю netplan и перезагружаю сервер..."
echo "(SSH-соединение оборвётся — это нормально, подключайтесь по новому IP)"

# Запуск в фоне, отвязанно от терминала: после смены IP SSH-сессия
# падает, и без этого скрипт мог бы не дойти до перезагрузки.
nohup bash -c 'netplan apply; sleep 3; reboot' >/dev/null 2>&1 &
disown
exit 0
