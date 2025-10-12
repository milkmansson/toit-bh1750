// Copyright (C) 2025 Toit Contributors. All rights reserved.
// Use of this source code is governed by a MIT-style license that can be found
// in the LICENSE file.

import log
import serial.device as serial
import ema show *

/**
Driver for the BH1750 ambient light sensor.  See README.md.

Datasheet: https://www.mouser.com/datasheet/2/348/bh1750fvi-e-186247.pdf
*/
class Bh1750:
  // Public
  static I2C-ADDRESS                 ::= 0x23
  static I2C-ADDRESS-ALT             ::= 0x5C

  /** 0.5 lx resolution - typically 120ms. Use with $set-mode. */
  static CONTINUOUS-HIGH-RES-MODE-2  ::= 0b0001_0001

  /** 1.0 lx resolution - typically 120ms. Use with $set-mode. */
  static CONTINUOUS-HIGH-RES-MODE    ::= 0b0001_0000

  /** 4.0 lx resolution - typicaly 16ms Use with $set-mode. */
  static CONTINUOUS-LOW-RES-MODE     ::= 0b0001_0011

  /** 0.5 lx resolution - typically 120ms - then power down. Use with $set-mode. */
  static ONE-TIME-HIGH-RES-MODE-2    ::= 0b0010_0001

  /** 1.0 lx resolution - typically 120ms - then power down. Use with $set-mode. */
  static ONE-TIME-HIGH-RES-MODE      ::= 0b0010_0000

  /** 4.0 lx resolution - typically 16ms - then power down. Use with $set-mode. */
  static ONE-TIME-LOW-RES-MODE       ::= 0b0010_0011

  static MTREG-DEFAULT               ::= 69.0
  static MTREG-MIN                   ::= 31.0
  static MTREG-MAX                   ::= 254.0

  static CORRECTION-FACTOR-DEFAULT   ::= 1.2
  static CORRECTION-FACTOR-MIN       ::= 0.96
  static CORRECTION-FACTOR-MAX       ::= 1.44

  static AUTORANGING-ALPHA           ::= 0.37
  static AUTORANGING-CONSECUTIVE     ::= 5
  static AUTORANGING-HOLD-DOWN       ::= (Duration --s=2)

  static AUTORANGING-BRIGHT-OUTDOOR-MTREG  ::= 32.0
  static AUTORANGING-BRIGHT-ON-LUX         ::= 45000.0  // enter bright when >= this
  static AUTORANGING-BRIGHT-OFF-LUX        ::= 38000.0  // leave bright when <= this
  static AUTORANGING-DEFAULT-GENERAL-MTREG ::= MTREG-DEFAULT
  static AUTORANGING-LOW-LIGHT-MTREG       ::= 138.0
  static AUTORANGING-LOW-ON-LUX            ::= 9.0      // enter low band when <= this
  static AUTORANGING-LOW-OFF-LUX           ::= 12.0     // leave low band when >= this

  // Bright/outdoor band (go to low MTREG to avoid saturation):


  // Private

  /** Reset data register value - not accepted in POWER_DOWN mode. */
  static RESET_                      ::= 0b0000_0111

  static POWER-OFF_                  ::= 0b0000_0000
  static POWER-ON_                   ::= 0b0000_0001

  dev_/serial.Device       := ?
  logger_/log.Logger       := ?
  mode_/int                := 0
  mtreg_/float             := 0.0
  wait-time-ms_/int        := 0
  stale_/bool              := false
  correction-factor_/float := 0.0
  autoranging_/bool        := false
  ema_/Ema                 := ?
  last-mtreg-change_/int   := 0
  bright-count_/int   := 0
  normal-count_/int   := 0
  low-count_/int      := 0

  constructor device/serial.Device --logger/log.Logger=log.default:
    logger_ = logger.with-name "bh1750"
    dev_ = device
    ema_ = Ema --alpha=AUTORANGING-ALPHA
    recalculate-wait-time-ms_
    power-on
    reset
    set-correction-factor CORRECTION-FACTOR-DEFAULT
    set-mode CONTINUOUS-HIGH-RES-MODE
    set-mtreg MTREG-DEFAULT

  /**
  Powers on the device.
  */
  power-on -> none:
    dev_.write #[POWER-ON_]

  /**
  Powers off the device.
  */
  power-off -> none:
    dev_.write #[POWER-OFF_]

  /**
  Resets the device and clears values.
  */
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
    dev_.write #[(0b01000_000 | (mtreg_.to-int >> 5))]   // high bits.
    dev_.write #[(0b011_00000 | (mtreg_.to-int & 0x1F))] // low bits.
    recalculate-wait-time-ms_
    last-mtreg-change_ = Time.monotonic-us
    dev_.write #[mode_]               // Ensures effective immediately.
    stale_ = true

  /**
  Gets the Measurement/Time (integration-time/sensitivity) register. See README.md.

  This value cannot be retrieved from the register, so is returned from the
  class private variable.
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
  Returns ambient light level.

  Takes care of issues such as priming and the specific mode requiring / 2.
  */
  read-lux -> float:
    // If config changed (stale_=true) prime by reading once.
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
    if autoranging_:
      ema_.add lux
      auto-range_

    return lux

  /**
  Recalculates the wait time for a read and stores in class variable.
  */
  recalculate-wait-time-ms_ -> none:
    // Wait for integration to complete.
    base-ms := (mode_ == CONTINUOUS-LOW-RES-MODE or mode_ == ONE-TIME-LOW-RES-MODE) ? 16 : 120

    // Scale time by mtreg_/69.0 (DEFAULT).
    scale/float := mtreg_ / MTREG-DEFAULT
    time-ms/int := (base-ms * scale).ceil.to-int

    // Enforce minimums.
    if time-ms < 16: time-ms = 16
    // Hi-res modes can take up to ~180 ms per datasheet; give them headroom.
    if (base-ms >= 120) and (time-ms < 180): time-ms = 180

    // Store the value.
    wait-time-ms_ = time-ms


  enable-autoranging alpha/float=AUTORANGING-ALPHA -> none:
    assert: 0 < alpha <= 1.0
    logger_.info "Autoranging enabled." --tags={"alpha" : alpha}
    ema_.reset
    ema_.set-alpha alpha
    autoranging_ = true

  disable-autoranging -> none:
    logger_.info "Autoranging disabled."
    ema_.reset
    autoranging_ = false

  read-moving-average -> float:
    return ema_.average

  auto-range_ -> none:
    // Check if holddown is exceeded
    if Time.monotonic-us < (last-mtreg-change_ + AUTORANGING-HOLD-DOWN.in-us):
      //logger_.warn "auto-range_: in holddown"
      return

    if ema_.average == null:
      logger_.error "auto-range_: average is null"
      return

    //if ema_.samples <= 5:
    //  logger_.warn "auto-range_: not enough initial samples."
    //  return

    // Low band: very dark
    if ema_.average <= AUTORANGING-LOW-ON-LUX:
      low-count_ += 1
    else:
      low-count_ = 0


    // Bright band: very bright
    if ema_.average >= AUTORANGING-BRIGHT-ON-LUX:
      bright-count_ += 1
    else:
      bright-count_ = 0

    // Normal band: between low-off and bright-off
    if (ema_.average >= AUTORANGING-LOW-OFF-LUX) and (ema_.average <= AUTORANGING-BRIGHT-OFF-LUX):
      normal-count_ += 1
    else:
      normal-count_ = 0

    // Bright/outdoor band
    if bright-count_ >= AUTORANGING_CONSECUTIVE and mtreg_ != AUTORANGING-BRIGHT-OUTDOOR-MTREG:
      set-mtreg AUTORANGING-BRIGHT-OUTDOOR-MTREG
      logger_.debug "auto-range_: Switched to Bright Outdoor (mtreg=$AUTORANGING-BRIGHT-OUTDOOR-MTREG)"
      // Reset dwell and restart holddown
      bright-count_ = 0
      low-count_ = 0
      normal-count_ = 0
      return

    // Low-light band
    if low-count_ >= AUTORANGING_CONSECUTIVE and mtreg_ != AUTORANGING-LOW-LIGHT-MTREG:
      set-mtreg AUTORANGING-LOW-LIGHT-MTREG
      logger_.debug "auto-range_: Switched to Low Light (mtreg=$AUTORANGING-LOW-LIGHT-MTREG)"
      bright-count_ = 0
      low-count_ = 0
      normal-count_ = 0
      return

    // Back to default/indoor (only when safely in the middle band)
    if normal-count_ >= AUTORANGING_CONSECUTIVE and mtreg_ != AUTORANGING-DEFAULT-GENERAL-MTREG:
      set-mtreg AUTORANGING-DEFAULT-GENERAL-MTREG
      logger_.debug "auto-range_: Switched to Low Light (mtreg=$AUTORANGING-DEFAULT-GENERAL-MTREG)"
      bright-count_ = 0
      low-count_ = 0
      normal-count_ = 0
      return


/*
    // Add hysteresis + dwell so you don’t chatter:
    // Go down a band only if lux > 45_000 for N=5 consecutive samples.
    // Go up a band only if lux < 8 for N=5 consecutive samples.
    // Return to default if 12 ≤ lux ≤ 38_000 for N=5 samples.

    if ema_.average > 45000:  set-mtreg 32.0 // Bright/outdoor
    if ema_.average > limit:  set-mtreg 69.0   // Default/indoor general

    if 12 <= ema_.value <= 38000:  set-mtreg AUTORANGING-DEFAULT-GENERAL
*/
