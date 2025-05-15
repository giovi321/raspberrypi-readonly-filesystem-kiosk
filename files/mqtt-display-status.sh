#!/bin/bash

# Configurable variables
BROKER="192.168.1.1"
USER="your-username"
PASSWORD="your-password"
TOPIC="tablet/screen/status"

# Function to check and publish monitor state
check_and_publish_monitor_state() {
    # Get the current monitor state
    monitor_state=$(DISPLAY=:0 xset q | grep "Monitor is" | awk '{print $3}')

    # Check if the monitor is On or Off
    if [ "$monitor_state" == "On" ]; then
        # If the monitor is On, publish message "1" to the MQTT topic
        mosquitto_pub -h "$BROKER" -u "$USER" -p 1883 -P "$PASSWORD" -t "$TOPIC" -m "1"
        echo "Monitor is On. Message '1' sent."
    else
        # If the monitor is Off, publish message "0" to the MQTT topic
        mosquitto_pub -h "$BROKER" -u "$USER" -p 1883 -P "$PASSWORD" -t "$TOPIC" -m "0"
        echo "Monitor is Off. Message '0' sent."
    fi
}

# Call the function to check the monitor state and publish the result
check_and_publish_monitor_state
