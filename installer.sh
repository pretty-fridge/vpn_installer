#!/bin/bash
set -euo pipefail

V2RAYA_INSTALLER_URL="https://github.com/v2rayA/v2rayA-installer/raw/main/installer.sh"
MY_REPO="https://raw.githubusercontent.com/pretty-fridge/vpn_installer/main/"
V2RAYA_URL="http://127.0.0.1:2017"
declare -A SYSTEMD_SHA256=(
["sub-convert.service"]="7e6c5224c1e3fcb7535fe8266a5386ced4bb8d4ad5ca89aef5d2e5d116aff9fd"
["sub-convert.timer"]="d49ff5ad2574460768503b3b2db09d16164b9de7397bedf9dcd6d68b3d224836"
["sub-http.service"]="57394aeddca15f8969d1c699d27e944d39c742ced9ec4e9a4c8d315fc437ad93"
["vpntester.service"]="854b82639aa68e415b36b55ac6635510f5da30e018ce5d6b286a51fdfe14649c"
["vpntester.timer"]="8e9dfc80710a76c23ce38be02bf85e2130617b52c48de393344dcbe495f0443b"
)
declare -A SCRIPTS_SHA256=(
["sub-convert"]="0fc8750261ab42b58747d9ef0a104b6ddecbd99c6a01fa22aaacc15ac2a85531"
["vpntester"]="d1d424890556238020572463c660a0b00e9a7b3f6d33da5245152f666f3eb104"
["example.env"]="5e4969d76e59309ce0d9c94e48e06ba432e8a95c9a88c5f462b06a385f353d63"
["RoutingA.txt"]="d73275d8179f79c6b8ebf9f043acf39d9363706f8642ade60947c11597b9f060"
["enable-sub-import"]="cc4a8229d5abd2043e3782b0d72a4b7da26950a1e0c2994ec5d82b144cb379d8"
)
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

set_matrix_notify() {
  printf "Введите url матрикс сервера, по умолчанию matrix.org" > /dev/tty
  read -r reply < /dev/tty || reply="matrix.org"
  sed -i "s|__MATRIX_SERVER__|https://$reply|g" "$1"

  printf "Введите токен пользователя от имени которого будут приходить уведомления" > /dev/tty
  reply=""
  while [ -z "$reply" ]; do
    read -r reply < /dev/tty || reply=""
    if [ -z "$reply" ]; then
      echo "Введите корректное значение"
      continue
    fi
  done
  sed -i "s|__MATRIX_USER_TOKEN__|$reply|g" "$1"

  printf "Введите ID комнаты, в которую будут приходить уведомления"
  reply=""
  while -z "$reply"; do
    read -r reply < /dev/tty || reply=""
    if [ -z "$reply" ]; then
      echo "Введите корректное значение"
      continue
    fi
  done
  sed -i "s|__ROOM_ID__|$reply|g" "$1"
}

take_v2raya_token(){
  ADMIN_USER="admin"
  ADMIN_PASS="$(openssl rand -hex 10)"
  response=$(curl -s -X POST "$V2RAYA_URL/api/register" \
  -H "Content-Type: application/json" \
  -d '{"username": "'"$ADMIN_USER"'", "password": "'"$ADMIN_PASS"'"}')

  token=$(echo "$response" | jq -r '.data.token // empty')
  echo "$token"
}

print_finish_summary() {
  local panel_url="$1"
  local panel_user="$2"
  local panel_pass="$3"

  local bold="" green="" cyan="" dim="" reset=""
  if [ -t 1 ]; then
    bold=$'\033[1m'
    green=$'\033[32m'
    cyan=$'\033[36m'
    dim=$'\033[2m'
    reset=$'\033[0m'
  fi

  printf '\n'
  printf '%s┌──────────────────────────────────────────────────┐%s\n' "$green" "$reset"
  printf '%s│%s %sУстановка завершена%s                              %s│%s\n' "$green" "$reset" "$bold" "$reset" "$green" "$reset"
  printf '%s├──────────────────────────────────────────────────┤%s\n' "$green" "$reset"
  printf '%s│%s Панель : %s%-39s%s %s│%s\n' "$green" "$reset" "$cyan" "$panel_url" "$reset" "$green" "$reset"
  printf '%s│%s Логин  : %-39s %s│%s\n' "$green" "$reset" "$panel_user" "$green" "$reset"
  printf '%s│%s Пароль : %s%-39s%s %s│%s\n' "$green" "$reset" "$bold" "$panel_pass" "$reset" "$green" "$reset"
  printf '%s└──────────────────────────────────────────────────┘%s\n' "$green" "$reset"
  printf '\n%sПодсказка:%s если подписка не импортируется в веб-панели или появляется ошибка о недоступности VPN-клиента,\n' "$bold" "$reset"
  printf 'выполните: %ssudo enable-sub-import%s\n\n' "$cyan" "$reset"
}

check_hash() {
  local file_name="$1"
  local -n hash_name="$2"
  local expected="${hash_name[$file_name]}"
  local actual

  tmp_file="$TMP_DIR/$file_name"

  if [ -z "$expected" ]; then
    echo "Error: expected SHA-256 not found for $file_name in $hash_name" >&2
    return 1
  fi

  actual="$(sha256sum "$tmp_file" | awk '{print $1}')"

  if [ "$actual" != "$expected" ]; then
    echo "Error: SHA-256 checksum mismatch for $file_name" >&2
    return 1
  fi
}

set_routinga() {
  local ROUTINGA_FILE="$TMP_DIR/RoutingA.txt"
  local payload=$(jq -nc --rawfile rules "$ROUTING_FILE" '{routingA: $rules}')
  curl -sSf -X PUT "$V2RAYA_URL/api/routingA" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "$payload" || echo "Не удалось экспортировать RoutingA файл"
}


apt update -y
apt install -y wget curl jq openssl

# Определяем, нужен ли sudo
if ! [ "$(id -u)" -eq 0 ]; then
    echo "Запустите скрипт с использованием прав sudo" >&2
    exit 1
fi

# Проверяем наличие wget
if ! command -v wget >/dev/null 2>&1; then
    apt install wget
fi

echo "Запуск установки v2rayA с Xray..."
if ! sh -c "$(wget -qO- "$V2RAYA_INSTALLER_URL")" @ --with-xray; then
  echo "Ошибка при выполнении установщика v2rayA." >&2
  exit 1
fi


#Загрузка и проверка хеша для systemd файлов
echo "Загружаю и проверяю systemd конфиги"
for file_name in "${!EXPECTED_SHA256[@]}"; do
  tmp_file="$TMP_DIR/$file_name"
  dest_file="/etc/systemd/system/$file_name"

  wget -qO "$tmp_file" "$MY_REPO/systemd/$file_name"
  if ! [ check_hash "$file_name" EXPECTED_SHA256 ]; then
    exit 1
  fi

  if [ "$file_name" == "vpntester.service" ]; then
    target_user="${SUDO_USER:-$USER}"
    sed -i "s|__USER__|$target_user|g" "$tmp_file"
  fi

  cp "$tmp_file" "$dest_file"
  chmod 644 "$dest_file"
done
echo "Файлы systemd успешно проверены и установлены"

echo "Загружаю и проверяю скрипты"
for file_name in "${!SCRIPTS_SHA256[@]}"; do
  tmp_file="$TMP_DIR/$file_name"
  dest_file="/usr/local/bin/$file_name"

  wget -qO "$tmp_file" "$MY_REPO/$file_name"
  if ! check_hash "$file_name" SCRIPTS_SHA256 ; then
    exit 1
  fi

  if [ "$file_name" == "example.env" ]; then
    printf "Настроить уведомления в Matrix? [y/N]: " > /dev/tty
    read -r REPLY < /dev/tty || REPLY=""

    case "${REPLY,,}" in
      y|yes|д|да)
        set_matrix_notify "$tmp_file"
        ;;
      *)
        ;;
    esac

    TOKEN=$(take_v2raya_token)

    if [ -z "$TOKEN" ]; then
      echo "Error: couldn't get v2raya token"
      exit 1
    fi
    sed -i "s|__V2RAYA_TOKEN__|$token|g" "$tmp_file"
    cp "$tmp_file" "/etc/home-vpn.env"
    chmod 640 "/etc/home-vpn.env"
  elif [ "$file_name" == "RoutingA.txt" ]; then
    continue
  else
    cp "$tmp_file" "$dest_file"
    chmod 755 "$dest_file"
  fi
done

systemctl daemon-reload
systemctl enable --now vpntester.timer
echo "Скрипты успешно проверены и установлены"

echo "Настраиваю конфигурацию v2raya"
curl -sSf -X PUT "$V2RAYA_URL/api/setting" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"transparent":"pac","transparentType":"tproxy","ipforward":true,"portSharing":false,"tproxyExcludedInterfaces":"docker*,veth*,wg*,ppp*,br-*","tunAutoRoute":true,"tunRouteShellType":"","tunRouteShellPath":"","tunSetupScript":"","tunTeardownScript":"","tunExcludeProcesses":"","pacMode":"routingA","pacAutoUpdateMode":"none","pacAutoUpdateIntervalHour":0,"subscriptionAutoUpdateMode":"auto_update_at_intervals","subscriptionAutoUpdateIntervalHour":1,"proxyModeWhenSubscribe":"proxy","tcpFastOpen":"default","logLevel":"info","inboundSniffing":"http,tls,quic","routeOnly":false,"muxOn":"no","mux":8}' > /dev/null

set_routinga
echo "Конфигурация v2raya успешно завершена"

print_finish_summary "$V2RAYA_URL" "$ADMIN_USER" "$ADMIN_PASS"
