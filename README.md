# [Super Nintendo Entertainment System](https://en.wikipedia.org/wiki/Super_Nintendo_Entertainment_System) for [MiSTer Platform](https://github.com/MiSTer-devel/Main_MiSTer/wiki)

Written by [srg320](https://github.com/srg320)

## SNES LLAPI Enhanced 1.0.0

### Using a controller

Connect the LLAPI adapter to USER I/O. Leave **Input Options → SNAC** at its factory setting of **No** for automatic LLAPI detection. A single LLAPI controller on either physical port becomes player 1. With both ports populated, port A is player 1 and port B is player 2 before the standard Swap Joysticks option. USB controllers occupy the remaining player slots. With no LLAPI controller detected, the five USB slots keep their original order. Select **SNAC = Yes** for the native SNAC reader.

### Published experimental build, 24 November 2026

The pilot integrates the [LLAPI Enhanced v1.0.0 driver](https://github.com/MiSTer-LLAPI/BlisSTer-LLAPI-Enhanced/releases/tag/v1.0.0) into the [official MiSTer-devel SNES base](https://github.com/MiSTer-devel/SNES_MiSTer/commit/3ac236af3013a4c96bdaf11b5a917a117f25dff6). Its digital controls and player assignment follow the [original LLAPI SNES integration](https://github.com/MiSTer-LLAPI/SNES_MiSTer/blob/a922e326af44459ce9e766fcdecda12f3f0a1939/SNES.sv), including the Saturn-specific Select and shoulder mapping.

- Each LLAPI port has its own driver. Immediate Repoll is enabled on both ports. Port A uses the extended poll acknowledgement window for Gamer-Pro. The driver synchronizes to the SNES vertical blanking signal.
- The core releases the LLAPI pins while the OSD is open. Native SNAC retains exclusive use of USER I/O when selected. The official input and video options remain available.
- The test workflow records the Quartus version, RBF and timing reports. The generate block uses explicit SystemVerilog syntax accepted by Quartus 17.
- Update All installs the pilot under **SNAC+LLAPI Enhanced → Experimental** as `SNES_LLAPI_1.0.0_Timing-Test_20261124.rbf`. SHA-256 is `86c0839265666147a2ea4758e553e0fe81d5c42e810ad3328137e3b98133c581`.
- [Build 45358261125](https://github.com/MiSTer-LLAPI/SNES_MiSTer/actions/runs/45358261125) used Quartus Prime Lite 17.0.2 Build 602. Setup slack was −2.844 ns on clk_mem and −0.451 ns on clk_sys. The worst hold slack was +0.130 ns. The official project identifies the Standard edition. The edition used for the official release binary is unconfirmed.

### Source revision after the pilot

- The OSD again displays **LLAPI enabled core** and **Connect USER I/O port**, followed by the driver version and the default setting. All original menu options keep their order.
- **Down + Start + first LLAPI button** opens the OSD from either connected LLAPI controller. All three buttons must come from the same controller.
- Each port transfers a complete mapped button report and its validity together between the 50 MHz driver clock and the SNES system clock. The core acknowledges the report before the driver-side register can be replaced. Driver enable is synchronized to the 50 MHz clock.
- The USB SaveState button follows its own controller when player slots are reordered. An LLAPI player's directions and a different USB controller's SaveState button can no longer form a shortcut.
- The next FPGA build will collect detailed setup paths for clk_mem and clk_sys. The workflow flags negative slack and retains the reports for inspection.
- Local integration simulation passed 1,305 checks covering player assignment, digital mappings, OSD shortcuts, USB SaveState isolation, transfer between clocks and native SNAC routing against the upstream implementation. The bench injected controller reports. Physical adapter tests and post-fit timing for this revision are pending.

## Features
* Cycle accurate SNES replica.
* Supports LoROM, HiROM, ExHiROM.
* Supports additional chips: DSP-1/2/3/4, ST010, CX4, SDD1, SuperFX(GSU-1/2), SA1, OBC1, SPC7110, S-RTC, BSX, Sufami Turbo.
* MSU-1 Support (1GB max).
* Save states support incl chips SA1, DSP and SuperFX.
* Cheat engine.
* Save/Load Backup RAM.
* Supports mouse.
* Light gun support via Wiimote, mouse or analog stick.
* [SuperFX Turbo and CPU Turbo.](https://github.com/MiSTer-devel/SNES_MiSTer/blob/master/SNES_Turbo.md)

## Installation
* Copy \*.rbf to root of SD card. Put some ROMs (\*.SFC, \*.SMC, \*.BIN) into games\SNES folder.
* Save states: Place [boot1.rom](https://github.com/MiSTer-devel/SNES_MiSTer/raw/master/releases/boot1.rom) in games\SNES folder.
* BSX: Place bsx_bios.rom in games\SNES folder.
