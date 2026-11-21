# SNES Enhanced
The build uses official SNES_MiSTer revision 3ac236af3013a4c96bdaf11b5a917a117f25dff6, including its MiSTer system interface. The workflow overlays this top-level and the LLAPI 0.5 driver on that revision.

Input Options selects USB, native SNES SNAC, or two-port SNES LLAPI. LLAPI keeps the original player assignment and accepts SNES pads only. USB remains available for unoccupied player slots. Immediate Repoll is selectable in LLAPI mode and defaults to On.

Autofire is off by default. Each player can hold B, A, or Y to repeat the selected button using USB or LLAPI. Native SNAC and lightgun inputs retain their original behaviour.
