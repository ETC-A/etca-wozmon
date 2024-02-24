;; echo.s for Grape1
;; function ECHO takes a character in r0. r3 and r4 are expected to be free.
;; The character MUST be returned in r0.

                .text
                ; Expect Grape1 to be configured with console at 0x80000000.
                ; That's a 32-bit address, but we can't set -mpw=d (it would
                ; break wozmon.s) so we have to do 32-bit arithmetic on our
                ; pointer but then use x in the address operands. We also have
                ; to enable real32 before we can touch the console.
                ; Since we can't set -mpw=d, we also can't use [VAR] addressing
                ; modes, as these would assemble 16-bit displacements.
                ; Even though we know these addresses are in 8-bit regions :(
ECHO:           cmph    %r0, 10            ; printing newline?
                je      ECHO_NL
                movx    %r3, 2
                movx    %address_mode, %r3
                movx    %r3, DSPROW
                movh    %r3, [%r3]
                lead    %r3, [%r3 + 4*%r3] ; one cycle faster than shift+add
                shld    %r3, 4             ; r3 = (DSPROW)*80
                movx    %r4, DSPCOL
                movh    %r4, [%r4]
                addd    %r3, %r4           ; r3 = (DSPROW)*80 + (DSPCOL)
                addd    %r3, 0x80000000    ; r3 += console MMIO offset
                movh    [%r3], %r0         ; output the character
                addh    %r4, 1             ; Increment DSPCOL
                cmph    %r4, 80            ; DSPCOL exceeds length of line?
                jb      1f                 ; No, just save it.
                movx    %r3, DSPROW
                addh    [%r3], 1           ; Yes, increment DSPROW
                movh    %r4, 0             ;   and set DSPCOL to 0
1:              movx    %r3, DSPCOL
                movh    [%r3], %r4         ; update DSPCOL.

                ; TODO: Screen scrolling?

                ; reset address mode to real16.
                movx    %r3, 0
                movx    %address_mode, %r3
                ret

                ; here, we can use exact addresses in memory operands because
                ; we never changed the memory mode away from real16.
ECHO_NL:        addh    [DSPROW], 1
                movh    [DSPCOL], 0
                ret ; this should actually jump to screen scroll

                .bss
DSPCOL:         .space 1
DSPROW:         .space 1
