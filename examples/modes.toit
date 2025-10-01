// Copyright (C) 2025 Toit Contributors
// This is a derived work from work Copyright (C) 2021 Justin Decker. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be found
// in the LICENSE file.

import gpio
import i2c
import bh1750 show *

sda-pin-number := 19    // please set these correctly for your device
scl-pin-number := 20    // please set these correctly for your device

main:
  bus := i2c.Bus
    --sda=gpio.Pin sda-pin-number
    --scl=gpio.Pin scl-pin-number

  // Alternate address accessed with I2C_ADDRESS_ALT
  // (e.g:  device := bus.device bh1750.I2C-ADDRESS-ALT)
  device := bus.device Bh1750.I2C-ADDRESS

  /* Set device and mode to driver.
     Mode options are:
      CONTINUOUS-HIGH-RES-MODE   : 1 lx resolution, 120 ms each continuous measurement
      CONTINUOUS-HIGH-RES-MODE-2 : 0.5 lx resolution, 120 ms each continuous measurement
      CONTINUOUS-LOW-RES-MODE    : 4lx resoution, 16 ms each continuous measurement
      ONE-TIME-HIGH-RES-MODE     : 1 lx resolution, 120 ms, one measurement then shuts down
      ONE-TIME-HIGH-RES-MODE-2   : 0.5 lx resolution, 120 ms, one measurement then shuts down
      ONE-TIME-LOW-RES-MODE      : 4 lx resolution, 16 ms, one measurement then shuts down
  */
  driver := Bh1750 device
  driver.set-mode Bh1750.CONTINUOUS-HIGH-RES-MODE

  while true:
    print "$(%0.2f driver.read-lux) lux"
    sleep --ms=1000
