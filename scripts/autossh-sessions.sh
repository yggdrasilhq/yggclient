#! /usr/bin/sh

# this is the vnc server "pi" zone
autossh -M 0 -o "ServerAliveInterval 30" -o "ServerAliveCountMax 3" -N -f \
 -L 5901:localhost:5901 root@192.168.3.3
