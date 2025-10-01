
// Copyright (C) 2025 Toit Contributors
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import gpio
import i2c
import bh1750 as bh1750

main:

  sda-pin-number := 26    // please set these correctly for your device
  scl-pin-number := 25    // please set these correctly for your device

  // Enable and drive I2C:
  frequency := 400_000
  sda-pin := gpio.Pin sda-pin-number
  scl-pin := gpio.Pin scl-pin-number
  bus := i2c.Bus --sda=sda-pin --scl=scl-pin --frequency=frequency
  scandevices := bus.scan

  if not scandevices.contains bh1750.Bh1750.I2C-ADDRESS:
    print "No MPR121 device found [0x$(%02x bh1750.Bh1750.I2C-ADDRESS)]"
  else:
    bh1750-device := bus.device bh1750.Bh1750.I2C-ADDRESS
    bh1750-driver := bh1750.Bh1750 bh1750-device


    bh1750-driver.set-mode bh1750.Bh1750.CONTINUOUS_HIGH_RES_MODE
    50.repeat:
      print "$(%0.2f bh1750-driver.read-lux)"
      sleep --ms=200
