; =====================================================================
;  DR. DRIVING LITE  -  COAL Final Project  (8088 assembly, NASM, .COM)
;  Build :  nasm drdriving.asm -o drdriving.com
;  Only techniques from the course book are used:
;    - BIOS video services (INT 10h: mode 0Dh, write pixel)
;    - hooked keyboard (INT 9) and timer (INT 8) interrupts, PIT, ports
;    - string instructions (STOS, CMPS), stack parameters, tables
; =====================================================================
cpu 8086
bits 16
[org 0x0100]
        jmp start

%macro PUSHV 1
        mov ax, %1
        push ax
%endmacro
; RECT x, y, w, h, colour  -> fillrect (uses AX)
%macro RECT 5
        PUSHV %1
        PUSHV %2
        PUSHV %3
        PUSHV %4
        PUSHV %5
        call fillrect
%endmacro

; rounded rectangle scratch (shared by the renderer)
rr_x: dw 0
rr_y: dw 0
rr_w: dw 0
rr_h: dw 0
rr_col: db 0
rr_r: dw 0
rr_cx: dw 0
rr_cy: dw 0

; ---------------------------------------------------------------- data
bseg:       dw 0                ; segment of the back buffer (frame being drawn)
fseg:       dw 0                ; segment of the front buffer (what is on screen)
oldkb:      dd 0
oldtimer:   dd 0
ticks:      dw 0
lasttick:   dw 0
lastkey:    db 0
keys:       times 128 db 0
rowtab:     times 200 dw 0      ; y * 320
numbuf:     times 8 db 0

; text variables
t_x: dw 0
t_y: dw 0
t_sc: db 1
t_col: db 15
; disc / ring variables
dd_cx: dw 0
dd_cy: dw 0
dd_r: dw 0
dd_ri: dw 0
dd_col: db 0
dd_tab: dw 0
dd_tabi: dw 0
bd_r: dw 0
bd_r2: dw 0
bd_t: dw 0
; line variables
ln_dx: dw 0
ln_dy: dw 0
ln_sx: dw 0
ln_sy: dw 0
ln_err: dw 0
ln_x1: dw 0
ln_y1: dw 0
; bitmap variables
bm_w: db 0
bm_h: db 0
bm_col: db 0
bm_x: dw 0

dtab30: times 31 db 0
dtab28: times 29 db 0
dtab22: times 23 db 0
dtab20: times 21 db 0
dtab47: times 48 db 0
dtab45: times 46 db 0
dtab38: times 39 db 0
dtab36: times 37 db 0
dtab11: times 12 db 0
dtab9:  times 10 db 0
dtab3:  times 4 db 0

; ------------------------------------------------------- interrupt routines
; keyboard: keeps a table of which keys are down (make code = down, break = up)
kbisr:  push ax
        push bx
        in   al, 0x60
        mov  bl, al
        and  bl, 0x7F
        xor  bh, bh
        cmp  bl, 0x60            ; 0xE0 prefix of the arrow keys: ignore
        je   kb_end
        test al, 0x80
        jnz  kb_up
        mov  byte [cs:keys+bx], 1
        mov  [cs:lastkey], bl
        jmp  kb_end
kb_up:  mov  byte [cs:keys+bx], 0
kb_end: mov  al, 0x20
        out  0x20, al
        pop  bx
        pop  ax
        iret

; timer: counts frames (PIT is set to 30 interrupts per second)
timer:  inc  word [cs:ticks]
        push ax
        mov  al, 0x20
        out  0x20, al
        pop  ax
        iret

; ------------------------------------------------------------ start up
start:
        cld
        mov  ax, cs
        add  ax, 0x1000
        mov  [bseg], ax
        add  ax, 0x1000
        mov  [fseg], ax
        call init_tables
        ; save the old vectors and hook INT 9 and INT 8
        xor  ax, ax
        mov  es, ax
        mov  ax, [es:9*4]
        mov  [oldkb], ax
        mov  ax, [es:9*4+2]
        mov  [oldkb+2], ax
        mov  ax, [es:8*4]
        mov  [oldtimer], ax
        mov  ax, [es:8*4+2]
        mov  [oldtimer+2], ax
        cli
        mov  word [es:9*4], kbisr
        mov  [es:9*4+2], cs
        mov  word [es:8*4], timer
        mov  [es:8*4+2], cs
        sti
        ; programmable interval timer: 1193180 / 19886 = 60 Hz
        mov  al, 0x36
        out  0x43, al
        mov  ax, 19886
        out  0x40, al
        mov  al, ah
        out  0x40, al
        ; 320x200, 256 colour graphics + our own colour gradients
        mov  ax, 0x0013
        int  0x10
        call setpal
        call game_init
        mov  ax, [ticks]
        mov  [lasttick], ax

mainloop:
        mov  ax, [ticks]
        cmp  ax, [lasttick]
        je   mainloop            ; wait for the next frame tick
        mov  cx, ax
        sub  cx, [lasttick]
        mov  [lasttick], ax
        cmp  cx, 3
        jbe  ml_steps
        mov  cx, 3               ; never run more than 3 logic steps per frame
ml_steps:
        push cx
        call game_update
        pop  cx
        loop ml_steps
        cmp  byte [quitflag], 0
        jne  quit
        mov  ax, [bseg]
        mov  es, ax
        call game_render
        call present
        jmp  mainloop

quit:
        mov  al, 0x36            ; timer back to 18.2 Hz
        out  0x43, al
        xor  al, al
        out  0x40, al
        out  0x40, al
        xor  ax, ax
        mov  es, ax
        mov  ax, [oldkb]
        mov  bx, [oldkb+2]
        cli
        mov  [es:9*4], ax
        mov  [es:9*4+2], bx
        mov  ax, [oldtimer]
        mov  bx, [oldtimer+2]
        mov  [es:8*4], ax
        mov  [es:8*4+2], bx
        sti
        mov  ax, 0x0003          ; back to text mode
        int  0x10
        mov  ax, 0x4C00
        int  0x21

; ------------------------------------------------ build the work tables
init_tables:
        mov  di, rowtab
        xor  ax, ax
        mov  cx, 200
it1:    mov  [di], ax
        add  di, 2
        add  ax, 320
        loop it1
        mov  si, dtab30
        mov  cx, 30
        call build_disc
        mov  si, dtab28
        mov  cx, 28
        call build_disc
        mov  si, dtab22
        mov  cx, 22
        call build_disc
        mov  si, dtab20
        mov  cx, 20
        call build_disc
        mov  si, dtab47
        mov  cx, 47
        call build_disc
        mov  si, dtab45
        mov  cx, 45
        call build_disc
        mov  si, dtab38
        mov  cx, 38
        call build_disc
        mov  si, dtab36
        mov  cx, 36
        call build_disc
        mov  si, dtab11
        mov  cx, 11
        call build_disc
        mov  si, dtab9
        mov  cx, 9
        call build_disc
        mov  si, dtab3
        mov  cx, 3
        call build_disc
        ret

; build_disc: si = table, cx = radius. table[dy] = half width of the
; circle at distance dy from the centre (x*x + dy*dy <= r*r)
build_disc:
        push ax
        push bx
        push dx
        push di
        mov  [bd_r], cx
        mov  ax, cx
        mul  cx
        mov  [bd_r2], ax
        mov  bx, cx
        xor  di, di
bd_chk: mov  ax, bx
        mul  bx
        mov  [bd_t], ax
        mov  ax, di
        mul  di
        add  ax, [bd_t]
        cmp  ax, [bd_r2]
        jbe  bd_ok
        dec  bx
        jmp  bd_chk
bd_ok:  push si
        add  si, di
        mov  [si], bl
        pop  si
        inc  di
        cmp  di, [bd_r]
        jbe  bd_chk
        pop  di
        pop  dx
        pop  bx
        pop  ax
        ret

; ------------------------------------- show the frame: the finished
; picture is copied to video memory (segment A000) in one go
present:
        push ds
        push es
        mov  ax, [bseg]
        mov  ds, ax
        mov  ax, 0xA000
        mov  es, ax
        xor  si, si
        xor  di, di
        mov  cx, 32000
        rep  movsw
        pop  es
        pop  ds
        ret

; ---------------------------------------------- colour gradients (VGA DAC)
; each entry: first colour, how many, start r,g,b, end r,g,b (0..63)
pal_defs:
        db 16,66,  8,30,58,  50,58,63     ; sky: deep blue at the top, pale at the horizon
        db 84,32,  30,30,34, 12,12,14     ; asphalt (far = light, near = dark)
        db 116,32, 36,36,40, 17,17,19     ; asphalt, second stripe
        db 148,32, 44,44,46, 52,52,54     ; pavement
        db 180,32, 38,38,40, 45,45,47     ; pavement, second stripe
        db 212,32, 63,46,16, 28,9,3       ; orange bonnet
        db 244,2,  34,44,56, 34,44,56     ; distant haze
        db 246,2,  24,32,46, 24,32,46     ; nearer haze
        db 0
rp_s: db 0
rp_n: dw 0
rp_c: times 6 db 0

setpal: push ax
        push bx
        push cx
        push dx
        push si
        push di
        mov  si, pal_defs
pl_def: lodsb
        or   al, al
        jz   pl_end
        mov  [rp_s], al
        lodsb
        xor  ah, ah
        mov  [rp_n], ax
        mov  di, rp_c
        mov  cx, 6
pl_cp:  lodsb
        mov  [di], al
        inc  di
        loop pl_cp
        xor  bx, bx
pl_i:   mov  al, [rp_s]
        add  al, bl
        mov  dx, 0x3C8
        out  dx, al
        xor  di, di
pl_c:   mov  al, [rp_c+di+3]
        sub  al, [rp_c+di]
        cbw
        imul bx
        mov  cx, [rp_n]
        dec  cx
        idiv cx
        add  al, [rp_c+di]
        mov  dx, 0x3C9
        out  dx, al
        inc  di
        cmp  di, 3
        jb   pl_c
        inc  bx
        cmp  bx, [rp_n]
        jb   pl_i
        jmp  pl_def
pl_end: pop  di
        pop  si
        pop  dx
        pop  cx
        pop  bx
        pop  ax
        ret

; ---------------------------------------------------------- primitives
; span: bx = y, cx = x1, dx = x2 (exclusive), al = colour. es = back buffer
span:   push cx
        push dx
        push di
        cmp  bx, 200
        jae  sp_end
        cmp  cx, 0
        jge  sp1
        xor  cx, cx
sp1:    cmp  dx, 320
        jle  sp2
        mov  dx, 320
sp2:    sub  dx, cx
        jle  sp_end
        mov  di, bx
        shl  di, 1
        mov  di, [rowtab+di]
        add  di, cx
        mov  cx, dx
        push ax
        mov  ah, al
        shr  cx, 1
        rep  stosw
        jnc  sp_ev
        stosb
sp_ev:  pop  ax
sp_end: pop  di
        pop  dx
        pop  cx
        ret

; spandith: like span but two colours (al, ah) in a checker pattern
spandith:
        push cx
        push dx
        push di
        push ax
        cmp  bx, 200
        jae  sd_end
        cmp  cx, 0
        jge  sd1
        xor  cx, cx
sd1:    cmp  dx, 320
        jle  sd2
        mov  dx, 320
sd2:    cmp  dx, cx
        jle  sd_end
        mov  di, bx
        shl  di, 1
        mov  di, [rowtab+di]
        test bl, 1
        jz   sd3
        xchg al, ah
sd3:    add  di, cx
        sub  dx, cx
        test cl, 1
        jz   sd4
        mov  [es:di], ah
        inc  di
        dec  dx
        jz   sd_end
sd4:    mov  cx, dx
        shr  cx, 1
        jz   sd5
        rep  stosw
sd5:    test dl, 1
        jz   sd_end
        mov  [es:di], al
sd_end: pop  ax
        pop  di
        pop  dx
        pop  cx
        ret

; fillrect: push x, y, w, h, colour  (stack parameters) - clipped
fillrect:
        push bp
        mov  bp, sp
        push ax
        push bx
        push cx
        push dx
        push si
        push di
        mov  ax, [bp+12]
        mov  bx, [bp+10]
        mov  cx, [bp+8]
        mov  dx, [bp+6]
        cmp  ax, 0
        jge  fr1
        add  cx, ax
        xor  ax, ax
fr1:    mov  si, ax
        add  si, cx
        cmp  si, 320
        jle  fr2
        mov  cx, 320
        sub  cx, ax
fr2:    cmp  cx, 0
        jle  fr_end
        cmp  bx, 0
        jge  fr3
        add  dx, bx
        xor  bx, bx
fr3:    mov  si, bx
        add  si, dx
        cmp  si, 200
        jle  fr4
        mov  dx, 200
        sub  dx, bx
fr4:    cmp  dx, 0
        jle  fr_end
        mov  di, bx
        shl  di, 1
        mov  di, [rowtab+di]
        add  di, ax
        mov  al, [bp+4]
        mov  ah, al
        mov  bx, 320
        sub  bx, cx
fr_row: push cx
        shr  cx, 1
        rep  stosw
        jnc  fr_ev
        stosb
fr_ev:  pop  cx
        add  di, bx
        dec  dx
        jnz  fr_row
fr_end: pop  di
        pop  si
        pop  dx
        pop  cx
        pop  bx
        pop  ax
        pop  bp
        ret  10

; roundrect: push x, y, w, h, colour
; Rounded filled rectangle using the course's disc and fillrect routines.
; Radius is 2 pixels for normal cars, 1 pixel for very small distant cars.
roundrect:
        push bp
        mov  bp, sp
        push ax
        push bx
        push cx
        push dx
        push si
        push di
        mov  ax, [bp+12]
        mov  [rr_x], ax
        mov  ax, [bp+10]
        mov  [rr_y], ax
        mov  ax, [bp+8]
        mov  [rr_w], ax
        mov  ax, [bp+6]
        mov  [rr_h], ax
        mov  al, [bp+4]
        mov  [rr_col], al
        mov  word [rr_r], 1
        cmp  word [rr_w], 8
        jb   rr_small
        cmp  word [rr_h], 6
        jb   rr_small
        mov  word [rr_r], 2
rr_small:
        ; central vertical strip
        mov  ax, [rr_x]
        add  ax, [rr_r]
        push ax
        mov  ax, [rr_y]
        push ax
        mov  ax, [rr_w]
        mov  bx, [rr_r]
        shl  bx, 1
        sub  ax, bx
        push ax
        mov  ax, [rr_h]
        push ax
        xor  ax, ax
        mov  al, [rr_col]
        push ax
        call fillrect
        ; top strip
        mov  ax, [rr_x]
        add  ax, [rr_r]
        push ax
        mov  ax, [rr_y]
        push ax
        mov  ax, [rr_w]
        mov  bx, [rr_r]
        shl  bx, 1
        sub  ax, bx
        push ax
        mov  ax, [rr_r]
        push ax
        xor  ax, ax
        mov  al, [rr_col]
        push ax
        call fillrect
        ; bottom strip
        mov  ax, [rr_x]
        add  ax, [rr_r]
        push ax
        mov  ax, [rr_y]
        add  ax, [rr_h]
        sub  ax, [rr_r]
        push ax
        mov  ax, [rr_w]
        mov  bx, [rr_r]
        shl  bx, 1
        sub  ax, bx
        push ax
        mov  ax, [rr_r]
        push ax
        xor  ax, ax
        mov  al, [rr_col]
        push ax
        call fillrect
        ; four rounded corners
        mov  si, dtab3
        mov  cx, [rr_r]
        mov  bx, [rr_x]
        add  bx, cx
        mov  dx, [rr_y]
        add  dx, cx
        mov  al, [rr_col]
        call drawdisc
        mov  si, dtab3
        mov  cx, [rr_r]
        mov  bx, [rr_x]
        add  bx, [rr_w]
        sub  bx, cx
        mov  dx, [rr_y]
        add  dx, cx
        mov  al, [rr_col]
        call drawdisc
        mov  si, dtab3
        mov  cx, [rr_r]
        mov  bx, [rr_x]
        add  bx, cx
        mov  dx, [rr_y]
        add  dx, [rr_h]
        sub  dx, cx
        mov  al, [rr_col]
        call drawdisc
        mov  si, dtab3
        mov  cx, [rr_r]
        mov  bx, [rr_x]
        add  bx, [rr_w]
        sub  bx, cx
        mov  dx, [rr_y]
        add  dx, [rr_h]
        sub  dx, cx
        mov  al, [rr_col]
        call drawdisc
        pop  di
        pop  si
        pop  dx
        pop  cx
        pop  bx
        pop  ax
        pop  bp
        ret  10

; drawdisc: si = half width table, cx = radius, bx = centre x,
;           dx = centre y, al = colour
drawdisc:
        push ax
        push bx
        push cx
        push dx
        push si
        push di
        mov  [dd_cx], bx
        mov  [dd_cy], dx
        mov  [dd_r], cx
        mov  [dd_col], al
        mov  [dd_tab], si
        mov  di, cx
        neg  di
dd_lp:  mov  bx, [dd_cy]
        add  bx, di
        cmp  bx, 200
        jae  dd_sk
        mov  ax, di
        cmp  ax, 0
        jge  dd_p
        neg  ax
dd_p:   mov  si, [dd_tab]
        add  si, ax
        xor  ax, ax
        mov  al, [si]
        mov  cx, [dd_cx]
        mov  dx, cx
        add  dx, ax
        inc  dx
        sub  cx, ax
        mov  al, [dd_col]
        call span
dd_sk:  inc  di
        cmp  di, [dd_r]
        jle  dd_lp
        pop  di
        pop  si
        pop  dx
        pop  cx
        pop  bx
        pop  ax
        ret

; drawring: si = outer table, [dd_tabi] = inner table, cx = outer radius,
;           [dd_ri] = inner radius, bx,dx = centre, al = colour
drawring:
        push ax
        push bx
        push cx
        push dx
        push si
        push di
        mov  [dd_cx], bx
        mov  [dd_cy], dx
        mov  [dd_r], cx
        mov  [dd_col], al
        mov  [dd_tab], si
        mov  di, cx
        neg  di
dr_lp:  mov  bx, [dd_cy]
        add  bx, di
        cmp  bx, 200
        jae  dr_sk
        mov  ax, di
        cmp  ax, 0
        jge  dr_p
        neg  ax
dr_p:   mov  si, [dd_tab]
        add  si, ax
        mov  cl, [si]            ; outer half width
        xor  ch, ch
        cmp  ax, [dd_ri]
        jbe  dr_two
        ; whole row is ring
        mov  si, [dd_cx]
        mov  dx, si
        add  dx, cx
        inc  dx
        sub  si, cx
        mov  cx, si
        mov  al, [dd_col]
        call span
        jmp  dr_sk
dr_two: mov  si, [dd_tabi]
        add  si, ax
        xor  ah, ah
        mov  al, [si]            ; inner half width
        mov  si, ax              ; si = inner
        mov  ax, [dd_cx]
        push ax
        sub  ax, cx              ; x1 = cx - outer
        mov  dx, [dd_cx]
        sub  dx, si              ; x2 = cx - inner
        push cx
        mov  cx, ax
        mov  al, [dd_col]
        call span
        pop  cx
        pop  ax                  ; ax = centre
        mov  dx, ax
        add  dx, cx
        inc  dx                  ; x2 = cx + outer + 1
        add  ax, si
        inc  ax                  ; x1 = cx + inner + 1
        mov  cx, ax
        mov  al, [dd_col]
        call span
dr_sk:  inc  di
        cmp  di, [dd_r]
        jle  dr_lp
        pop  di
        pop  si
        pop  dx
        pop  cx
        pop  bx
        pop  ax
        ret

; line: push x0, y0, x1, y1, colour  (Bresenham)
line:   push bp
        mov  bp, sp
        push ax
        push bx
        push cx
        push dx
        push si
        push di
        mov  ax, [bp+12]
        mov  bx, [bp+10]
        mov  cx, [bp+8]
        mov  dx, [bp+6]
        mov  si, 1
        mov  di, cx
        sub  di, ax
        jge  ln1
        neg  di
        mov  si, -1
ln1:    mov  [ln_dx], di
        mov  [ln_sx], si
        mov  si, 1
        mov  di, dx
        sub  di, bx
        jge  ln2
        neg  di
        mov  si, -1
ln2:    neg  di
        mov  [ln_dy], di
        mov  [ln_sy], si
        mov  si, [ln_dx]
        add  si, di
        mov  [ln_err], si
        mov  [ln_x1], cx
        mov  [ln_y1], dx
ln_lp:  cmp  ax, 320
        jae  ln_np
        cmp  bx, 200
        jae  ln_np
        mov  di, bx
        shl  di, 1
        mov  di, [rowtab+di]
        add  di, ax
        mov  cl, [bp+4]
        mov  [es:di], cl
ln_np:  cmp  ax, [ln_x1]
        jne  ln_c
        cmp  bx, [ln_y1]
        je   ln_end
ln_c:   mov  si, [ln_err]
        shl  si, 1
        cmp  si, [ln_dy]
        jl   ln_nx
        mov  di, [ln_dy]
        add  [ln_err], di
        add  ax, [ln_sx]
ln_nx:  cmp  si, [ln_dx]
        jg   ln_ny
        mov  di, [ln_dx]
        add  [ln_err], di
        add  bx, [ln_sy]
ln_ny:  jmp  ln_lp
ln_end: pop  di
        pop  si
        pop  dx
        pop  cx
        pop  bx
        pop  ax
        pop  bp
        ret  10

; drawbmp: si = bitmap (width, height, rows as words, bit 15 = left),
;          bx = x, dx = y, al = colour
drawbmp:
        push ax
        push bx
        push cx
        push dx
        push si
        push di
        mov  [bm_col], al
        mov  [bm_x], bx
        lodsb
        mov  [bm_w], al
        lodsb
        mov  [bm_h], al
bm_row: cmp  dx, 200
        jae  bm_sk
        lodsw
        mov  di, dx
        shl  di, 1
        mov  di, [rowtab+di]
        add  di, [bm_x]
        mov  cl, [bm_w]
        xor  ch, ch
        mov  bl, [bm_col]
bm_px:  shl  ax, 1
        jnc  bm_no
        mov  [es:di], bl
bm_no:  inc  di
        loop bm_px
        jmp  bm_nx
bm_sk:  add  si, 2
bm_nx:  inc  dx
        dec  byte [bm_h]
        jnz  bm_row
        pop  di
        pop  si
        pop  dx
        pop  cx
        pop  bx
        pop  ax
        ret

; ------------------------------------------------------------- text
; num2str: ax = number, cl = minimum digits  ->  si = zero ended string
num2str:
        push ax
        push bx
        push cx
        push dx
        push di
        xor  ch, ch
        mov  bx, 10
        xor  di, di
n2a:    xor  dx, dx
        div  bx
        add  dl, '0'
        push dx
        inc  di
        or   ax, ax
        jnz  n2a
n2b:    cmp  di, cx
        jae  n2c
        mov  dx, '0'
        push dx
        inc  di
        jmp  n2b
n2c:    mov  bx, numbuf
n2d:    pop  dx
        mov  [bx], dl
        inc  bx
        dec  di
        jnz  n2d
        mov  byte [bx], 0
        pop  di
        pop  dx
        pop  cx
        pop  bx
        pop  ax
        mov  si, numbuf
        ret

; putch: al = character, draws at [t_x],[t_y] with [t_sc],[t_col]
putch:  push ax
        push bx
        push cx
        push dx
        push si
        push di
        sub  al, 32
        jb   pc_end
        cmp  al, 59
        jae  pc_end
        xor  ah, ah
        mov  bx, ax
        mov  cl, 3
        shl  bx, cl
        sub  bx, ax
        add  bx, fontdata
        mov  si, bx
        cmp  byte [t_sc], 1
        jne  pc_big
        mov  dx, [t_y]
        mov  bx, 7
pc_fr:  cmp  dx, 200
        jae  pc_fs
        lodsb
        mov  ah, al
        mov  cl, 3
        shl  ah, cl
        mov  di, dx
        shl  di, 1
        mov  di, [rowtab+di]
        add  di, [t_x]
        mov  cx, 5
        mov  al, [t_col]
pc_fp:  shl  ah, 1
        jnc  pc_fn
        mov  [es:di], al
pc_fn:  inc  di
        loop pc_fp
        jmp  pc_fx
pc_fs:  inc  si
pc_fx:  inc  dx
        dec  bx
        jnz  pc_fr
        jmp  pc_end
pc_big: xor  bx, bx
pc_br:  lodsb
        mov  dl, al
        mov  cl, 3
        shl  dl, cl
        xor  cx, cx
pc_bc:  shl  dl, 1
        jnc  pc_bn
        mov  ax, cx
        mul  byte [t_sc]
        add  ax, [t_x]
        push ax
        mov  ax, bx
        mul  byte [t_sc]
        add  ax, [t_y]
        push ax
        xor  ah, ah
        mov  al, [t_sc]
        push ax
        push ax
        mov  al, [t_col]
        push ax
        call fillrect
pc_bn:  inc  cx
        cmp  cx, 5
        jb   pc_bc
        inc  bx
        cmp  bx, 7
        jb   pc_br
pc_end: pop  di
        pop  si
        pop  dx
        pop  cx
        pop  bx
        pop  ax
        ret

; puts: si = string, bx = x, dx = y, al = colour, ah = scale.
; On return [t_x] is the x position after the last character.
puts:   push ax
        push bx
        push cx
        push dx
        push si
        mov  [t_col], al
        mov  [t_sc], ah
        mov  [t_x], bx
        mov  [t_y], dx
pt_nx:  lodsb
        or   al, al
        jz   pt_end
        call putch
        xor  ah, ah
        mov  al, [t_sc]
        mov  bx, 6
        mul  bx
        add  [t_x], ax
        jmp  pt_nx
pt_end: pop  si
        pop  dx
        pop  cx
        pop  bx
        pop  ax
        ret

; puts_sh: same, with a black shadow one pixel down and right
puts_sh:
        push ax
        push bx
        push dx
        inc  bx
        inc  dx
        mov  al, 0
        call puts
        pop  dx
        pop  bx
        pop  ax
        call puts
        ret

; =====================================================================
;                          GAME  VARIABLES
; =====================================================================
NC      equ 10                  ; traffic cars
PERIOD  equ 15680               ; length of the traffic ring (245 m, 1 m = 64 units)
ZLOW    equ 384

quitflag: db 0
state:    db 0                  ; 0 menu, 1 highway, 2 parking, 3 message
scene:    db 1                  ; which world is drawn: 1 highway, 2 parking
spd:      dw 0                  ; speed, 1/16 km/h, negative = reversing
vmax:     dw 2240
accsh:    db 7
brk:      dw 24
revacc:   dw 3
negrev:   dw -128
odo:      dw 0                  ; distance driven, 1/64 m
acc27:    dw 0
advp:     dw 0                  ; world movement of this frame (1/64 m)
camu:     dw 64                 ; camera sideways position, 64 per lane
lane:     dw 1
pl:       db 0
pr:       db 0
wheel:    dw 0                  ; steering wheel angle -4..4
score:    dw 0
lastm:    dw 0
timeleft: dw 0
timetotal:dw 1
fuel:     dw 0
fuelmax:  dw 1
crash:    dw 0
endtimer: dw 0
msg_t:    dw 0
msg_c:    db 12
px:       dw 100                ; parking: sideways position
pz:       dw 0                  ; parking: front bumper position (1/64 m)
pcool:    dw 0
sensor:   dw 99                 ; parking sensor, decimetres
hitflag:  db 0
par:      db 0
oldpz:    dw 0
oldpx:    dw 0

car_z:    times NC dw 0
car_lane: dw 1,0,2,2,1,0,0,1,2,1
car_col:  dw 9,3,15,4,14,2,3,9,4,15
car_off:  dw 0,2240,2240,4480,6720,6720,8960,11200,11200,13440

; parking obstacles: x0, x1, z0, z1
pobst:  dw -33,1,595,890         ; parked car on the left
        dw 127,161,595,890       ; parked car on the right
        dw 16,24,550,602         ; cone, left
        dw 104,112,550,602       ; cone, right
        dw -60,190,998,1024      ; wheel stop at the back of the bay

; =====================================================================
;                              GAME LOGIC
; =====================================================================
game_init:
        call menu_reset
        ret

menu_reset:
        mov  byte [state], 0
        mov  byte [scene], 1
        mov  word [spd], 1100
        mov  word [odo], 0
        mov  word [camu], 64
        mov  word [wheel], 0
        mov  word [score], 0
        mov  word [timeleft], 4800
        mov  word [timetotal], 4800
        mov  word [fuel], 30000
        mov  word [fuelmax], 36000
        mov  word [crash], 0
        call cars_init
        mov  byte [lastkey], 0
        ret

cars_init:
        mov  cx, NC
        xor  si, si
ci1:    mov  ax, [car_off+si]
        add  ax, ZLOW+1920
        mov  [car_z+si], ax
        add  si, 2
        loop ci1
        ret

game_update:
        mov  al, [state]
        cmp  al, 1
        je   u_hwy
        cmp  al, 2
        je   u_park
        cmp  al, 3
        je   u_end
        jmp  upd_menu
u_hwy:  jmp  upd_hwy
u_park: jmp  upd_park
u_end:  jmp  upd_end

; ---------------------------------------------------------------- menu
upd_menu:
        mov  word [advp], 15
        mov  ax, [odo]
        add  ax, 15
        mov  [odo], ax
        call traffic_update
        mov  al, [lastkey]
        mov  byte [lastkey], 0
        cmp  al, 2
        je   hwy_start
        cmp  al, 3
        je   park_start
        cmp  al, 1
        jne  um_x
        mov  byte [quitflag], 1
um_x:   ret

; ------------------------------------------------------- common physics
; phys: Up accelerates (fast at first, slower near top speed), Space brakes
; gradually, Down reverses only when the car stands still, otherwise coasts
phys:   mov  ax, [spd]
        cmp  byte [keys+0x39], 0
        jne  ph_brake
        cmp  byte [keys+0x48], 0
        jne  ph_up
        cmp  byte [keys+0x50], 0
        jne  ph_down
        jmp  ph_coast
ph_brake:
        cmp  ax, 0
        jg   ph_b1
        add  ax, [brk]
        jle  ph_done
        xor  ax, ax
        jmp  ph_done
ph_b1:  sub  ax, [brk]
        jge  ph_done
        xor  ax, ax
        jmp  ph_done
ph_up:  cmp  ax, 0
        jl   ph_brake
        mov  bx, [vmax]
        sub  bx, ax
        mov  cl, [accsh]
        shr  bx, cl
        inc  bx
        add  ax, bx
        cmp  ax, [vmax]
        jle  ph_done
        mov  ax, [vmax]
        jmp  ph_done
ph_down:
        cmp  ax, 0
        jg   ph_coast
        sub  ax, [revacc]
        cmp  ax, [negrev]
        jge  ph_done
        mov  ax, [negrev]
        jmp  ph_done
ph_coast:
        cmp  ax, 0
        jg   ph_c1
        jl   ph_c2
        jmp  ph_done
ph_c1:  mov  bx, ax
        mov  cl, 9
        shr  bx, cl
        inc  bx
        sub  ax, bx
        jge  ph_done
        xor  ax, ax
        jmp  ph_done
ph_c2:  add  ax, 2
        jle  ph_done
        xor  ax, ax
ph_done:
        mov  [spd], ax
        ret

; calc_adv: speed (1/16 km/h) -> movement per frame in 1/64 m  (divide by 27)
calc_adv:
        mov  ax, [spd]
        xor  cx, cx
        cmp  ax, 0
        jge  ca1
        neg  ax
        mov  cx, 1
ca1:    add  ax, [acc27]
        xor  dx, dx
        mov  bx, 54
        div  bx
        mov  [acc27], dx
        or   cx, cx
        jz   ca2
        neg  ax
ca2:    mov  [advp], ax
        ret

; time and fuel: fuel burns faster the faster you drive
timefuel:
        cmp  word [timeleft], 0
        je   tf1
        dec  word [timeleft]
tf1:    mov  ax, [spd]
        cmp  ax, 0
        jge  tf2
        neg  ax
tf2:    mov  cl, 7
        shr  ax, cl
        add  ax, 2
        mov  bx, [fuel]
        sub  bx, ax
        jae  tf3
        xor  bx, bx
tf3:    mov  [fuel], bx
        cmp  word [crash], 0
        je   tf4
        dec  word [crash]
tf4:    ret

; --------------------------------------------------------------- highway
hwy_start:
        mov  byte [state], 1
        mov  byte [scene], 1
        mov  word [spd], 0
        mov  word [vmax], 2240
        mov  byte [accsh], 7
        mov  word [brk], 24
        mov  word [revacc], 3
        mov  word [negrev], -128
        mov  word [odo], 0
        mov  word [acc27], 0
        mov  word [camu], 64
        mov  word [lane], 1
        mov  word [wheel], 0
        mov  word [score], 0
        mov  word [lastm], 0
        mov  word [timeleft], 4800
        mov  word [timetotal], 4800
        mov  word [fuel], 36000
        mov  word [fuelmax], 36000
        mov  word [crash], 0
        mov  al, [keys+0x4B]
        mov  [pl], al
        mov  al, [keys+0x4D]
        mov  [pr], al
        call cars_init
        mov  byte [lastkey], 0
        ret

upd_hwy:
        cmp  byte [keys+1], 0
        je   uh0
        call menu_reset
        ret
uh0:    call lane_input
        call phys
        call calc_adv
        mov  ax, [odo]
        mov  bx, [advp]
        cmp  bx, 0
        jge  uh_f
        add  ax, bx              ; reversing: never go below the start line
        jc   uh1
        xor  ax, ax
        mov  word [spd], 0
        mov  word [advp], 0
        jmp  uh1
uh_f:   add  ax, bx
uh1:    mov  [odo], ax
        mov  cl, 6
        shr  ax, cl              ; metres
        mov  bx, [lastm]
        cmp  ax, bx
        jbe  uh2
        sub  ax, bx
        mov  dx, 10
        mul  dx
        add  [score], ax
        mov  ax, [odo]
        mov  cl, 6
        shr  ax, cl
        mov  [lastm], ax
uh2:    call traffic_update
        call hwy_collide
        call timefuel
        cmp  word [odo], 64000
        jae  uh_win
        cmp  word [timeleft], 0
        je   uh_time
        cmp  word [fuel], 0
        je   uh_fuel
        ret
uh_win: mov  word [msg_t], s_win
        mov  byte [msg_c], 10
        jmp  end_level
uh_time:
        mov  word [msg_t], s_time
        mov  byte [msg_c], 12
        jmp  end_level
uh_fuel:
        mov  word [msg_t], s_fuel
        mov  byte [msg_c], 12
end_level:
        mov  byte [state], 3
        mov  word [endtimer], 72
        mov  byte [lastkey], 0
        ret

; Left / Right arrow: one lane per key press; the camera glides to the lane
lane_input:
        mov  al, [keys+0x4B]
        mov  ah, [pl]
        mov  [pl], al
        cmp  al, ah
        jbe  li1
        cmp  word [lane], 0
        je   li1
        dec  word [lane]
li1:    mov  al, [keys+0x4D]
        mov  ah, [pr]
        mov  [pr], al
        cmp  al, ah
        jbe  li2
        cmp  word [lane], 2
        je   li2
        inc  word [lane]
li2:    mov  ax, [lane]
        mov  cl, 6
        shl  ax, cl              ; target = lane * 64
        mov  bx, [camu]
        mov  dx, ax
        sub  dx, bx              ; remaining distance
        mov  cl, 4
        sar  dx, cl
        cmp  dx, 4
        jle  li3
        mov  dx, 4
li3:    cmp  dx, -4
        jge  li4
        mov  dx, -4
li4:    mov  [wheel], dx
        cmp  bx, ax
        jl   li_r
        jg   li_l
        ret
li_r:   add  bx, 4
        cmp  bx, ax
        jle  li5
        mov  bx, ax
        jmp  li5
li_l:   sub  bx, 4
        cmp  bx, ax
        jge  li5
        mov  bx, ax
li5:    mov  [camu], bx
        ret

; traffic: every car keeps a fixed place on a ring of cars driving at 40 km/h
traffic_update:
        mov  cx, NC
        xor  si, si
tu1:    mov  ax, [car_z+si]
        sub  ax, [advp]
        add  ax, 12
        cmp  ax, ZLOW
        jge  tu2
        add  ax, PERIOD
tu2:    cmp  ax, ZLOW+PERIOD
        jl   tu3
        sub  ax, PERIOD
tu3:    mov  [car_z+si], ax
        add  si, 2
        loop tu1
        ret

hwy_collide:
        cmp  word [advp], 12
        jle  hc_end
        mov  cx, NC
        xor  si, si
hc1:    mov  ax, [car_z+si]
        cmp  ax, 512
        jl   hc_nx
        cmp  ax, 1600
        jg   hc_nx
        mov  bx, [car_lane+si]
        push cx
        mov  cl, 6
        shl  bx, cl
        pop  cx
        mov  ax, [camu]
        sub  ax, bx
        jge  hc2
        neg  ax
hc2:    cmp  ax, 56
        jge  hc_nx
        mov  word [spd], 0
        mov  word [crash], 90
        mov  ax, [score]
        sub  ax, 50
        jae  hc3
        xor  ax, ax
hc3:    mov  [score], ax
        ret
hc_nx:  add  si, 2
        loop hc1
hc_end: ret

; --------------------------------------------------------------- parking
park_start:
        mov  byte [state], 2
        mov  byte [scene], 2
        mov  word [spd], 0
        mov  word [vmax], 176
        mov  byte [accsh], 5
        mov  word [brk], 6
        mov  word [revacc], 2
        mov  word [negrev], -80
        mov  word [acc27], 0
        mov  word [px], 100
        mov  word [pz], 0
        mov  word [wheel], 0
        mov  word [score], 1000
        mov  word [timeleft], 5400
        mov  word [timetotal], 5400
        mov  word [fuel], 12000
        mov  word [fuelmax], 12000
        mov  word [crash], 0
        mov  word [pcool], 0
        mov  word [sensor], 99
        mov  byte [lastkey], 0
        ret

upd_park:
        cmp  byte [keys+1], 0
        je   up0
        call menu_reset
        ret
up0:    call phys
        call calc_adv
        mov  byte [hitflag], 0
        ; steering wheel follows the arrow keys
        xor  bx, bx
        cmp  byte [keys+0x4B], 0
        je   up1
        mov  bx, -4
up1:    cmp  byte [keys+0x4D], 0
        je   up2
        mov  bx, 4
up2:    mov  ax, [wheel]
        cmp  ax, bx
        jl   up3
        jg   up4
        jmp  up5
up3:    inc  ax
        jmp  up5
up4:    dec  ax
up5:    mov  [wheel], ax
        ; forward / backward movement
        mov  ax, [pz]
        mov  [oldpz], ax
        add  ax, [advp]
        cmp  ax, -320
        jge  up6
        mov  ax, -320
        mov  word [spd], 0
up6:    mov  [pz], ax
        call park_ovl
        jnc  up7
        mov  ax, [oldpz]
        mov  [pz], ax
        mov  word [spd], 0
        mov  byte [hitflag], 1
up7:    ; sideways movement only while the car is moving
        cmp  word [spd], 0
        je   up10
        xor  byte [par], 1
        jz   up10                ; steer every second frame
        mov  ax, [px]
        mov  [oldpx], ax
        cmp  byte [keys+0x4B], 0
        je   up8
        dec  ax
up8:    cmp  byte [keys+0x4D], 0
        je   up9
        inc  ax
up9:    cmp  ax, 0
        jge  up9a
        xor  ax, ax
up9a:   cmp  ax, 128
        jle  up9b
        mov  ax, 128
up9b:   mov  [px], ax
        call park_ovl
        jnc  up10
        mov  ax, [oldpx]
        mov  [px], ax
        mov  byte [hitflag], 1
up10:   ; touching something costs points (not more than once in a while)
        cmp  word [pcool], 0
        je   up11
        dec  word [pcool]
up11:   cmp  byte [hitflag], 0
        je   up12
        cmp  word [pcool], 0
        jne  up12
        mov  ax, [score]
        sub  ax, 50
        jae  up11a
        xor  ax, ax
up11a:  mov  [score], ax
        mov  word [pcool], 50
        mov  word [crash], 90
up12:   call park_sensor
        call timefuel
        ; parked: stopped completely inside the bay without touching anything
        cmp  word [spd], 0
        jne  up13
        cmp  word [pz], 858
        jl   up13
        cmp  word [pz], 997
        jg   up13
        cmp  word [px], 41
        jl   up13
        cmp  word [px], 87
        jg   up13
        add  word [score], 500
        mov  word [msg_t], s_park
        mov  byte [msg_c], 10
        jmp  end_level
up13:   cmp  word [timeleft], 0
        je   up_time
        cmp  word [fuel], 0
        je   up_fuel
        ret
up_time:
        mov  word [msg_t], s_time
        mov  byte [msg_c], 12
        jmp  end_level
up_fuel:
        mov  word [msg_t], s_fuel
        mov  byte [msg_c], 12
        jmp  end_level

; park_ovl: carry set when the car box overlaps an obstacle
park_ovl:
        push si
        push cx
        mov  si, pobst
        mov  cx, 5
po1:    mov  ax, [px]
        add  ax, 17
        cmp  ax, [si]
        jle  po_n
        mov  ax, [px]
        sub  ax, 17
        cmp  ax, [si+2]
        jge  po_n
        mov  ax, [pz]
        cmp  ax, [si+4]
        jle  po_n
        sub  ax, 282
        cmp  ax, [si+6]
        jge  po_n
        pop  cx
        pop  si
        stc
        ret
po_n:   add  si, 8
        loop po1
        pop  cx
        pop  si
        clc
        ret

; park_sensor: gap to the closest obstacle in decimetres (0 = touching)
park_sensor:
        mov  si, pobst
        mov  cx, 5
        mov  word [sensor], 99
ps1:    ; gap in x
        mov  ax, [si]
        mov  bx, [px]
        add  bx, 17
        sub  ax, bx              ; x0 - (px+17)
        mov  dx, [px]
        sub  dx, 17
        sub  dx, [si+2]          ; (px-17) - x1
        cmp  dx, ax
        jle  ps2
        mov  ax, dx
ps2:    cmp  ax, 0
        jge  ps3
        xor  ax, ax
ps3:    mov  bx, 35
        mul  bx
        mov  bx, ax
        push cx
        mov  cl, 6
        shr  bx, cl              ; gap x in dm
        pop  cx
        ; gap in z
        mov  ax, [si+4]
        sub  ax, [pz]            ; z0 - pz
        mov  dx, [pz]
        sub  dx, 282
        sub  dx, [si+6]          ; (pz-282) - z1
        cmp  dx, ax
        jle  ps4
        mov  ax, dx
ps4:    cmp  ax, 0
        jge  ps5
        xor  ax, ax
ps5:    mov  dx, 10
        mul  dx
        push cx
        mov  cl, 6
        shr  ax, cl
        pop  cx
        cmp  ax, bx
        jae  ps6
        mov  ax, bx
ps6:    cmp  ax, [sensor]
        jae  ps7
        mov  [sensor], ax
ps7:    add  si, 8
        loop ps1
        ret

; ----------------------------------------------------- message screen
upd_end:
        cmp  word [endtimer], 0
        je   ue1
        dec  word [endtimer]
        ret
ue1:    mov  al, [lastkey]
        cmp  al, 0x1C
        je   ue2
        cmp  al, 0x39
        je   ue2
        cmp  al, 0x01
        je   ue2
        ret
ue2:    call menu_reset
        ret

s_win:  db "LEVEL COMPLETE",0
s_time: db "TIME IS UP",0
s_fuel: db "OUT OF FUEL",0
s_park: db "PARKED PERFECTLY",0

; =====================================================================
;                              RENDERING
; =====================================================================
g_y:  dw 0
g_k:  dw 0
g_lw: dw 0
g_cx: dw 0
g_hw: dw 0
g_ew: dw 0
g_zw: dw 0
g_xl: dw 0
g_xr: dw 0
g_dw: dw 0
g_kk: dw 0
b_off: dw 0
b_base: dw 0
b_j:  dw 0
b_z:  dw 0
b_k:  dw 0
b_lw: dw 0
b_yb: dw 0
b_cx: dw 0
b_idx: dw 0
b_side: dw 0
b_x0: dw 0
b_bw: dw 0
b_h:  dw 0
b_ph: dw 0
b_fp: dw 0
b_wh: dw 0
b_pitch: dw 0
b_ww: dw 0
b_wy: dw 0
b_f:  dw 0
b_c:  dw 0
dc_cx: dw 0
dc_yb: dw 0
dc_lw: dw 0
dc_col: dw 0
c_W:  dw 0
c_H:  dw 0
c_sh: dw 0
c_bh: dw 0
c_ch: dw 0
c_x0: dw 0
c_ytb: dw 0
c_xc: dw 0
c_wc: dw 0
c_yc: dw 0
c_t:  dw 0
tdone: times NC dw 0
t_cnt: dw 0
pp_x: dw 0
pp_z: dw 0
sc_t: dw 0

bld_ht:  db 7,10,8,12,9,6,11,8
bld_col: db 7,6,3,7,8,6,7,3
sky_h:   db 10,16,8,20,12,9,18,11,15,7,19,13,9,17,10,14

; 1-bit pictures: width, height, one word per row (bit 15 = leftmost)
bmp_lane:  db 7,11
           dw 0x1000,0x3800,0x7C00,0xFE00,0x1000,0x1000,0x1000,0x1000,0x1000,0x1000,0x1000
bmp_larr:  db 13,9
           dw 0x0400,0x0C00,0x1C00,0x3FF8,0x7FF8,0x3FF8,0x1C00,0x0C00,0x0400
bmp_rarr:  db 13,9
           dw 0x0100,0x0180,0x01C0,0x1FF8,0x3FF8,0x1FF8,0x01C0,0x0180,0x0100
bmp_haz:   db 13,11
           dw 0x0200,0x0500,0x0500,0x0880,0x0880,0x1040,0x1040,0x2020,0x2020,0x4010,0xFFF8
bmp_pump:  db 7,9
           dw 0x7C00,0x4400,0x7C00,0x7C00,0x7C00,0x7C00,0x7C00,0x7C00,0xFE00

s_dist:  db "DIST",0
s_of:    db " / 1000 M",0
s_score: db "SCORE",0
s_time_l: db "TIME",0
s_kmh:   db "KM/H",0
s_40:    db "40",0
s_80:    db "80",0
s_120:   db "120",0
s_160:   db "160",0
s_e:     db "E",0
s_f:     db "F",0
s_p:     db "P",0
s_s:     db "S",0
s_d:     db "D",0
s_r:     db "R",0
s_sens:  db "SENSOR",0
s_m:     db " M",0
s_dot:   db ".",0
s_ban:   db "PARKING * LEVEL 2",0
s_crash: db "CRASH  -50",0
s_touch: db "TOUCH  -50",0

game_render:
        cmp  byte [scene], 2
        je   gr_p
        call render_highway
        jmp  gr_c
gr_p:   call render_parking
gr_c:   call draw_cockpit
        call draw_hud
        mov  al, [state]
        cmp  al, 0
        je   gr_menu
        cmp  al, 3
        je   gr_end
        ; crash message
        cmp  word [crash], 0
        je   gr_x
        test byte [crash], 8
        jz   gr_x
        mov  si, s_crash
        cmp  byte [scene], 2
        jne  gr_c2
        mov  si, s_touch
gr_c2:  mov  bx, 100
        mov  dx, 66
        mov  al, 12
        mov  ah, 2
        call puts_sh
gr_x:   ret
gr_menu: call draw_menu
        ret
gr_end: call draw_endpanel
        ret

; ------------------------------------------------------------ sky
; skyband: bx = first row, cx = last row + 1, al/ah = the two colours
skyband:
        push bx
        push cx
        push dx
        push si
        mov  si, cx
sb1:    xor  cx, cx
        mov  dx, 320
        call spandith
        inc  bx
        cmp  bx, si
        jb   sb1
        pop  si
        pop  dx
        pop  cx
        pop  bx
        ret

; skyrows: smooth sky gradient for the rows 0 .. cx-1
skyrows:
        push ax
        push bx
        push cx
        push dx
        push si
        mov  si, cx
        xor  bx, bx
sr1:    mov  ax, bx
        shl  ax, 1
        add  ax, bx
        shr  ax, 1
        shr  ax, 1               ; y * 3 / 4
        add  ax, 16
        xor  cx, cx
        mov  dx, 320
        call span
        inc  bx
        cmp  bx, si
        jb   sr1
        pop  si
        pop  dx
        pop  cx
        pop  bx
        pop  ax
        ret

draw_sky_hwy:
        mov  cx, 88
        call skyrows
        ; clouds
        RECT 56,24,26,4,15
        RECT 46,28,50,5,15
        RECT 52,33,36,2,11
        RECT 214,38,22,4,15
        RECT 204,42,44,4,15
        ; far away skyline
        xor  si, si
sk1:    xor  ax, ax
        mov  al, [sky_h+si]
        mov  [c_t], ax
        mov  ax, si
        mov  cl, 4
        mov  bx, 20
        mul  bx
        mov  [c_xc], ax
        mov  ax, 88
        sub  ax, [c_t]
        mov  [c_yc], ax
        mov  bx, 244
        test si, 2
        jz   sk2
        mov  bx, 246
sk2:    mov  [c_wc], bx
        RECT [c_xc],[c_yc],20,[c_t],[c_wc]
        inc  si
        cmp  si, 16
        jb   sk1
        ret

; --------------------------------------------------- highway ground
draw_ground_hwy:
        mov  word [g_y], 88
gh_row: mov  ax, [g_y]
        sub  ax, 87
        mov  [g_k], ax
        add  ax, 7
        mov  [g_lw], ax
        mov  bx, [g_k]
        cmp  bx, 2
        jae  gh1
        mov  bx, 2
gh1:    mov  dx, 1
        mov  ax, 0x5E00          ; 89600 = 1400 m * 64
        div  bx
        add  ax, [odo]
        mov  [g_zw], ax
        mov  ax, [camu]
        mov  bx, [g_lw]
        mul  bx
        mov  cl, 6
        shr  ax, cl
        mov  bx, 160
        add  bx, [g_lw]
        sub  bx, ax
        mov  [g_cx], bx
        mov  ax, [g_lw]
        shr  ax, 1
        add  ax, [g_lw]
        mov  [g_hw], ax
        mov  ax, [g_lw]
        mov  cl, 5
        shr  ax, cl
        inc  ax
        mov  [g_ew], ax
        mov  ax, [g_cx]
        sub  ax, [g_hw]
        mov  [g_xl], ax
        mov  ax, [g_cx]
        add  ax, [g_hw]
        mov  [g_xr], ax
        mov  bx, [g_y]
        mov  ax, [g_k]
        shr  ax, 1
        cmp  ax, 31
        jbe  gh2a
        mov  ax, 31
gh2a:   mov  [g_kk], ax
        ; pavement on both sides (colour gets brighter towards the car)
        add  ax, 148
        test word [g_zw], 512
        jz   gh2
        add  ax, 32
gh2:    mov  ah, al
        xor  cx, cx
        mov  dx, [g_xl]
        call spandith
        mov  cx, [g_xr]
        mov  dx, 320
        call spandith
        ; asphalt
        mov  ax, [g_kk]
        add  ax, 84
        test word [g_zw], 512
        jz   gh3
        add  ax, 32
gh3:    mov  ah, al
        mov  cx, [g_xl]
        add  cx, [g_ew]
        mov  dx, [g_xr]
        sub  dx, [g_ew]
        call spandith
        ; white edge lines
        mov  al, 15
        mov  ah, 15
        mov  cx, [g_xl]
        mov  dx, cx
        add  dx, [g_ew]
        call spandith
        mov  dx, [g_xr]
        mov  cx, dx
        sub  cx, [g_ew]
        call spandith
        ; dashed lane lines
        mov  ax, [g_zw]
        and  ax, 1023
        cmp  ax, 384
        jae  gh_nd
        mov  ax, [g_lw]
        mov  cl, 4
        shr  ax, cl
        inc  ax
        mov  [g_dw], ax
        mov  si, [g_lw]
        shr  si, 1
        mov  ax, 0x0F0F
        mov  cx, [g_cx]
        sub  cx, si
        mov  dx, [g_dw]
        shr  dx, 1
        sub  cx, dx
        mov  dx, cx
        add  dx, [g_dw]
        call spandith
        mov  cx, [g_cx]
        add  cx, si
        mov  dx, [g_dw]
        shr  dx, 1
        sub  cx, dx
        mov  dx, cx
        add  dx, [g_dw]
        call spandith
gh_nd:  inc  word [g_y]
        cmp  word [g_y], 167
        jae  gh_dn
        jmp  gh_row
gh_dn:  ret

; ------------------------------------------------------- buildings
; b_project: ax = distance z (>= 448); sets b_k, b_lw, b_yb, b_cx
b_project:
        mov  bx, ax
        mov  dx, 1
        mov  ax, 0x5E00
        div  bx
        mov  [b_k], ax
        add  ax, 7
        mov  [b_lw], ax
        mov  bx, ax
        mov  ax, [b_k]
        add  ax, 87
        mov  [b_yb], ax
        mov  ax, [camu]
        mul  bx
        mov  cl, 6
        shr  ax, cl
        mov  bx, 160
        add  bx, [b_lw]
        sub  bx, ax
        mov  [b_cx], bx
        ret

draw_buildings:
        mov  ax, [odo]
        and  ax, 1023
        mov  [b_off], ax
        mov  ax, [odo]
        mov  cl, 10
        shr  ax, cl
        mov  [b_base], ax
        mov  word [b_j], 16
bl_lp:  mov  ax, [b_j]
        inc  ax
        mov  cl, 10
        shl  ax, cl
        sub  ax, [b_off]
        mov  [b_z], ax
        cmp  ax, 448
        jb   bl_nx
        call b_project
        mov  ax, [b_base]
        add  ax, [b_j]
        and  ax, 7
        mov  [b_idx], ax
        mov  word [b_side], 0
        call draw_bld
        mov  ax, [b_base]
        add  ax, [b_j]
        add  ax, 3
        and  ax, 7
        mov  [b_idx], ax
        mov  word [b_side], 1
        call draw_bld
bl_nx:  dec  word [b_j]
        jns  bl_lp
        ret

draw_bld:
        mov  ax, [b_lw]
        shl  ax, 1
        mov  [b_bw], ax
        mov  ax, [b_lw]
        shr  ax, 1
        add  ax, [b_lw]          ; road half width
        mov  bx, [b_lw]
        shr  bx, 1
        shr  bx, 1               ; pavement gap
        add  ax, bx
        cmp  word [b_side], 0
        jne  db1
        mov  bx, [b_cx]
        sub  bx, ax
        sub  bx, [b_bw]
        jmp  db2
db1:    mov  bx, [b_cx]
        add  bx, ax
db2:    mov  [b_x0], bx
        mov  si, [b_idx]
        xor  ax, ax
        mov  al, [bld_ht+si]
        mul  word [b_lw]
        shr  ax, 1
        mov  [b_h], ax
        xor  ax, ax
        mov  al, [bld_col+si]
        mov  [c_t], ax
        mov  ax, [b_yb]
        sub  ax, [b_h]
        mov  [c_yc], ax
        RECT [b_x0],[c_yc],[b_bw],[b_h],[c_t]
        ; shop front
        mov  ax, [b_lw]
        shr  ax, 1
        inc  ax
        mov  [b_ph], ax
        mov  ax, [b_yb]
        sub  ax, [b_ph]
        mov  [c_yc], ax
        RECT [b_x0],[c_yc],[b_bw],[b_ph],8
        cmp  word [b_lw], 12
        jb   db_end
        ; windows: 3 columns, one row per floor
        mov  ax, [b_lw]
        shr  ax, 1
        mov  [b_fp], ax
        mov  bx, ax
        add  ax, ax
        add  ax, bx
        mov  cl, 3
        shr  ax, cl
        mov  [b_wh], ax          ; window height = 3/8 of a floor... 
        mov  ax, [b_bw]
        mov  bl, 3
        div  bl
        xor  ah, ah
        mov  [b_pitch], ax
        shr  ax, 1
        mov  [b_ww], ax
        mov  ax, [b_yb]
        sub  ax, [b_ph]
        sub  ax, [b_fp]
        mov  [b_wy], ax
        mov  word [b_f], 1
db_fl:  mov  ax, [b_wy]
        mov  bx, [b_yb]
        sub  bx, [b_h]
        add  bx, [b_fp]
        cmp  ax, bx
        jl   db_end
        mov  ax, [b_wy]
        add  ax, [b_wh]
        cmp  ax, 0
        jl   db_end
        mov  word [b_c], 0
db_cl:  mov  ax, [b_c]
        mul  word [b_pitch]
        add  ax, [b_x0]
        mov  bx, [b_pitch]
        sub  bx, [b_ww]
        shr  bx, 1
        add  ax, bx
        mov  [c_xc], ax
        mov  ax, [b_f]
        mov  bx, 5
        mul  bx
        mov  bx, [b_c]
        add  ax, bx
        add  ax, bx
        add  ax, bx
        add  ax, [b_idx]
        and  ax, 3
        mov  word [c_t], 1
        jnz  db_w
        mov  word [c_t], 14
db_w:   RECT [c_xc],[b_wy],[b_ww],[b_wh],[c_t]
        inc  word [b_c]
        cmp  word [b_c], 3
        jb   db_cl
        mov  ax, [b_wy]
        sub  ax, [b_fp]
        mov  [b_wy], ax
        inc  word [b_f]
        jmp  db_fl
db_end: ret

; -------------------------------------------------------------- cars
; drawcar: dc_cx = centre, dc_yb = bottom row, dc_lw = lane width, dc_col
drawcar:
        mov  ax, [dc_lw]
        mov  bx, ax
        shl  ax, 1
        shl  ax, 1
        shl  ax, 1
        sub  ax, bx
        mov  cl, 3
        shr  ax, cl              ; W = 7/8 lane
        cmp  ax, 3
        jae  dcw
        mov  ax, 3
dcw:    mov  [c_W], ax
        mov  bx, ax
        shl  ax, 1
        shl  ax, 1
        add  ax, bx
        mov  cl, 3
        shr  ax, cl              ; H = 5/8 W
        cmp  ax, 2
        jae  dch
        mov  ax, 2
dch:    mov  [c_H], ax
        mov  cl, 3
        shr  ax, cl
        cmp  ax, 1
        jae  dcs
        mov  ax, 1
dcs:    mov  [c_sh], ax
        mov  ax, [c_H]
        mov  bx, ax
        shl  ax, 1
        add  ax, bx
        shr  ax, 1
        shr  ax, 1
        cmp  ax, 1
        jae  dcb
        mov  ax, 1
dcb:    mov  [c_bh], ax
        mov  ax, [c_H]
        sub  ax, [c_bh]
        cmp  ax, 1
        jge  dcc
        mov  ax, 1
dcc:    mov  [c_ch], ax
        mov  ax, [c_W]
        shr  ax, 1
        mov  bx, [dc_cx]
        sub  bx, ax
        mov  [c_x0], bx
        mov  ax, [dc_yb]
        sub  ax, [c_sh]
        sub  ax, [c_bh]
        mov  [c_ytb], ax
        sub  ax, [c_ch]
        mov  [c_yc], ax
        mov  ax, [c_W]
        shr  ax, 1
        shr  ax, 1
        shr  ax, 1
        mov  bx, [c_x0]
        add  bx, ax
        mov  [c_xc], bx
        mov  bx, [c_W]
        shr  bx, 1
        shr  bx, 1
        mov  cx, [c_W]
        sub  cx, bx
        mov  [c_wc], cx
        ; ground shadow / bumper
        mov  ax, [dc_yb]
        sub  ax, [c_sh]
        mov  [c_t], ax
        RECT [c_x0],[c_t],[c_W],[c_sh],0
        ; lower body and cabin use rounded silhouettes for softer car edges
        PUSHV [c_x0]
        PUSHV [c_ytb]
        PUSHV [c_W]
        PUSHV [c_bh]
        PUSHV [dc_col]
        call roundrect
        PUSHV [c_xc]
        PUSHV [c_yc]
        PUSHV [c_wc]
        PUSHV [c_ch]
        PUSHV [dc_col]
        call roundrect
        ; rear window
        cmp  word [c_ch], 3
        jb   dc_tl
        mov  ax, [c_wc]
        shr  ax, 1
        shr  ax, 1
        shr  ax, 1
        inc  ax
        mov  bx, [c_xc]
        add  bx, ax
        mov  [c_t], bx
        shl  ax, 1
        mov  cx, [c_wc]
        sub  cx, ax
        mov  ax, [c_yc]
        inc  ax
        mov  dx, [c_ch]
        dec  dx
        mov  [sc_t], ax
        mov  [dc_lw], dx
        mov  [c_wc], cx
        RECT [c_t],[sc_t],[c_wc],[dc_lw],1
dc_tl:  ; tail lights
        mov  ax, [c_W]
        mov  cl, 3
        shr  ax, cl
        cmp  ax, 1
        jae  dtl1
        mov  ax, 1
dtl1:   mov  [c_xc], ax          ; light width
        mov  ax, [c_bh]
        shr  ax, 1
        cmp  ax, 1
        jae  dtl2
        mov  ax, 1
dtl2:   mov  [c_wc], ax          ; light height
        mov  ax, [c_bh]
        shr  ax, 1
        shr  ax, 1
        add  ax, [c_ytb]
        mov  [c_t], ax
        mov  ax, [c_W]
        mov  cl, 4
        shr  ax, cl
        add  ax, [c_x0]
        mov  [sc_t], ax
        RECT [sc_t],[c_t],[c_xc],[c_wc],12
        mov  ax, [c_x0]
        add  ax, [c_W]
        sub  ax, [c_xc]
        mov  bx, [c_W]
        mov  cl, 4
        shr  bx, cl
        sub  ax, bx
        mov  [sc_t], ax
        RECT [sc_t],[c_t],[c_xc],[c_wc],12
        ; number plate
        cmp  word [c_W], 22
        jb   dc_end
        mov  ax, [c_W]
        shr  ax, 1
        shr  ax, 1
        mov  [c_xc], ax
        shr  ax, 1
        mov  bx, [dc_cx]
        sub  bx, ax
        mov  [sc_t], bx
        mov  ax, [c_bh]
        shr  ax, 1
        add  ax, [c_ytb]
        mov  [c_t], ax
        mov  ax, [c_bh]
        shr  ax, 1
        shr  ax, 1
        inc  ax
        mov  [c_wc], ax
        RECT [sc_t],[c_t],[c_xc],[c_wc],15
dc_end: ret

; traffic, drawn from the far one to the near one
draw_traffic:
        xor  si, si
dt0:    mov  word [tdone+si], 0
        add  si, 2
        cmp  si, NC*2
        jb   dt0
        mov  word [t_cnt], NC
dt_pick:
        mov  bx, -1              ; best index
        mov  dx, -32768          ; best z
        xor  si, si
dt1:    cmp  word [tdone+si], 0
        jne  dt2
        mov  ax, [car_z+si]
        cmp  ax, dx
        jle  dt2
        mov  dx, ax
        mov  bx, si
dt2:    add  si, 2
        cmp  si, NC*2
        jb   dt1
        cmp  bx, 0
        jl   dt_end
        mov  word [tdone+bx], 1
        mov  si, bx
        cmp  dx, 448
        jl   dt_nx
        cmp  dx, 30000
        jg   dt_nx
        mov  ax, dx
        push si
        call b_project
        pop  si
        mov  ax, [b_yb]
        mov  [dc_yb], ax
        mov  ax, [b_lw]
        mov  [dc_lw], ax
        mov  ax, [car_col+si]
        mov  [dc_col], ax
        mov  ax, [b_cx]
        mov  bx, [car_lane+si]
        cmp  bx, 1
        je   dt3
        jb   dt4
        add  ax, [b_lw]
        jmp  dt3
dt4:    sub  ax, [b_lw]
dt3:    mov  [dc_cx], ax
        call drawcar
dt_nx:  dec  word [t_cnt]
        jnz  dt_pick
dt_end: ret

render_highway:
        call draw_sky_hwy
        call draw_ground_hwy
        call draw_buildings
        call draw_traffic
        ret

; =====================================================================
;                    COCKPIT  (bonnet, dials, wheel)  and  HUD
; =====================================================================
draw_bonnet:
        mov  word [g_y], 143
bn1:    mov  bx, [g_y]
        mov  ax, bx
        sub  ax, 143             ; r = row inside the bonnet
        mov  si, bonnet_hw
        add  si, ax
        mov  di, ax
        xor  ah, ah
        mov  al, [si]
        mov  cx, 160
        sub  cx, ax
        mov  dx, 160
        add  dx, ax
        ; paint colour: smooth orange gradient from top to bottom
        mov  ax, di
        mov  bp, ax
        shr  bp, 1
        shr  bp, 1
        add  ax, bp
        cmp  ax, 31
        jbe  bn2
        mov  ax, 31
bn2:    add  ax, 212
        mov  ah, al
        mov  bp, ax              ; remember the colour
        call spandith
bn3:    inc  word [g_y]
        cmp  word [g_y], 167
        jb   bn1
        ret

draw_dashbase:
        RECT 0,167,320,33,0
        RECT 0,167,320,1,8
        ; gear box
        RECT 7,175,24,22,8
        RECT 8,176,22,20,0
        mov  si, s_d
        mov  al, 10
        cmp  word [spd], 0
        jge  dg1
        mov  si, s_r
        mov  al, 12
dg1:    mov  bx, 13
        mov  dx, 179
        mov  ah, 2
        call puts
        ; button grid
        RECT 35,173,29,25,8
        RECT 36,174,27,23,0
        xor  si, si
bg1:    mov  ax, si
        mov  bl, 3
        div  bl                  ; al = row, ah = column
        mov  bx, ax
        xor  bh, bh              ; bl = row
        mov  al, ah
        xor  ah, ah
        mov  cl, 3
        shl  ax, cl
        add  ax, 40
        mov  [c_xc], ax
        mov  ax, bx
        xor  ah, ah
        mov  cl, 3
        shl  ax, cl
        add  ax, 178
        mov  [c_yc], ax
        mov  bx, si
        mov  al, [grid_col+bx]
        xor  ah, ah
        mov  [c_t], ax
        RECT [c_xc],[c_yc],5,5,[c_t]
        inc  si
        cmp  si, 9
        jb   bg1
        ret

grid_col: db 3,6,2,9,4,2,12,10,14

draw_speedo:
        mov  si, dtab30
        mov  cx, 30
        mov  bx, 112
        mov  dx, 188
        mov  al, 15
        call drawdisc
        mov  si, dtab28
        mov  cx, 28
        mov  al, 0
        call drawdisc
        ; tick marks
        mov  si, tick_tab
        mov  cx, 21
spt:    lodsb
        cbw
        add  ax, 112
        push ax
        lodsb
        cbw
        add  ax, 188
        push ax
        lodsb
        cbw
        add  ax, 112
        push ax
        lodsb
        cbw
        add  ax, 188
        push ax
        mov  al, 7
        test cl, 1
        jz   spt1
        mov  al, 15
spt1:   xor  ah, ah
        push ax
        call line
        loop spt
        ; numbers
        mov  si, lbl_tab
        lodsb
        cbw
        mov  bx, ax
        add  bx, 112
        lodsb
        cbw
        mov  dx, ax
        add  dx, 188
        push si
        mov  si, s_40
        mov  al, 15
        mov  ah, 1
        call puts
        pop  si
        lodsb
        cbw
        mov  bx, ax
        add  bx, 112
        lodsb
        cbw
        mov  dx, ax
        add  dx, 188
        push si
        mov  si, s_80
        mov  al, 15
        mov  ah, 1
        call puts
        pop  si
        lodsb
        cbw
        mov  bx, ax
        add  bx, 112
        lodsb
        cbw
        mov  dx, ax
        add  dx, 188
        push si
        mov  si, s_120
        mov  al, 15
        mov  ah, 1
        call puts
        pop  si
        lodsb
        cbw
        mov  bx, ax
        add  bx, 112
        lodsb
        cbw
        mov  dx, ax
        add  dx, 188
        mov  si, s_160
        mov  al, 15
        mov  ah, 1
        call puts
        ; needle
        mov  ax, [spd]
        cmp  ax, 0
        jge  sn1
        neg  ax
sn1:    xor  dx, dx
        mov  bx, 40
        div  bx
        cmp  ax, 80
        jbe  sn2
        mov  ax, 80
sn2:    shl  ax, 1
        add  ax, needle_tab
        mov  si, ax
        lodsb
        cbw
        add  ax, 112
        mov  [c_xc], ax
        lodsb
        cbw
        add  ax, 188
        mov  [c_yc], ax
        PUSHV 112
        PUSHV 188
        PUSHV [c_xc]
        PUSHV [c_yc]
        PUSHV 12
        call line
        PUSHV 113
        PUSHV 188
        PUSHV [c_xc]
        PUSHV [c_yc]
        PUSHV 12
        call line
        PUSHV 112
        PUSHV 189
        PUSHV [c_xc]
        PUSHV [c_yc]
        PUSHV 4
        call line
        mov  si, dtab3
        mov  cx, 3
        mov  bx, 112
        mov  dx, 188
        mov  al, 7
        call drawdisc
        ; digital speed
        mov  ax, [spd]
        cmp  ax, 0
        jge  sn3
        neg  ax
sn3:    mov  cl, 4
        shr  ax, cl
        mov  cl, 3
        call num2str
        mov  bx, 90
        mov  dx, 192
        mov  al, 14
        mov  ah, 1
        call puts
        mov  si, s_kmh
        mov  bx, 113
        mov  dx, 192
        mov  al, 7
        mov  ah, 1
        call puts
        ret

draw_fuelgauge:
        mov  si, dtab22
        mov  cx, 22
        mov  bx, 222
        mov  dx, 188
        mov  al, 15
        call drawdisc
        mov  si, dtab20
        mov  cx, 20
        mov  al, 0
        call drawdisc
        mov  si, ftick_tab
        mov  cx, 5
ft1:    lodsb
        cbw
        add  ax, 222
        push ax
        lodsb
        cbw
        add  ax, 188
        push ax
        lodsb
        cbw
        add  ax, 222
        push ax
        lodsb
        cbw
        add  ax, 188
        push ax
        PUSHV 7
        call line
        loop ft1
        mov  si, s_e
        mov  bx, 203
        mov  dx, 191
        mov  al, 15
        mov  ah, 1
        call puts
        mov  si, s_f
        mov  bx, 234
        mov  dx, 191
        mov  al, 15
        mov  ah, 1
        call puts
        ; low fuel? (below a quarter of the tank)
        mov  ax, [fuelmax]
        shr  ax, 1
        shr  ax, 1               ; a quarter of the tank
        mov  cx, 12
        cmp  [fuel], ax
        jae  ff1
        mov  cx, 15
ff1:    mov  [c_t], cx           ; warning colour index
        ; needle: fuel * 16 / tank
        mov  ax, [fuel]
        mov  bx, 16
        mul  bx
        div  word [fuelmax]
        cmp  ax, 16
        jbe  ff2
        mov  ax, 16
ff2:    shl  ax, 1
        add  ax, fneedle_tab
        mov  si, ax
        lodsb
        cbw
        add  ax, 222
        mov  [c_xc], ax
        lodsb
        cbw
        add  ax, 188
        mov  [c_yc], ax
        PUSHV 222
        PUSHV 188
        PUSHV [c_xc]
        PUSHV [c_yc]
        PUSHV 12
        call line
        PUSHV 223
        PUSHV 188
        PUSHV [c_xc]
        PUSHV [c_yc]
        PUSHV 12
        call line
        mov  si, dtab3
        mov  cx, 3
        mov  bx, 222
        mov  dx, 188
        mov  al, 7
        call drawdisc
        ; pump symbol, blinks red when the tank is nearly empty
        mov  al, 7
        cmp  word [c_t], 15
        jne  ff3
        mov  al, 12
        test byte [ticks], 16
        jz   ff3
        mov  al, 0
ff3:    mov  si, bmp_pump
        mov  bx, 219
        mov  dx, 171
        call drawbmp
        ret

draw_indicators:
        ; left / right arrows light up while steering
        mov  al, 2
        cmp  word [wheel], 0
        jge  di1
        mov  al, 10
di1:    mov  si, bmp_larr
        mov  bx, 137
        mov  dx, 176
        call drawbmp
        mov  al, 2
        cmp  word [wheel], 0
        jle  di2
        mov  al, 10
di2:    mov  si, bmp_rarr
        mov  bx, 178
        mov  dx, 176
        call drawbmp
        ; hazard triangle blinks after a crash
        mov  al, 4
        cmp  word [crash], 0
        je   di3
        test byte [crash], 8
        jz   di3
        mov  al, 12
di3:    mov  si, bmp_haz
        mov  bx, 158
        mov  dx, 173
        call drawbmp
        ret

draw_wheel:
        ; rim: grey outline with a black ring inside
        mov  si, dtab47
        mov  word [dd_tabi], dtab38
        mov  word [dd_ri], 38
        mov  cx, 47
        mov  bx, 303
        mov  dx, 183
        mov  al, 8
        call drawring
        mov  si, dtab45
        mov  word [dd_tabi], dtab36
        mov  word [dd_ri], 36
        mov  cx, 45
        mov  al, 0
        call drawring
        ; three spokes, rotated with the steering angle
        mov  ax, [wheel]
        add  ax, 4
        mov  bx, 6
        mul  bx
        add  ax, spoke_tab
        mov  si, ax
        mov  cx, 3
sw1:    lodsb
        cbw
        add  ax, 303
        mov  [c_xc], ax
        lodsb
        cbw
        add  ax, 183
        mov  [c_yc], ax
        PUSHV 303
        PUSHV 183
        PUSHV [c_xc]
        PUSHV [c_yc]
        PUSHV 8
        call line
        PUSHV 304
        PUSHV 183
        PUSHV [c_xc]
        PUSHV [c_yc]
        PUSHV 8
        call line
        PUSHV 303
        PUSHV 184
        PUSHV [c_xc]
        PUSHV [c_yc]
        PUSHV 8
        call line
        loop sw1
        mov  si, dtab11
        mov  cx, 11
        mov  bx, 303
        mov  dx, 183
        mov  al, 7
        call drawdisc
        mov  si, dtab9
        mov  cx, 9
        mov  al, 0
        call drawdisc
        mov  si, s_s
        mov  bx, 301
        mov  dx, 180
        mov  al, 7
        mov  ah, 1
        call puts
        ret

draw_cockpit:
        call draw_bonnet
        call draw_dashbase
        call draw_speedo
        call draw_indicators
        call draw_fuelgauge
        call draw_wheel
        ret

; ----------------------------------------------------------------- HUD
draw_hud:
        ; time bar (the red level drops as time runs out)
        RECT 9,20,6,122,0
        mov  ax, [timeleft]
        mov  bx, 119
        mul  bx
        div  word [timetotal]
        mov  [c_t], ax
        or   ax, ax
        jz   hd1
        mov  ax, 141
        sub  ax, [c_t]
        mov  [c_yc], ax
        mov  ax, [timetotal]
        shr  ax, 1
        shr  ax, 1
        mov  bx, 12
        cmp  [timeleft], ax
        jae  hd0
        test byte [ticks], 16    ; flashes when time is nearly out
        jz   hd0
        mov  bx, 4
hd0:    mov  [c_wc], bx
        RECT 10,[c_yc],4,[c_t],[c_wc]
        RECT 10,[c_yc],1,[c_t],14
hd1:    mov  si, s_time_l
        mov  bx, 4
        mov  dx, 11
        mov  al, 15
        mov  ah, 1
        call puts_sh
        ; distance and score
        cmp  byte [scene], 2
        je   hd_sc
        mov  si, s_dist
        mov  bx, 34
        mov  dx, 3
        mov  al, 15
        mov  ah, 1
        call puts_sh
        mov  ax, [odo]
        mov  cl, 6
        shr  ax, cl
        mov  cl, 1
        call num2str
        mov  bx, [t_x]
        add  bx, 6
        mov  dx, 3
        mov  al, 15
        mov  ah, 1
        call puts_sh
        mov  si, s_of
        mov  bx, [t_x]
        mov  dx, 3
        mov  al, 15
        mov  ah, 1
        call puts_sh
hd_sc:  mov  si, s_score
        mov  bx, 34
        mov  dx, 13
        mov  al, 14
        mov  ah, 1
        call puts_sh
        mov  ax, [score]
        mov  cl, 1
        call num2str
        mov  bx, [t_x]
        add  bx, 6
        mov  dx, 13
        mov  al, 14
        mov  ah, 1
        call puts_sh
        ; lane guide
        RECT 205,2,28,25,6
        RECT 206,3,26,23,0
        mov  ax, [camu]
        add  ax, 32
        mov  cl, 6
        shr  ax, cl
        cmp  ax, 2
        jbe  hd2
        mov  ax, 2
hd2:    mov  [c_t], ax
        xor  si, si
hd3:    mov  ax, si
        mov  cl, 3
        shl  ax, cl
        add  ax, 208
        mov  [c_xc], ax
        mov  al, 8
        cmp  si, [c_t]
        jne  hd4
        mov  bx, [c_xc]
        dec  bx
        mov  [c_wc], bx
        RECT [c_wc],4,9,19,6
        mov  al, 14
hd4:    mov  bx, [c_xc]
        mov  dx, 7
        push si
        mov  si, bmp_lane
        call drawbmp
        pop  si
        inc  si
        cmp  si, 3
        jb   hd3
        cmp  byte [scene], 2
        jne  hd_end
        ; parking: title pill and sensor
        RECT 96,3,108,15,8
        RECT 97,4,106,13,0
        mov  si, s_ban
        mov  bx, 99
        mov  dx, 7
        mov  al, 15
        mov  ah, 1
        call puts
        mov  si, s_sens
        mov  bx, 125
        mov  dx, 121
        mov  al, 15
        mov  ah, 1
        call puts_sh
        mov  ax, [sensor]
        xor  dx, dx
        mov  bx, 10
        div  bx
        push dx
        mov  cl, 1
        call num2str
        mov  bx, [t_x]
        add  bx, 6
        mov  dx, 121
        mov  al, 15
        mov  ah, 1
        call puts_sh
        mov  si, s_dot
        mov  bx, [t_x]
        mov  dx, 121
        mov  al, 15
        mov  ah, 1
        call puts_sh
        pop  ax
        mov  cl, 1
        call num2str
        mov  bx, [t_x]
        mov  dx, 121
        mov  al, 15
        mov  ah, 1
        call puts_sh
        mov  si, s_m
        mov  bx, [t_x]
        mov  dx, 121
        mov  al, 15
        mov  ah, 1
        call puts_sh
        ; 8 sensor lamps: green, yellow, red as the car gets closer
        mov  ax, 32
        sub  ax, [sensor]
        jge  sl1
        xor  ax, ax
sl1:    mov  cl, 2
        shr  ax, cl
        cmp  ax, 8
        jbe  sl2
        mov  ax, 8
sl2:    mov  [c_t], ax
        RECT 123,128,83,9,0
        xor  si, si
sl3:    mov  ax, si
        mov  bx, 10
        mul  bx
        add  ax, 125
        mov  [c_xc], ax
        mov  bx, 8
        cmp  si, [c_t]
        jae  sl4
        mov  bx, 10
        cmp  si, 3
        jb   sl4
        mov  bx, 14
        cmp  si, 6
        jb   sl4
        mov  bx, 12
sl4:    mov  [c_wc], bx
        RECT [c_xc],130,8,5,[c_wc]
        inc  si
        cmp  si, 8
        jb   sl3
hd_end: ret

; =====================================================================
;                    PARKING LOT  and  MENU / MESSAGE PANELS
; =====================================================================
tree_y: db 52,48,55,50,53,47,54,51,49,55
s_title: db "DR. DRIVING",0
s_lite:  db "LITE",0
s_sub:   db "COAL FINAL PROJECT",0
s_o1:    db "HIGHWAY",0
s_o2:    db "PARKING",0
s_k1:    db "1",0
s_k2:    db "2",0
s_hint1: db "UP GAS  SPACE BRAKE  DOWN REVERSE",0
s_hint2: db "LEFT RIGHT STEER   ESC BACK",0
s_enter: db "PRESS ENTER",0
s_scorel: db "SCORE",0

; bayx: ax = world x  ->  ax = screen x at the current row (uses [px], [g_lw])
bayx:   sub  ax, [px]
        imul word [g_lw]
        mov  cl, 6
        sar  ax, cl
        add  ax, 160
        ret

draw_sky_park:
        mov  cx, 80
        call skyrows
        RECT 40,18,30,4,15
        RECT 30,22,52,4,15
        RECT 220,30,26,4,15
        RECT 210,34,48,4,15
        ; row of trees behind the fence
        xor  si, si
tp1:    mov  ax, si
        mov  bx, 34
        mul  bx
        sub  ax, 6
        mov  [c_xc], ax
        xor  ax, ax
        mov  al, [tree_y+si]
        mov  [c_yc], ax
        mov  bx, 80
        sub  bx, ax
        mov  [c_wc], bx
        RECT [c_xc],[c_yc],40,[c_wc],2
        mov  ax, [c_xc]
        add  ax, 3
        mov  [c_xc], ax
        RECT [c_xc],[c_yc],34,5,10
        inc  si
        cmp  si, 10
        jb   tp1
        ; concrete fence
        RECT 0,80,320,8,7
        RECT 0,80,320,1,15
        RECT 0,87,320,1,8
        xor  si, si
tp2:    mov  ax, si
        mov  cl, 4
        shl  ax, cl
        mov  [c_xc], ax
        RECT [c_xc],81,2,6,8
        inc  si
        cmp  si, 20
        jb   tp2
        ret

draw_ground_park:
        mov  word [g_y], 88
gp_row: mov  ax, [g_y]
        sub  ax, 87
        mov  [g_k], ax
        shl  ax, 1
        add  ax, 20
        mov  [g_lw], ax
        mov  bx, [g_k]
        xor  dx, dx
        mov  ax, 18560           ; 290 m * 64
        div  bx
        add  ax, [pz]
        sub  ax, 115
        mov  [g_zw], ax
        mov  bx, [g_y]
        mov  ax, [g_k]
        shr  ax, 1
        cmp  ax, 31
        jbe  gp1a
        mov  ax, 31
gp1a:   add  ax, 84
        mov  ah, al
        xor  cx, cx
        mov  dx, 320
        call spandith
        mov  ax, [g_zw]
        cmp  ax, 576
        jl   gp_nx
        cmp  ax, 1030
        jg   gp_nx
        mov  ax, [g_lw]
        mov  cl, 5
        shr  ax, cl
        inc  ax
        mov  [g_ew], ax
        cmp  word [g_zw], 992
        jge  gp_curb
        ; bay: green floor, white lines
        mov  ax, 24
        call bayx
        mov  [g_xl], ax
        mov  ax, 104
        call bayx
        mov  [g_xr], ax
        mov  bx, [g_y]
        mov  ax, 0x0202
        mov  cx, [g_xl]
        mov  dx, [g_xr]
        call spandith
        mov  ax, 0x0F0F
        mov  cx, [g_xl]
        mov  dx, cx
        add  dx, [g_ew]
        call spandith
        mov  dx, [g_xr]
        mov  cx, dx
        sub  cx, [g_ew]
        call spandith
        cmp  word [g_zw], 616
        jge  gp2
        mov  cx, [g_xl]
        mov  dx, [g_xr]
        call spandith
gp2:    mov  ax, -56
        call bayx
        mov  cx, ax
        mov  dx, ax
        add  dx, [g_ew]
        mov  ax, 0x0F0F
        call spandith
        mov  ax, 184
        call bayx
        mov  cx, ax
        mov  dx, ax
        add  dx, [g_ew]
        mov  ax, 0x0F0F
        call spandith
        jmp  gp_nx
gp_curb:
        mov  ax, -60
        call bayx
        push ax
        mov  ax, 190
        call bayx
        mov  dx, ax
        pop  cx
        mov  bx, [g_y]
        mov  ax, 0x0E0E
        call spandith
gp_nx:  inc  word [g_y]
        cmp  word [g_y], 167
        jae  gp_dn
        jmp  gp_row
gp_dn:  ret

; park_proj: [pp_x] = world x, [pp_z] = world z  ->  dc_cx, dc_yb, g_lw
;            carry set when the object is not visible
park_proj:
        mov  ax, [pz]
        sub  ax, 115
        mov  bx, [pp_z]
        sub  bx, ax
        cmp  bx, 200
        jl   pj_no
        xor  dx, dx
        mov  ax, 18560
        div  bx
        cmp  ax, 1
        jl   pj_no
        mov  [g_k], ax
        add  ax, 87
        mov  [dc_yb], ax
        mov  ax, [g_k]
        shl  ax, 1
        add  ax, 20
        mov  [g_lw], ax
        mov  ax, [pp_x]
        call bayx
        mov  [dc_cx], ax
        clc
        ret
pj_no:  stc
        ret

; a parked car seen from behind
park_car:
        call park_proj
        jc   pc_x
        mov  ax, [g_lw]
        mov  bx, ax
        shl  ax, 1
        shl  ax, 1
        add  ax, bx
        mov  cl, 3
        shr  ax, cl
        mov  [dc_lw], ax
        call drawcar
pc_x:   ret

; traffic cone
park_cone:
        call park_proj
        jc   pk_x
        mov  ax, [g_lw]
        mov  bx, ax
        shl  ax, 1
        add  ax, bx
        mov  cl, 4
        shr  ax, cl              ; height
        cmp  ax, 4
        jae  pk1
        mov  ax, 4
pk1:    mov  [c_H], ax
        mov  cl, 2
        shr  ax, cl
        mov  [c_sh], ax          ; height of one step
        mov  ax, [c_H]
        shr  ax, 1
        shr  ax, 1
        shr  ax, 1
        cmp  ax, 1
        jae  pk2
        mov  ax, 1
pk2:    mov  [c_bh], ax          ; base plate
        xor  si, si
pk3:    mov  ax, si
        inc  ax
        mul  word [c_H]
        mov  cl, 2
        shr  ax, cl
        inc  ax
        mov  [c_W], ax           ; width of this step
        shr  ax, 1
        mov  bx, [dc_cx]
        sub  bx, ax
        mov  [c_x0], bx
        mov  ax, si
        mul  word [c_sh]
        mov  bx, [dc_yb]
        sub  bx, [c_H]
        sub  bx, [c_bh]
        add  bx, ax
        mov  [c_ytb], bx
        mov  ax, 12
        cmp  si, 1
        jne  pk4
        mov  ax, 15
pk4:    mov  [c_t], ax
        RECT [c_x0],[c_ytb],[c_W],[c_sh],[c_t]
        inc  si
        cmp  si, 4
        jb   pk3
        mov  ax, [c_H]
        mov  cl, 2
        shr  ax, cl
        add  ax, [c_H]
        mov  [c_W], ax
        shr  ax, 1
        mov  bx, [dc_cx]
        sub  bx, ax
        mov  [c_x0], bx
        mov  ax, [dc_yb]
        sub  ax, [c_bh]
        mov  [c_ytb], ax
        RECT [c_x0],[c_ytb],[c_W],[c_bh],0
pk_x:   ret

draw_park_objects:
        ; big letter P in the bay
        mov  ax, [pz]
        mov  bx, 899
        sub  bx, ax              ; distance to the middle of the bay
        cmp  bx, 300
        jl   dpo1
        xor  dx, dx
        mov  ax, 18560
        div  bx
        cmp  ax, 70
        jg   dpo1
        mov  [g_k], ax
        add  ax, 87
        mov  [dc_yb], ax
        mov  ax, [g_k]
        shl  ax, 1
        add  ax, 20
        mov  [g_lw], ax
        mov  ax, 64
        call bayx
        mov  [dc_cx], ax
        mov  ah, 3
        cmp  word [g_k], 30
        jge  dpo2
        mov  ah, 2
        cmp  word [g_k], 14
        jge  dpo2
        mov  ah, 1
dpo2:   mov  [t_sc], ah
        xor  ah, ah
        mov  al, [t_sc]
        mov  bx, 3
        mul  bx
        mov  bx, [dc_cx]
        sub  bx, ax
        mov  dx, [dc_yb]
        sub  dx, ax
        mov  si, s_p
        mov  al, 15
        mov  ah, [t_sc]
        call puts
dpo1:   ; far parked cars
        mov  word [pp_x], 0
        mov  word [pp_z], 2300
        mov  word [dc_col], 4
        call park_car
        mov  word [pp_x], 116
        mov  word [pp_z], 2700
        mov  word [dc_col], 15
        call park_car
        mov  word [pp_x], -70
        mov  word [pp_z], 2500
        mov  word [dc_col], 14
        call park_car
        mov  word [pp_x], 60
        mov  word [pp_z], 3000
        mov  word [dc_col], 3
        call park_car
        mov  word [pp_x], 170
        mov  word [pp_z], 2400
        mov  word [dc_col], 9
        call park_car
        ; neighbours of the bay
        mov  word [pp_x], -16
        mov  word [pp_z], 595
        mov  word [dc_col], 15
        call park_car
        mov  word [pp_x], 144
        mov  word [pp_z], 595
        mov  word [dc_col], 4
        call park_car
        ; cones at the bay entrance
        mov  word [pp_x], 20
        mov  word [pp_z], 576
        call park_cone
        mov  word [pp_x], 108
        mov  word [pp_z], 576
        call park_cone
        ret

render_parking:
        call draw_sky_park
        call draw_ground_park
        call draw_park_objects
        ret

; ---------------------------------------------------------------- menu
; frame: draws a panel with a brown border and a thin orange line inside
; push x, y, w, h
panel:  push bp
        mov  bp, sp
        push ax
        mov  ax, [bp+10]
        mov  [c_x0], ax
        mov  ax, [bp+8]
        mov  [c_ytb], ax
        mov  ax, [bp+6]
        mov  [c_W], ax
        mov  ax, [bp+4]
        mov  [c_H], ax
        RECT [c_x0],[c_ytb],[c_W],[c_H],6
        mov  ax, [c_x0]
        add  ax, 2
        mov  [c_x0], ax
        mov  ax, [c_ytb]
        add  ax, 2
        mov  [c_ytb], ax
        sub  word [c_W], 4
        sub  word [c_H], 4
        RECT [c_x0],[c_ytb],[c_W],[c_H],0
        add  word [c_x0], 3
        add  word [c_ytb], 3
        sub  word [c_W], 6
        sub  word [c_H], 6
        RECT [c_x0],[c_ytb],[c_W],1,12
        mov  ax, [c_ytb]
        add  ax, [c_H]
        dec  ax
        mov  [c_t], ax
        RECT [c_x0],[c_t],[c_W],1,12
        RECT [c_x0],[c_ytb],1,[c_H],12
        mov  ax, [c_x0]
        add  ax, [c_W]
        dec  ax
        mov  [c_t], ax
        RECT [c_t],[c_ytb],1,[c_H],12
        pop  ax
        pop  bp
        ret  8

; text with a three layer "gold" look: dark red, brown, bright
goldtext:
        push ax
        push bx
        push dx
        add  bx, 2
        add  dx, 2
        mov  al, 4
        call puts
        pop  dx
        pop  bx
        push bx
        push dx
        inc  bx
        inc  dx
        mov  al, 6
        call puts
        pop  dx
        pop  bx
        pop  ax
        call puts
        ret

draw_menu:
        PUSHV 40
        PUSHV 28
        PUSHV 240
        PUSHV 148
        call panel
        mov  si, s_title
        mov  bx, 62
        mov  dx, 40
        mov  al, 14
        mov  ah, 3
        call goldtext
        mov  si, s_lite
        mov  bx, 137
        mov  dx, 66
        mov  al, 12
        mov  ah, 2
        call goldtext
        mov  si, s_sub
        mov  bx, 106
        mov  dx, 87
        mov  al, 7
        mov  ah, 1
        call puts
        RECT 70,98,180,1,8
        mov  si, s_k1
        mov  bx, 90
        mov  dx, 107
        mov  al, 14
        mov  ah, 2
        call puts_sh
        mov  si, s_o1
        mov  bx, 116
        mov  dx, 107
        mov  al, 15
        mov  ah, 2
        call puts_sh
        mov  si, s_k2
        mov  bx, 90
        mov  dx, 129
        mov  al, 14
        mov  ah, 2
        call puts_sh
        mov  si, s_o2
        mov  bx, 116
        mov  dx, 129
        mov  al, 15
        mov  ah, 2
        call puts_sh
        mov  si, s_hint1
        mov  bx, 61
        mov  dx, 150
        mov  al, 7
        mov  ah, 1
        call puts
        mov  si, s_hint2
        mov  bx, 79
        mov  dx, 160
        mov  al, 8
        mov  ah, 1
        call puts
        ret

draw_endpanel:
        PUSHV 50
        PUSHV 58
        PUSHV 220
        PUSHV 78
        call panel
        ; centre the title
        mov  si, [msg_t]
        xor  cx, cx
es1:    cmp  byte [si], 0
        je   es2
        inc  si
        inc  cx
        jmp  es1
es2:    mov  ax, cx
        mov  bx, 12
        mul  bx
        sub  ax, 2
        shr  ax, 1
        mov  bx, 160
        sub  bx, ax
        mov  si, [msg_t]
        mov  dx, 70
        mov  al, [msg_c]
        mov  ah, 2
        call puts_sh
        ; score line, centred: width = (6 + digits) * 12
        mov  ax, [score]
        mov  cl, 1
        call num2str
        xor  cx, cx
es4:    cmp  byte [si], 0
        je   es5
        inc  si
        inc  cx
        jmp  es4
es5:    add  cx, 6
        mov  ax, cx
        mov  bx, 6
        mul  bx
        mov  bx, 160
        sub  bx, ax
        push bx
        mov  si, s_scorel
        mov  dx, 94
        mov  al, 14
        mov  ah, 2
        call puts_sh
        mov  ax, [score]
        mov  cl, 1
        call num2str
        mov  bx, [t_x]
        add  bx, 12
        mov  dx, 94
        mov  al, 15
        mov  ah, 2
        call puts_sh
        pop  bx
        test byte [ticks], 32
        jz   es3
        mov  si, s_enter
        mov  bx, 128
        mov  dx, 118
        mov  al, 7
        mov  ah, 1
        call puts
es3:    ret


; =====================================================================
;                         LOOK-UP TABLES
; =====================================================================
; ---- 5x7 font: ASCII 32..90, 7 bytes per character, bit 4 = leftmost pixel ----
fontdata:
    db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00      ; ' '
    db 0x04, 0x04, 0x04, 0x04, 0x04, 0x00, 0x04      ; '!'
    db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00      ; '"'
    db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00      ; '#'
    db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00      ; '$'
    db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00      ; '%'
    db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00      ; '&'
    db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00      ; '''
    db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00      ; '('
    db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00      ; ')'
    db 0x00, 0x00, 0x0E, 0x0E, 0x0E, 0x00, 0x00      ; '*'
    db 0x00, 0x04, 0x04, 0x1F, 0x04, 0x04, 0x00      ; '+'
    db 0x00, 0x00, 0x00, 0x00, 0x0C, 0x0C, 0x08      ; ','
    db 0x00, 0x00, 0x00, 0x1F, 0x00, 0x00, 0x00      ; '-'
    db 0x00, 0x00, 0x00, 0x00, 0x00, 0x0C, 0x0C      ; '.'
    db 0x01, 0x01, 0x02, 0x04, 0x08, 0x10, 0x10      ; '/'
    db 0x0E, 0x11, 0x13, 0x15, 0x19, 0x11, 0x0E      ; '0'
    db 0x04, 0x0C, 0x04, 0x04, 0x04, 0x04, 0x0E      ; '1'
    db 0x0E, 0x11, 0x01, 0x02, 0x04, 0x08, 0x1F      ; '2'
    db 0x1F, 0x02, 0x04, 0x02, 0x01, 0x11, 0x0E      ; '3'
    db 0x02, 0x06, 0x0A, 0x12, 0x1F, 0x02, 0x02      ; '4'
    db 0x1F, 0x10, 0x1E, 0x01, 0x01, 0x11, 0x0E      ; '5'
    db 0x06, 0x08, 0x10, 0x1E, 0x11, 0x11, 0x0E      ; '6'
    db 0x1F, 0x01, 0x02, 0x04, 0x08, 0x08, 0x08      ; '7'
    db 0x0E, 0x11, 0x11, 0x0E, 0x11, 0x11, 0x0E      ; '8'
    db 0x0E, 0x11, 0x11, 0x0F, 0x01, 0x02, 0x0C      ; '9'
    db 0x00, 0x0C, 0x0C, 0x00, 0x0C, 0x0C, 0x00      ; ':'
    db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00      ; ';'
    db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00      ; '<'
    db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00      ; '='
    db 0x10, 0x08, 0x04, 0x02, 0x04, 0x08, 0x10      ; '>'
    db 0x0E, 0x11, 0x01, 0x02, 0x04, 0x00, 0x04      ; '?'
    db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00      ; '@'
    db 0x0E, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11      ; 'A'
    db 0x1E, 0x11, 0x11, 0x1E, 0x11, 0x11, 0x1E      ; 'B'
    db 0x0E, 0x11, 0x10, 0x10, 0x10, 0x11, 0x0E      ; 'C'
    db 0x1E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x1E      ; 'D'
    db 0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x1F      ; 'E'
    db 0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x10      ; 'F'
    db 0x0E, 0x11, 0x10, 0x17, 0x11, 0x11, 0x0E      ; 'G'
    db 0x11, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11      ; 'H'
    db 0x0E, 0x04, 0x04, 0x04, 0x04, 0x04, 0x0E      ; 'I'
    db 0x07, 0x02, 0x02, 0x02, 0x02, 0x12, 0x0C      ; 'J'
    db 0x11, 0x12, 0x14, 0x18, 0x14, 0x12, 0x11      ; 'K'
    db 0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x1F      ; 'L'
    db 0x11, 0x1B, 0x15, 0x15, 0x11, 0x11, 0x11      ; 'M'
    db 0x11, 0x19, 0x15, 0x13, 0x11, 0x11, 0x11      ; 'N'
    db 0x0E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E      ; 'O'
    db 0x1E, 0x11, 0x11, 0x1E, 0x10, 0x10, 0x10      ; 'P'
    db 0x0E, 0x11, 0x11, 0x11, 0x15, 0x12, 0x0D      ; 'Q'
    db 0x1E, 0x11, 0x11, 0x1E, 0x14, 0x12, 0x11      ; 'R'
    db 0x0F, 0x10, 0x10, 0x0E, 0x01, 0x01, 0x1E      ; 'S'
    db 0x1F, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04      ; 'T'
    db 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E      ; 'U'
    db 0x11, 0x11, 0x11, 0x11, 0x11, 0x0A, 0x04      ; 'V'
    db 0x11, 0x11, 0x11, 0x15, 0x15, 0x1B, 0x11      ; 'W'
    db 0x11, 0x11, 0x0A, 0x04, 0x0A, 0x11, 0x11      ; 'X'
    db 0x11, 0x11, 0x0A, 0x04, 0x04, 0x04, 0x04      ; 'Y'
    db 0x1F, 0x01, 0x02, 0x04, 0x08, 0x10, 0x1F      ; 'Z'

; ---- speedometer needle end points (dx,dy) from the dial centre, 81 steps of 2.5 km/h ----
needle_tab:
    db -21,12, -21,11, -22,10, -22,9, -23,7, -23,6, -23,5, -24,4
    db -24,3, -24,1, -24,0, -24,-1, -24,-3, -24,-4, -23,-5, -23,-6
    db -23,-7, -22,-9, -22,-10, -21,-11, -21,-12, -20,-13, -19,-14, -19,-15
    db -18,-16, -17,-17, -16,-18, -15,-19, -14,-19, -13,-20, -12,-21, -11,-21
    db -10,-22, -9,-22, -7,-23, -6,-23, -5,-23, -4,-24, -3,-24, -1,-24
    db 0,-24, 1,-24, 3,-24, 4,-24, 5,-23, 6,-23, 7,-23, 9,-22
    db 10,-22, 11,-21, 12,-21, 13,-20, 14,-19, 15,-19, 16,-18, 17,-17
    db 18,-16, 19,-15, 19,-14, 20,-13, 21,-12, 21,-11, 22,-10, 22,-9
    db 23,-7, 23,-6, 23,-5, 24,-4, 24,-3, 24,-1, 24,0, 24,1
    db 24,3, 24,4, 23,5, 23,6, 23,7, 22,9, 22,10, 21,11
    db 21,12

; ---- speedometer tick marks: x0,y0,x1,y1 relative to the centre, one per 10 km/h ----
tick_tab:
    db -19,11,-23,14
    db -24,8,-26,8
    db -22,2,-27,3
    db -25,-3,-27,-3
    db -21,-7,-26,-8
    db -22,-12,-23,-13
    db -16,-15,-20,-18
    db -15,-20,-16,-22
    db -9,-20,-11,-25
    db -5,-24,-6,-26
    db 0,-22,0,-27
    db 5,-24,6,-26
    db 9,-20,11,-25
    db 15,-20,16,-22
    db 16,-15,20,-18
    db 22,-12,23,-13
    db 21,-7,26,-8
    db 25,-3,27,-3
    db 22,2,27,3
    db 24,8,26,8
    db 19,11,23,13

; ---- dial numbers: x,y offset of the text from the centre ----
lbl_tab:
    db -20,-8      ; 40
    db -12,-17      ; 80
    db -2,-17      ; 120
    db 6,-8      ; 160

; ---- fuel needle end points, 17 steps from E to F ----
fneedle_tab:
    db -14,6, -15,3, -15,-1, -14,-5, -13,-8, -10,-11, -7,-13, -4,-15
    db 0,-15, 4,-15, 7,-13, 10,-11, 13,-8, 14,-5, 15,-1, 15,3
    db 14,6
ftick_tab:
    db -15,7,-18,8
    db -13,-9,-16,-10
    db 0,-16,0,-20
    db 13,-9,16,-10
    db 15,7,18,8

; ---- steering wheel spoke end points for 9 turn angles (-40..+40 deg): left, right, bottom ----
spoke_tab:
    db -28,24, 28,-24, 24,28
    db -32,19, 32,-18, 19,32
    db -35,13, 35,-13, 13,35
    db -36,6, 36,-6, 6,36
    db -37,0, 37,0, 0,37
    db -36,-6, 36,6, -6,36
    db -35,-13, 35,13, -13,35
    db -32,-18, 32,18, -19,32
    db -28,-24, 28,24, -24,28

; ---- bonnet curve: half width of each row, from y = 143 + (x-160)^2/1067 ----
bonnet_hw:
    db 32, 46, 56, 65, 73, 80, 86, 92
    db 97, 103, 108, 113, 117, 122, 126, 130
    db 134, 138, 142, 146, 149, 153, 156, 160
    db 160