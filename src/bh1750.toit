// Copyright (C) 2021 Toitware ApS. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be found
// in the LICENSE file.

import log
import binary
import serial.device as serial
import serial.registers as registers

// Datasheet: https://www.mouser.com/datasheet/2/348/bh1750fvi-e-186247.pdf

/**
Driver for the BH1750 ambient light sensor.
*/
class Bh1750:
  // Public
  static I2C-ADDRESS                 ::= 0x23
  static I2C-ADDRESS-ALT             ::= 0x5C

  static POWER-DOWN_                 ::= 0b0000_0000
  static POWER-ON_                   ::= 0b0000_0001

  /** Reset data register value - not accepted in POWER_DOWN mode */
  static RESET_                      ::= 0b0000_0111

  /** 0.5 lx resolution - typically 120ms. */
  static CONTINUOUS-HIGH-RES-MODE-2  ::= 0b0001_0001

  /** 1.0 lx resolution - typically 120ms. */
  static CONTINUOUS-HIGH-RES-MODE    ::= 0b0001_0000

  /** 4.0 lx resolution - typicaly 16ms */
  static CONTINUOUS-LOW-RES-MODE     ::= 0b0001_0011

  /** 0.5 lx resolution - typically 120ms - then power down. */
  static ONE-TIME-HIGH-RES-MODE-2    ::= 0b0010_0001

  /** 1.0 lx resolution - typically 120ms - then power down. */
  static ONE-TIME-HIGH-RES-MODE      ::= 0b0010_0000

  /** 4.0 lx resolution - typically 16ms - then power down. */
  static ONE-TIME-LOW-RES-MODE       ::= 0b0010_0011

  static MTREG-DEFAULT               ::= 69.0
  static MTREG-MIN                   ::= 31.0
  static MTREG-MAX                   ::= 254.0

  static CORRECTION-FACTOR-DEFAULT   ::= 1.2
  static CORRECTION-FACTOR-MIN       ::= 0.96
  static CORRECTION-FACTOR-MAX       ::= 1.44


  // Private Variables
  dev_/serial.Device       := ?
  logger_/log.Logger       := ?
  mode_/int                := 0
  mtreg_/float             := 0.0
  wait-time-ms_/int        := 0
  stale_/bool              := false
  correction-factor_/float := 0.0

  constructor device/serial.Device --logger/log.Logger=(log.default.with-name "bh1750"):
    logger_       = logger
    dev_          = device
    recalculate-wait-time-ms_
    power-on
    reset
    set-correction-factor CORRECTION-FACTOR-DEFAULT
    set-mode CONTINUOUS-HIGH-RES-MODE
    set-mtreg MTREG-DEFAULT

  /** Powers on the device */
  power-on -> none:
    dev_.write #[POWER-ON_]

  /** Powers off the device */
  power-off -> none:
    dev_.write #[POWER-DOWN_]

  /** Resets the device and clears values */
  reset -> none:
    dev_.write #[RESET_]

  /**
  Sets correction factor for reads.

  Typical value is 1.2 but can range from 0.96 to 1.44. See the data sheet (p.2,
  Measurement Accuracy) (and/or README.md) for more information.
  */
  set-correction-factor factor/float -> none:
    assert: CORRECTION-FACTOR-MIN <= factor <= CORRECTION-FACTOR-MAX
    correction-factor_ = factor

  /**
  Gets correction factor. See $set-correction-factor.
  */
  get-correction-factor -> float:
    return correction-factor_

  /**
  Sets the Measurement/Time (integration-time/sensitivity) register. See README.md.
  */
  set-mtreg mtreg/float -> none:
    assert: MTREG-MIN <= mtreg <= MTREG-MAX
    mtreg_ = mtreg
    dev_.write #[(0b01000_000 | (mtreg_.to-int >> 5))]   // high bits
    dev_.write #[(0b011_00000 | (mtreg_.to-int & 0x1F))] // low bits
    recalculate-wait-time-ms_
    dev_.write #[mode_]                                  // Ensures effective immediately
    stale_ = true

  /**
  Gets the Measurement/Time (integration-time/sensitivity) register. See README.md.
  */
  get-mtreg -> float:
    return mtreg_

  /**
  Sets the mode (select from the constants).
  */
  set-mode mode/int -> none:
    mode_ = mode
    dev_.write #[mode_]
    recalculate-wait-time-ms_
    stale_ = true

  /**
  Returns ambient light level

  Takes care of issues such as priming and the specific mode requiring / 2
  */
  read-lux -> float:
    // If config changed (stale_=true) prime by reading once
    if stale_:
      if mode_ == ONE-TIME-HIGH-RES-MODE
          or mode_ == ONE-TIME-HIGH-RES-MODE-2
          or mode_ == ONE-TIME-LOW-RES-MODE:
        dev_.write #[mode_]
      sleep --ms=wait-time-ms_
      throw-away := dev_.read 2   // discard
      stale_ = false

    // If using ONE-TIME modes, mode must be re-issued before each read:
    if mode_ == ONE-TIME-HIGH-RES-MODE
        or mode_ == ONE-TIME-HIGH-RES-MODE-2
        or mode_ == ONE-TIME-LOW-RES-MODE:
      dev_.write #[mode_]

    sleep --ms=wait-time-ms_

    data := dev_.read 2
    level := (data[0] << 8) | data[1]
    lux/float := (level.to-float / correction-factor_) * (MTREG-DEFAULT / mtreg_)

    if (mode_ == CONTINUOUS-HIGH-RES-MODE-2) or (mode_ == ONE-TIME-HIGH-RES-MODE-2):
      lux /= 2.0

    //logger_.debug "read-lux: measured $(lux) lux"
    return lux

  /**
  Recalculates the wait time for a read and stores in class variable
  */
  recalculate-wait-time-ms_ -> none:
    // Wait for integration to complete.
    base-ms := (mode_ == CONTINUOUS-LOW-RES-MODE or mode_ == ONE-TIME-LOW-RES-MODE) ? 16 : 120

    // Scale time by mtreg_/69.0 (DEFAULT)
    scale/float := mtreg_ / MTREG-DEFAULT
    time-ms/int := (base-ms * scale).ceil.to-int

    // Enforce minimums
    if time-ms < 16: time-ms = 16
    // Hi-res modes can take up to ~180 ms per datasheet; give them headroom
    if (base-ms >= 120) and (time-ms < 180): time-ms = 180

    // Store the value
    wait-time-ms_ = time-ms
