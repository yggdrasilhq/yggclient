#!/usr/bin/env bash
set -euo pipefail

# Lenovo ThinkBook 16 G9 AHP (FTCS1000) workaround:
# On some boots the AMD DesignWare I2C path probes as 0xffffffff and the
# touchpad is missing. Reprobe HID/I2C stack a few times to recover it.

modprobe i2c_designware_core 2>/dev/null || true
modprobe i2c_designware_platform 2>/dev/null || true

# Give the platform a short window to finish ACPI/I2C bring-up.
for attempt in $(seq 1 30); do
  if grep -q "FTCS1000" /proc/bus/input/devices 2>/dev/null; then
    exit 0
  fi

  # Try rebinding AMD DesignWare I2C controllers.
  for dev in AMDI0010:00 AMDI0010:01 AMDI0010:03; do
    if [[ -e /sys/bus/platform/drivers/i2c_designware/bind ]]; then
      echo "$dev" > /sys/bus/platform/drivers/i2c_designware/bind 2>/dev/null || true
    fi
  done

  # Every few attempts, reprobe I2C HID modules as well.
  if (( attempt % 5 == 0 )); then
    modprobe -r i2c_hid_acpi i2c_hid hid_multitouch hid_generic 2>/dev/null || true
    modprobe hid_generic 2>/dev/null || true
    modprobe hid_multitouch 2>/dev/null || true
    modprobe i2c_hid_acpi 2>/dev/null || true
    modprobe i2c_hid 2>/dev/null || true
  fi

  if grep -q "FTCS1000" /proc/bus/input/devices 2>/dev/null; then
    exit 0
  fi

  udevadm settle || true
  sleep 1
done

echo "FTCS1000 touchpad did not appear after reprobe attempts" >&2
exit 1
