# Raspberry Pi read-only filesystem kiosk

This works on Bookworm releases of raspberry pi - tested on a PI 4 with a fresh install of the lite version.
I took the instructions wrote by @vladbabii here https://github.com/vladbabii/raspberry_os_buster_read_only_fs and improved them:
1) compatibility with Raspberry PI OS Bookworm
2) Possibility to add a kiosk mode (a chromium window that auto starts and shows a web page)

## Initial setup

* Configure WiFi, and anything else you want using Raspberry Pi Imager
* Write the image of raspberry pi OS lite on the SD card

## First boot

Update packages
```
apt-get update
apt-get upgrade
```

Run as root
```
apt-get remove --purge triggerhappy logrotate dphys-swapfile
apt-get autoremove --purge
```

Edit /boot/cmdline.txt and add at the end of the first line of the file
```
fastboot noswap ro
```

Log manager change (as root)
```
apt-get install busybox-syslogd
```

Edit /etc/fstab and add the ",ro" flags to all block devices that start with PARTUUID=...
```
proc                  /proc     proc    defaults             0     0
PARTUUID=fb0d460e-01  /boot     vfat    defaults,ro          0     2
PARTUUID=fb0d460e-02  /         ext4    defaults,noatime,ro  0     1
```


Edit /etc/fstab and add tmpfs
```
tmpfs        /tmp            tmpfs   nosuid,nodev         0       0
tmpfs        /var/log        tmpfs   nosuid,nodev         0       0
tmpfs        /var/tmp        tmpfs   nosuid,nodev         0       0
```

Install & enable `systemd-resolved`
```
apt-get install --no-install-recommends systemd-resolved
systemctl enable systemd-resolved
systemctl start systemd-resolved
```

Tell NetworkManager to hand DNS off to systemd
```
mkdir -p /etc/NetworkManager/conf.d
cat <<EOF > /etc/NetworkManager/conf.d/10-dns.conf
[main]
dns=systemd-resolved
EOF
systemctl restart NetworkManager
```

Now all lookups go through the in-RAM stub at `/run`

System random seed
```
rm /var/lib/systemd/random-seed
ln -s /tmp/random-seed /var/lib/systemd/random-seed
```

Edit /lib/systemd/system/systemd-random-seed.service , add line
```
ExecStartPre=/bin/echo "" >/tmp/random-seed
```
under [Service] section like this
```
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStartPre=/bin/echo "" >/tmp/random-seed
ExecStart=/lib/systemd/systemd-random-seed load
ExecStop=/lib/systemd/systemd-random-seed save
TimeoutSec=30s
```

Edit /etc/bash.bashrc and add the lines at the end of the file
```
set_bash_prompt() {
    fs_mode=$(mount | sed -n -e "s/^\/dev\/.* on \/ .*(\(r[w|o]\).*/\1/p")
    PS1='\[\033[01;32m\]\u@\h${fs_mode:+($fs_mode)}\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
}
alias ro='sudo mount -o remount,ro / ; sudo mount -o remount,ro /boot'
alias rw='sudo mount -o remount,rw / ; sudo mount -o remount,rw /boot'
PROMPT_COMMAND=set_bash_prompt
```

Create /etc/bash.bash_logout
```
mount -o remount,ro /
mount -o remount,ro /boot
```

Reboot and enjoy!


## How to use

Connect via ssh and type "rw" to make the filesystem writable again and install anything you want.

Type "ro" to make the filesystem readonly again - it can take some time untill all writes are finished so be a little patient.

The prompt will change based on rw or ro filesystem to let you know the state, here is how it will look like when switching from ro to rw and back again
```
pi@raspberrypi(ro):~$ rw
pi@raspberrypi(rw):~$ ro
pi@raspberrypi(ro):~$ 
```

# Add kiosk mode

# Set up the browser and window manager

Install `x`, `openbox` and `chromium` to have a window manager and browser
```
apt install -y xinit openbox chromium-browser
```

Create a kiosk X session file: create `/root/.xinitrc`
```
nano /root/.xinitrc
```

Paste the following into that file, remember to change the link to the page you want the kiosk to show
```
#!/bin/sh

# Disable screensaver and DPMS
xset s off
xset -dpms
xset s noblank

# Start Openbox as window manager
openbox-session &

# Start Chromium in kiosk mode without need for cache
chromium-browser \
  --no-sandbox \
  --kiosk \
  --incognito \
  --disable-application-cache \
  --disable-session-crashed-bubble \
  --disable-infobars \
  --no-first-run \
  --disk-cache-dir=/dev/null \
  --user-data-dir=/tmp/chrome \
  http://your-page-link-here

```

Make the file executable:
```
chmod +x /root/.xinitrc
```

Auto-start at boot the kiosk mode via `systemd`
```
nano /etc/systemd/system/kiosk.service
```

Add the following content to the file
```
[Unit]
Description=Minimal Chromium Kiosk
After=network.target

[Service]
ExecStart=/usr/bin/xinit
WorkingDirectory=/root
User=root
Restart=always
Environment=XDG_RUNTIME_DIR=/run/user/0

[Install]
WantedBy=default.target
```

Enable the service
```
sudo systemctl enable kiosk.service
```

## Remove the mouse cursor permanently [optional]

Create or edit `/root/.xserverrc`
```
Create or edit `/root/.xserverrc`:
```

Put this inside
```
#!/bin/sh
exec /usr/bin/X -nocursor -nolisten tcp "$@"
```

Make it executable
```
`chmod +x /root/.xserverrc
```

## Remove the cursor only when inactive

Install `unclutter`
```
sudo apt install unclutter-xfixes
```

Run it before Chromium in your `/root/.xinitrc` file by adding this line above all the rest
```
`unclutter -idle 5 &`
```

You can change the timeout (i.e., the time the computer will wait before hiding the cursor after the latest interaction). The default is 5 seconds.


# Control the screen via MQTT
A little extra: these few scripts will allow you to control the screen via MQTT.

Install `mosquitto` client
```
apt install mosquitto-clients
```

Create the script that will turn on and off the screen
```
nano /mqtt-display-set.sh
```

Add the following content and edit the MQTT broker variables
```
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
```

Create the script that publishes the status of the screen (on/off)
```
nano /mqtt-display-status.sh
```

Add the following content and edit the MQTT broker variables
```
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
```

Make the two scripts executable
```
chmod +x mqtt-display-set.sh
chmod +x mqtt-display-status.sh 
```

Create the two systemd services to auto-start the scripts
```
nano /etc/systemd/system/mqtt-display-set.service
```

Add the following content to the file
```
[Unit]
Description=Monitor Display Control based on MQTT messages
After=network.target

[Service]
ExecStart=/mqtt-display-set.sh
Restart=always
User=root
StandardOutput=journal
StandardError=journal
RestartSec=5s

[Install]
WantedBy=multi-user.target
```

Now the second service
```
nano /etc/systemd/system/mqtt-display-staus.service
```

Add the following content to the file
```
[Unit]
Description=Publish Monitor State to MQTT
After=network.target

[Service]
ExecStart=/mqtt-display-status.sh
Restart=always
User=root
StandardOutput=journal
StandardError=journal
RestartSec=5s

[Install]
WantedBy=multi-user.target
```

Enable and start the two services
```
systemctl enable mqtt-display-set.service
systemctl enable mqtt-display-status.service
systemctl start mqtt-display-set.service
systemctl start mqtt-display-status.service
```

# Sources
* https://github.com/vladbabii/raspberry_os_buster_read_only_fs 
* https://media.ccc.de/v/30C3_-_5294_-_en_-_saal_1_-_201312291400_-_the_exploration_and_exploitation_of_an_sd_memory_card_-_bunnie_-_xobs#t=2
* https://learn.adafruit.com/read-only-raspberry-pi
* https://medium.com/swlh/make-your-raspberry-pi-file-system-read-only-raspbian-buster-c558694de79


# License
The content of this repository is licensed under the WTFPL.
```
Copyright © 2023 giovi321
This work is free. You can redistribute it and/or modify it under the
terms of the Do What The Fuck You Want To Public License, Version 2,
as published by Sam Hocevar. See the LICENSE file for more details.
```
