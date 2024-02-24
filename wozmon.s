; Port of Steve Wozniak's Woz Monitor to ETCa

                .ifdef VARS_IN_BSS
                .bss
VARS:           .space 136
                .endif

                .ifndef VARS
                .err
                .endif

                .set DATA, VARS+8 ; ptr to IN, other vars are at negative offsets

                ; most of these can probably actually be in registers
                ; need to write more code and see how they are used.
                ; Register allocation:
                ; r0-r1 t
                ; r2-r4 t. r2 sometimes holds hex data. r3 sometimes saves r5.
                ; r5    text index (Y). t when text index not needed
                ; r6    value of DATA
                ; r7    return address
                ; When r6 is not a nested return address, it is t
                .set XAM_OFF,  -8 ; 2 bytes
                .set ST_OFF,   -6 ; 2 bytes
                ; There are 3 blank words of space here, which are used in
                ; PRBYTE to save some temporary data to free up registers
                ; for custom ECHO functions.
                .set MODE_OFF, -1 ; 1 byte

                ; defn of _start is needed for MegaIng's annotated output
                .text
                .globl _start
_start:
                .globl WOZ_RESET
WOZ_RESET:      movh    %rh5, 0x7F
                .p2align 1, 0xAE
                call    1f
                .word   DATA
1:              movx    %rx6, [%rx7]
                .ifdef SET_VEC
                call    1f
                .word   DOUBLEFAULT
1:              movx    %rx0, [%rx7]    ; DOUBLEFAULT -> r0
                writecr %rx0, 4         ; DOUBLEFAULT -> INT_PC
                .endif
NOTCR:          movh    %rh1, '_'       ; '_' -> r0
                subh    %rh0, %rh1      ; cmp char =? '_'
                je      BACKSPACE
                subh    %rh0, 1         ; cmp char =? '`' ('`' = '_' + 1)
                je      ESCAPE
                addh    %rh5, 1         ; INY advance text index
                jnn     NEXTCHAR        ; auto ESC if > 127
ESCAPE:         movh    %rh0, '\\'      ; '\' -> r0
                call WOZ_ECHO       ; output it
GETLINE:        movh    %rh0, 10        ; LF -> r0
                call WOZ_ECHO       ; Output it
                movh    %rh5, 1         ; initialize text index
BACKSPACE:      subh    %rh5, 1         ; Back up text index
                jn      GETLINE         ; Beyond start of line, reinit
NEXTCHAR:       movx    %rx1, 0x100     ; 0x0100 -> r1
1:              loadh   %rh0, KBDCR     ; Key ready?
                testh   %rh0, -1
                jz      1b              ; loop until ready
                loadx   %rx0, KBD       ; Load character. Bit 8 should be 0 for press.
                testx   %rx0, %rx1      ; char & 0x0100
                jnz     1b              ; loop if yes.
                ; TODO: once we can get fixes for the keyboard component again,
                ; this hopefully won't be necessary. It explicitly ignores SHIFT events.
                movh    %rh1, 0x15      ; TC keycode for shift
                cmph    %rh0, %rh1      ; key = SHIFT?
                je      NEXTCHAR        ; loop if yes.
                movh    %rh1, %rh5      ; Y -> r1
                addx    %rx1, %rx6      ; IN+Y -> r1
                movh    [%rx1], %rh0    ; add char to text buffer
                call    WOZ_ECHO_0      ; Output character
                cmph    %rh0, 10        ; LF? (TC Keyboards send 5, but ECHO_0 fixed)
                jne     NOTCR           ; no
                movh    %rh5, -1        ; Reset text index
                mov     %rh0, 0xD       ; D -> r0 For XAM mode
                ; 0 = BLOCK XAM, 0xD = XAM, 0xC = STOR (need XAM > STOR)
SETMODE:        movx    %rx1, MODE_OFF  ; MODE -> r1
                addx    %rx1, %rx6      ; DATA+MODE -> r1
                movh    [%rx1], %rh0    ; r0 -> (DATA,MODE)
BLSKIP:         addh    %rh5, 1         ; advance text index
NEXTITEM:       movh    %rh0, %rh5      ; Y -> r0
                addx    %rx0, %rx6      ; DATA+Y -> r0
                movh    %rh0, [%rx0]    ; (IN,Y) -> r0
                cmph    %rh0, 5         ; LF?
                je      GETLINE         ; Yes, done this line
                movh    %rh1, '.'       ; '.' -> r1
                subh    %rh0, %rh1      ; char - '.' -> r0
                jb      BLSKIP          ; skip delimiters
                je      SETMODE         ; Set BLOCK XAM mode
                cmph    %rh0, ':' - '.' ; char - '.' =? ':' - '.'
                je      SETMODE         ; Yes, set STOR mode
                movh    %rh1, 'R' - '.' ; 'R' - '.' -> r1
                cmph    %rh0, %rh1      ; char - '.' =? 'R' - '.'
                je      RUN             ; yes, run user program
                movx    %rx2, 0         ; 0 -> r2 [L,H]
                movh    %rh3, %rh5      ; Y -> r3 to check if changed later
NEXTHEX:        movx    %rx0, %rx5      ; Y -> r0
                addx    %rx0, %rx6      ; IN+Y -> r0
                movh    %rh0, [%rx0]    ; (IN,Y) -> r0
                movh    %rh1, '0'       ; '0' -> r1, note '0' is 0x30
                xorh    %rh0, %rh1      ; map '0'-'9' => 0-9, 'A'-'F' => 0x71-0x76
                cmph    %rh0, 10        ; r0 <? 10 (digit?)
                jb      DIGIT           ; yes.
                movh    %rh1, 0x89      ; map 0x71-0x76 to 0xFA-0xFF
                addh    %rh0, %rh1      ; ``
                cmph    %rh0, -6        ; Hex letter? (-6 = 0xFA)
                jb      NOTHEX          ; No.
DIGIT:          andh    %rh0, 0x0F      ; least significant nibble is hex digit
                addx    %rx2, %rx2
                addx    %rx2, %rx2
                addx    %rx2, %rx2
                addx    %rx2, %rx2      ; r2<<4 -> r2
                orx     %rx2, %rx0      ; r2|r0 -> r2
                addh    %rh5, 1         ; INY advance text index
                jmp     NEXTHEX         ; Check next char for hex
NOTHEX:         cmph    %rh5, %rh3      ; Check if we read any digits
                je      ESCAPE          ; No, generate ESC sequence.
                movx    %rx1, MODE_OFF  ; MODE -> r1
                addx    %rx1, %rx6      ; DATA+MODE -> r1
                movh    %rh0, [%rx1]    ; (DATA,MODE) -> r0
                addx    %rx1, XAM_OFF-MODE_OFF  ; DATA+XAM -> r1
                cmph    %rh0, 0xC       ; STOR?
                jne     NOTSTOR         ; No.
                movx    %rx0, [%rx1]    ; (DATA,ST) -> r0
                movh    [%rx0], %rh2    ; least significant hex digits -> (ST)
                addx    %rx0, 1         ; increment ST
                movx    [%rx1], %rx0    ; ST+1 -> (DATA,ST)
                jmp     NEXTITEM
RUN:            movx    %rx0, XAM_OFF   ; XAM -> r0
                addx    %rx0, %rx6      ; DATA+XAM -> r0
                movx    %rx0, [%rx0]    ; (DATA,XAM) -> r0
                jmp     %rx0            ; Run at current XAM index.
NOTSTOR:        jb      XAMNEXT         ; from cmp (MODE),0xC less => block XAM
                movx    [%rx1], %rx2    ; hex data -> (DATA,XAM)
                addx    %rx1, ST_OFF-XAM_OFF    ; DATA+ST -> r1
                movx    [%rx1], %rx2    ; hex data -> (DATA,ST)
                addx    %rx1, XAM_OFF-ST_OFF    ; DATA+XAM -> r1
                xorx    %rx3, %rx3      ; set Z flag
NXTPRNT:        jnz     PRDATA          ; NZ means no address to print
                movh    %rh0, 10        ; LF -> r0
                call WOZ_ECHO       ; Output it
                addx    %rx1, 1         ; DATA+XAM{H} -> r1
                movh    %rh0, [%rx1]    ; (DATA,XAMH) -> r0
                call    PRBYTE          ; Output it in hex format
                subx    %rx1, 1         ; DATA+XAM -> r1
                movh    %rh0, [%rx1]    ; (DATA,XAM) -> r0
                call    PRBYTE          ; Output it in hex format
                movh    %rh0, ':'       ; ':' -> r0
                call WOZ_ECHO       ; Output it
PRDATA:         movh    %rh0, ' '       ; ' ' -> r0
                call WOZ_ECHO       ; Output it
                movx    %rx0, [%rx1]    ; (DATA,XAM) -> r0
                movh    %rh0, [%rx0]    ; ((DATA,XAM)) -> r0
                call    PRBYTE          ; Output it in hex format
XAMNEXT:        pushh   0xD             ; Reset MODE to XAM mode
                addx    %rx6, 1         ; restore %rx6 after push
                movx    %rx0, [%rx1]    ; (DATA,XAM) -> r0
                cmpx    %rx0, %rx2      ; compare (XAM) to hex data
                jae     NEXTITEM        ; not less, no more data to output
                addx    %rx0, 1         ; (XAM)+1 -> r0
                movx    [%rx1], %rx0    ; (XAM)+1 -> (XAM)
MOD8CHK:        andx    %rx0, 0x07      ; (XAM) mod 8
                jmp     NXTPRNT
PRBYTE:         movh    %rh3, %rh0      ; r0 -> r3 to save around PRHEX
                ; This code MASSIVELY benefits from conditional use of EXOP.
                ; Right-shift %rh0 by 4, by left shifting %rx0 by 4 and then
                ; extracting the upper byte through memory.
                ; The memory that we use is (MODE), which is currently
                ; irrelevant since it will be reset before NEXTITEM.
                addx    %rx0, %rx0
                addx    %rx0, %rx0
                addx    %rx0, %rx0
                addx    %rx0, %rx0
                pushx   %rx0            ; r0<<4 -> (MODE)
                addx    %rx6, 1
                poph    %rh0            ; r0>>4 -> r0
                pushx   %rx7            ; save ret addr around PRHEX
                pushh   %rh3            ; save rh3 around PREHX
                call    PRHEX           ; Output hex digit
                poph    %rh0            ; restore LSD (saved from rh3)
                popx    %rx7            ; restore ret addr
PRHEX:          andh    %rh0, 0x0F      ; mask LSD
                cmph    %rh0, 10        ; digit?
                jb      1f              ; yes, don't add letter offset
                addh    %rh0, 7         ; 'A' - '0' + 0xA
1:              ; This code would benefit from FI or really just any way
                ; of easily adding '0' without needing a register.
                movh    %rh3, '0'
                addh    %rh0, %rh3      ; r0 + '0' -> r0
WOZ_ECHO_0:     cmph    %rh0, 5         ; TCLF?
                jne     WOZ_ECHO        ; no, just echo it
                addh    %rh0, 5         ; TCLF => LF
                ; free registers here: r0,r3,r4
                .globl WOZ_ECHO
WOZ_ECHO:       
                .ifdef CUSTOM_ECHO
                .include "echo.s"
                .text
                .else
                storeh  %rh0, DSP       ; output character
                ret
                .endif

                .ifdef  SET_VEC
DOUBLEFAULT:    .byte 0x0F, 0x11        ; syscall instruction
                .endif
