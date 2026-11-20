#!/bin/bash

API_URL="http://192.168.0.106:2017/api"
TOKEN=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJleHAiOjE3OTY0NzYxOTMsInVuYW1lIjoic2VydmVyX3ZwbiJ9.4QbjcFNRMIZIbvfOq_5nHCELPWpKr6Q4pc_RbRvtJaw

get_subscriptions() {
	local response

	if ! response=$(curl -sf "$API_URL/touch" -H "Authorization: Bearer $TOKEN"); then
		echo "Error: curl failed or server returned HTTP error."
		return 1
	fi

	jq '.data.touch.subscriptions[].servers[].id' <<< "$response"

}

is_running(){
	local response
	response=$(curl -sf "$API_URL/touch" -H "Authorization: Bearer $TOKEN")
	jq '.data.running' <<< "$response"
}

test_connection() {
	curl -fsS --max-time 3 -o /dev/null "http://www.youtube.com/generate_204" 2>/dev/null || return 1
	curl -fsS --max-time 3 -o /dev/null "https://api.telegram.org/" 2>/dev/null || return 1
	curl -fsS --max-time 3 -o /dev/null "https://chatgpt.com" 2>/dev/null|| return 1
	curl -fsS --max-time 3 -o /dev/null "https://claude.com" 2>/dev/null|| return 1

	return 0
}

select_server(){
	curl -Ssf -X PUT "$API_URL/outboundSelection" \
	-H "Authorization: Bearer $TOKEN" \
	-H "Content-Type: application/json" \
	-d '{"outbound":"proxy","which":{"_type":"subscriptionServer","id":'"$1"',"sub":0,"Link":"","outbound":"proxy"}}' \
	> /dev/null
}

update_subscriptions(){
	curl -sSf -X PUT "$API_URL/subscription" \
	-H "Authorization: Bearer $TOKEN" \
	-H "Content-Type: application/json" \
	-d '{"_type":"subscription","id":1}' \
	> /dev/null
}

send_alert(){
	local HS TOKEN ROOM TXN ROOM_ENC PAYLOAD
	source /etc/matrix-notify.env

	ALERT_SERVICE="v2rayA updater"
	TXN="$(date +%s%N)-$$"
	ROOM_ENC=$(printf '%s' "$ROOM" | jq -sRr @uri)
	PAYLOAD=$(jq -n --arg b "[$ALERT_SERVICE] $*" '{msgtype:"m.text", body:$b}')

	curl -fSs --max-time 15 \
	-X PUT \
	-H "Authorization: Bearer $TOKEN" \
	-H 'Content-Type: application/json' \
	-d "$PAYLOAD" \
	"$HS/_matrix/client/v3/rooms/$ROOM_ENC/send/m.room.message/$TXN" \
	>/dev/null
}

disable_vpn(){
	curl -Ssf -X DELETE "$API_URL/v2ray" \
	-H "Authorization: Bearer $TOKEN" \
	-H "Content-Type: application/json" \
	> /dev/null
}

find_alive(){
	local output

	output=$(get_subscriptions) || {
		echo "Error: curl failed or server returned HTTP error."
		return 1
	}

	mapfile -t ids <<< "$output"

	for id in "${ids[@]}"; do
		select_server "$id" || {
			echo "Failed to select server $id"
			continue
		}

		sleep 3
		if test_connection; then
			echo "Server $id is available"
			return 0
		fi
	done
	return 1
}

main() {

	if [ "$(is_running)" == "false" ]; then
		echo "VPN is already disabled"
		return 0
	fi

	if test_connection; then
		echo "Active server is available"
		return 0
	fi

	if ! find_alive; then
		sub-convert || { echo "VPN provider is unavailable"; return 1; }
		sleep 2
		update_subscriptions
		find_alive || { echo "All VPN servers unavailable, VPN will be disabled"; return 1; }
	fi
}

out=$(main) || { disable_vpn; send_alert "Couldn't update subscription or connect to VPN server:"$'\n\n'"$out"; exit 1; }
