#!/bin/bash

# MQTT Broker Details
BROKER="192.168.1.1"
USER="your-username"
PASSWORD="your-password"
TOPIC="tablet/screen/set"

# Function to turn off the display
turn_off_display() {
    echo "Turning off the display..."
    DISPLAY=:0 xset dpms force off
}

# Function to turn on the display
turn_on_display() {
    echo "Turning on the display..."
    DISPLAY=:0 xset dpms force on
    DISPLAY=:0 xset -dpms
}

# Subscribe to the MQTT topic and listen for messages
mosquitto_sub -h "$BROKER" -u "$USER" -p 1883 -P "$PASSWORD" -t "$TOPIC" | while read -r message
do
    if [ "$message" == "0" ]; then
        # If message is 0, turn off the display
        turn_off_display
    elif [ "$message" == "1" ]; then
        # If message is 1, turn on the display
        turn_on_display
    fi
done
