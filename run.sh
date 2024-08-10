#!/bin/bash

# Restart the Chrome Remote Desktop service
service chrome-remote-desktop stop
service chrome-remote-desktop start

# Print hostname and keep the script running
echo 'your device currently active...'
sleep infinity
