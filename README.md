# ETCA Wozmon

A port of Steven Wozniak's "Woz Monitor" for the Apple 1 to extension-lite ETCa systems.

## System Requirements

The extensions SAF and BYTE are required.

The system must support a keyboard and console. MMIO addresses for interacting with the keyboard
must be able to identify if a character is pending (KBDCR) and read the next event (KBD).
Key events should be recieved as a 16-bit value: the low byte is the value of the pressed key,
and the high byte is 0 if the key was pressed down and one if it was released.
The MMIO address for the console must simply accept a letter and then print it to the console.
If your system expects to control console terminal emulation in code, there is a mechanism to
override this MMIO console control method with a subroutine of your choice.

These MMIO addresses MUST be in the range 0-31. Support for bigger addresses may be added
in the future, but will make the binary larger.

## Portability

This program is intended to run on any ETCa system supporting both the SAF and BYTE extensions.
Conditional compilation for enhanced extension sets might be added in the future but is not
available at the moment. Wozmon uses all 8 registers and does not initialize a stack.

To port etca-wozmon to a new system, you will have to create an appropriate .cfg file. This repo
contains example config files for AbelianGrape's various ETCa builds that support those
extensions. The config files are regular assembly files which are .included into wozmon.s, see
the config files for commentary.

Nothing should prevent wozmon from linking with a different program if you would like to use
wozmon as a base for starting up a system. If you have a linker script for such a project,
you may want to use the `VARS_IN_BSS` config option, rather than placing the vars yourself.

Since wozmon is intended for extension-lite systems that might not have INT, it does not
interact with interrupts at all by default. The config option `SET_VEC` will tell wozmon
that it needs to set an interrupt vector at startup. For systems supporting the `INT` extension,
this is crucial, as otherwise undefined (and probably bad) behavior will result from a fault.
The interrupt vector used simply triggers a double fault, resetting the system.

If you are linking with wozmon and want it to be the code that runs at startup, then either
ensure that wozmon is at the base of the text segment, or ensure that the first instruction
is a jump to `WOZ_RESET`. If you want to use some of wozmon's code for your own console purposes,
`WOZ_ECHO` is exposed. However exposing `WOZ_GETLINE` is a bit more complicated and not
currently supported.

`wozmon` will run if the system is in 32-bit mode, but still only interacts with addresses in
the 16-bit range.

## Porting to a New System

To port to a new system named `sys`, do the following:

1. Create a directory named `sys/`
2. Create the config file, `sys/sys.cfg`. Copy a given one and read the comments, then
    pick appropriate settings for your system.
3. If you used `VARS_IN_BSS` or otherwise need a linker script, create it at `sys/sys.lds`.
4. If you used `CUSTOM_ECHO`, create `echo.s` and implement `ECHO`.
5. If you need any extra extensions enabled, create `sys/exts` and list them in the
    normal argument format, for example `DW,EXOP,MD`. This should be the first line of the file,
    other lines will be ignored.

## Console Control

By default, the `WOZ_ECHO` function outputs to a console by writing characters to a specified
MMIO address.

This behavior is not acceptable for systems which do not provide hardware for controlling a
console as though it were a TTY output device. In that case, it is necessary to _override_
the functionality of `WOZ_ECHO` with a custom `ECHO` function. To do this, define the symbol
`CUSTOM_ECHO` in the config file, and then provide a file named `echo.s` containing the
implementation. If you are using `VARS_IN_BSS`, it is recommended that any variables used
by echo also be in `.bss`, and that they be placed manually if you are not using `VARS_IN_BSS`.

Wozmon expects that plain linefeeds (0xA) will be interpreted as newline control characters.

Note that when using a custom `ECHO`, `WOZ_ECHO` will alias it. `echo.s` is `.include`d into
`wozmon.s`. Since `WOZ_ECHO` is a global symbol, `ECHO` need not also be global.
