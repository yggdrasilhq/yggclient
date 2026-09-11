#! /usr/bin/sh

# this is the vnc server "pi" zone
# no -f: the unit is Type=simple and needs autossh as its main process —
# a backgrounded autossh gets SIGTERM'd by the cgroup teardown every restart
exec autossh -M 0 -o "ServerAliveInterval 30" -o "ServerAliveCountMax 3" -N \
 -L 5901:localhost:5901 root@192.0.2.33
