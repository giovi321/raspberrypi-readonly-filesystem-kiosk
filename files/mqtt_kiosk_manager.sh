#!/bin/bash
# mqtt_kiosk_manager.sh
# Unified MQTT autodiscovery and kiosk management for Raspberry Pi

#########################
# Configuration (edit below)
#########################
BROKER="192.168.1.1"         # MQTT broker address
USER="username"                   # MQTT username
PASSWORD="password"      # MQTT password
DEVICE_NAME="Tablet"  # Friendly name in Home Assistant
DEVICE_ID="tablet"   # ID used in MQTT topics (no spaces)
INTERVAL_SCREENSHOT=10                      # Interval in seconds for screenshot
INTERVAL_SCREENSTATE=1                      # Interval in seconds for publishing the state of the screen (on or off)

#########################
# Prepare X access
#########################
export DISPLAY=:0
# Allow root to access X
xhost +SI:localuser:root >/dev/null 2>&1

#########################
# Device JSON payload for Home Assistant discovery
#########################
DEVICE_PAYLOAD=$(cat <<EOF
{"identifiers":["${DEVICE_ID}"],"name":"${DEVICE_NAME}","model":"kiosk","manufacturer":"none","sw_version":"1.0"}
EOF
)

# Common mosquitto_pub args
PUB_ARGS="-h $BROKER -u $USER -P $PASSWORD -r"
# Common mosquitto_sub args
SUB_ARGS=(-h "$BROKER" -u "$USER" -P "$PASSWORD")
RECONNECT_DELAY=5

log_reconnect() {
  echo "$(date +'%Y-%m-%dT%H:%M:%S%z') mqtt_kiosk_manager: MQTT connection lost for $1, retrying in ${RECONNECT_DELAY}s" >&2
}

#########################
# 0) Publish Home Assistant discovery
#########################
mosquitto_pub $PUB_ARGS -t "homeassistant/button/${DEVICE_ID}_display_off/config" -m "{\"name\":\"${DEVICE_NAME} Display Off\",\"unique_id\":\"${DEVICE_ID}_display_off\",\"command_topic\":\"${DEVICE_ID}/screen/set\",\"payload_press\":\"0\",\"device\":$DEVICE_PAYLOAD}"
mosquitto_pub $PUB_ARGS -t "homeassistant/button/${DEVICE_ID}_display_on/config" -m "{\"name\":\"${DEVICE_NAME} Display On\",\"unique_id\":\"${DEVICE_ID}_display_on\",\"command_topic\":\"${DEVICE_ID}/screen/set\",\"payload_press\":\"1\",\"device\":$DEVICE_PAYLOAD}"
mosquitto_pub $PUB_ARGS -t "homeassistant/binary_sensor/${DEVICE_ID}_screen_state/config" -m "{\"name\":\"${DEVICE_NAME} Screen State\",\"unique_id\":\"${DEVICE_ID}_screen_state\",\"state_topic\":\"${DEVICE_ID}/screen/state\",\"payload_on\":\"1\",\"payload_off\":\"0\",\"device_class\":\"connectivity\",\"device\":$DEVICE_PAYLOAD}"
mosquitto_pub $PUB_ARGS -t "homeassistant/button/${DEVICE_ID}_refresh/config" -m "{\"name\":\"${DEVICE_NAME} Refresh Page\",\"unique_id\":\"${DEVICE_ID}_refresh\",\"command_topic\":\"${DEVICE_ID}/refresh\",\"payload_press\":\"refresh\",\"device\":$DEVICE_PAYLOAD}"
mosquitto_pub $PUB_ARGS -t "homeassistant/button/${DEVICE_ID}_reboot/config" -m "{\"name\":\"${DEVICE_NAME} Reboot\",\"unique_id\":\"${DEVICE_ID}_reboot\",\"command_topic\":\"${DEVICE_ID}/reboot\",\"payload_press\":\"reboot\",\"device\":$DEVICE_PAYLOAD}"
mosquitto_pub $PUB_ARGS \
  -t "homeassistant/image/${DEVICE_ID}_screenshot/config" \
  -m "{\"name\":\"${DEVICE_NAME} Screenshot\",\"unique_id\":\"${DEVICE_ID}_screenshot\",\"image_topic\":\"${DEVICE_ID}/screenshot\",\"content_type\":\"image/png\",\"device\":${DEVICE_PAYLOAD}}"


#########################
# 1) Polling loops
#########################
# 1a) Screenshot publisher
download_loop() {
  while true; do
    TS=$(date +'%Y%m%dT%H%M%S')
    FILE="/tmp/${DEVICE_ID}_screenshot_${TS}.png"
    DISPLAY=:0 scrot -u "$FILE"
    mosquitto_pub $PUB_ARGS \
      -t "${DEVICE_ID}/screenshot" \
      -f "$FILE" \
      -q 1
    rm -f "$FILE"
    sleep "$INTERVAL_SCREENSHOT"
  done
}

# 1b) Screen state publisher
state_loop() {
  while true; do
    state=$(xset q | grep -Po '(?<=Monitor is )\w+')
    if [ "$state" = "On" ]; then p=1; else p=0; fi
    mosquitto_pub -h "$BROKER" -u "$USER" -P "$PASSWORD" -t "${DEVICE_ID}/screen/state" -m "$p"
    sleep $INTERVAL_SCREENSTATE
  done
}

# Start loops in background
download_loop &
state_loop &

#########################
# 2) Command listeners
#########################
# Screen on/off
screen_loop() {
  while true; do
    mosquitto_sub "${SUB_ARGS[@]}" -t "${DEVICE_ID}/screen/set" |
    while read -r cmd; do
      if [ "$cmd" = "0" ]; then xset dpms force off; fi
      if [ "$cmd" = "1" ]; then xset dpms force on; sleep 1; xset dpms 0 0 0; fi
    done
    log_reconnect "${DEVICE_ID}/screen/set"
    sleep "$RECONNECT_DELAY"
  done
}
screen_loop &

# Refresh page
touch_loop() {
  while true; do
    mosquitto_sub "${SUB_ARGS[@]}" -t "${DEVICE_ID}/refresh" |
    while read -r cmd; do
      if [ "$cmd" = "refresh" ]; then
        W=$(xdotool search --onlyvisible --class chromium | head -n1)
        xdotool key --window "$W" --clearmodifiers ctrl+F5
      fi
    done
    log_reconnect "${DEVICE_ID}/refresh"
    sleep "$RECONNECT_DELAY"
  done
}
touch_loop &

# Reboot
reboot_loop() {
  while true; do
    mosquitto_sub "${SUB_ARGS[@]}" -t "${DEVICE_ID}/reboot" |
    while read -r cmd; do
      [ "$cmd" = "reboot" ] && reboot
    done
    log_reconnect "${DEVICE_ID}/reboot"
    sleep "$RECONNECT_DELAY"
  done
}
reboot_loop &

# Prevent exit
wait
