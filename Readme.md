# [Thomson Computers](https://en.wikipedia.org/wiki/Thomson_computers) for [MiSTer Platform](https://github.com/MiSTer-devel/Main_MiSTer/wiki)

## Presentation

This core implements the Thomson SIMIV 8bits computers, developed in France between 1983 and 1989.

These computers were based on a 1MHz MC6809 CPU.

## Mister Hardware
* SDRAM module of any size is needed.
* Keyboard
* Joystick
* Mouse. **All these computers were sold with a light pen.** It is emulated with the mouse input.

# Models

| Model              | Generation |                                                           |
|--------------------|----|-------------------------------------------------------------------|
| TO7                | 1 | First model. BASIC on cartridge                                    |
| TO7/70             | 2 | Sligtly updated TO7, with more RAM. BASIC on cartridge             |
| TO9                | 2 | BASIC and text processor in ROM                                    |
| TO8, TO8D          | 3 | More RAM, more graphics modes. BASIC in ROM                        |
| TO9+               | 3 | More RAM. similar hardware to TO8                                  |
|                    |   |                                                                    |
| MO5, MO5E          | 2 | Low-cost. BASIC IN ROM. Not fully compatible with TO series        |
| MO6, Olivetti PC128| 3 | More RAM. More graphics modes, based on TO8/TO9+ ASIC but compatible with MO5 |

## Featured Options

- Sound, Mouse and Joystick interfaces
- Floppy disk read (internal on TO8/TO9+, add-on module on others). Not working on TO9. No QDD support.
- Tape read (only WAV format supported)
- RAM extensions
  * TO8, TO9+ : 256K BASE + 256K extension
  * MO5, TO7 :  16K extension
  * TO770, TO9 : 64k extension

# Software

## System ROM

The computer model is autodected when loading the system ROM ("Load ROM" menu), it can also be forced with the "Model:" menu.

## Loadable programs

Software was available on :

  - Cartridges ("Load cartridge" menu)

    Cartridges are automatically loaded and should appear on the startup screen.

  - 3"1/2 disks ("Load floppy" menu)

    Can be loaded with DIR, LOAD "name", RUN "name" or with menu "Appel de programmes" on TO8/TO9+.

  - Cassettes ("Load tape" menu)

    Disable the disk interface (Floppy Extension = OFF), then type LOAD then RUN.
    

MO5 software should run on MO6.

TO7, TO770 software should run on TO8, TO9+.

# MiSTer options

* Floppy Ctrl Extension: Can be disabled to allow simpler access to taped programs (with LOAD, RUN).
- Mouse: The mouse can either be used to emulate the light pen, or as a mouse on MO6, TO8, TO9+ (replaces joystick).
* CPU: VHDL or Verilog. The VHDL CPU is more likely to have bugs than the Verilog one.
- Speed: CPU frequency : 1MHz (original), 2MHz, 4MHz. Verilog CPU runs at fixed 1MHz.
* Cursor: Show the light pen current postion on screen
* Bar: Progress bar showing currently accessed floppy track and tape read progress.

# Credits

This core was made possible thanks to the documentation, emulator and games on [dcmoto](https://dcmoto.pages-perso.free.fr/) , the TEO and MAME emulators.
