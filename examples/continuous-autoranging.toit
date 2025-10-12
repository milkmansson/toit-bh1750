// Copyright (C) 2025 Toit Contributors
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import gpio
import i2c
import bh1750 show *

sda-pin-number := 19    // please set these correctly for your device
scl-pin-number := 20    // please set these correctly for your device

main:
  // Enable and drive I2C:
  frequency := 400_000
  sda-pin := gpio.Pin sda-pin-number
  scl-pin := gpio.Pin scl-pin-number
  bus := i2c.Bus --sda=sda-pin --scl=scl-pin --frequency=frequency
  scandevices := bus.scan

  if not scandevices.contains Bh1750.I2C-ADDRESS:
    print "No Bh1750 device found [0x$(%02x Bh1750.I2C-ADDRESS)]"
    return

  bh1750-device := bus.device Bh1750.I2C-ADDRESS
  bh1750-driver := Bh1750 bh1750-device
  bh1750-driver.set-mode Bh1750.CONTINUOUS-HIGH-RES-MODE

  // Set Autoranging on, default values
  bh1750-driver.enable-autoranging

  50.repeat:
    print "Value: $(%0.2f bh1750-driver.read-lux) \t ema: $(%0.5f bh1750-driver.read-moving-average) \t mtreg: $(%0.0f bh1750-driver.get-mtreg)"
    sleep --ms=500
