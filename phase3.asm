; =====================================================================
;  DR. DRIVING LITE  -  COAL Final Project  (8088 assembly, NASM, .COM)
;  PHASE 3 : PARKING  (final program, Phases 1 and 2 included)
;  Build :  nasm phase3.asm -o phase3.com
;
;  Menu: UP / DOWN / ENTER  or  1 2 3.   Game: UP gas, SPACE brake, DOWN reverse,
;  LEFT / RIGHT lanes (steer), C camera, ESC pause menu.
;  Highway (Phase 2), Parking (Phase 3) and the garage.
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
dtab10: times 11 db 0
dtab8:  times 9 db 0
dtab6:  times 7 db 0

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
        call build_invmap
        call load_game
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
        cmp  cx, 2
        jb   ml_fast
        inc  byte [slow]         ; a frame took longer than a tick
        cmp  byte [slow], 40
        jb   ml_cap
        mov  byte [autooff], 1   ; too slow for the edge smoothing: pause it
        mov  byte [slow], 0
        jmp  ml_cap
ml_fast: mov byte [slow], 0
ml_cap: cmp  cx, 3
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
        mov  si, dtab10
        mov  cx, 10
        call build_disc
        mov  si, dtab8
        mov  cx, 8
        call build_disc
        mov  si, dtab6
        mov  cx, 6
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

; ------------------------------------------------------ video memory
; present: the finished picture is copied to video memory (segment A000);
; with smoothing on, the stair steps of slanted and round edges are then
; softened by blending the two pixels that meet at an edge
present:
        push ds
        push es
        push bp
        mov  ax, [bseg]
        mov  ds, ax
        mov  ax, 0xA000
        mov  es, ax
        xor  si, si
        xor  di, di
        mov  cx, 32000
        rep  movsw
        pop  bp
        pop  es
        pop  ds
        cmp  byte [smooth], 0
        je   pr_x
        cmp  byte [autooff], 0
        jne  pr_x
        call smooth_edges
pr_x:   ret

; blend12: bx = colour a, ax = colour b (packed 4+4+4 bit r,g,b)  ->  ax = average
blend12:
        push cx
        mov  cx, bx
        and  cx, ax
        xor  ax, bx
        shr  ax, 1
        and  ax, 0x0777
        add  ax, cx
        pop  cx
        ret

; aa_pair: the pixels at [si-1] and [di-1] of the picture meet at an edge.
; 3/4 of their own colour and 1/4 of the neighbour is written to the screen.
aa_pair:
        mov  al, [si-1]
        mov  ah, [di-1]
        mov  cl, al
        sub  cl, ah
        jnc  ap1
        neg  cl
ap1:    cmp  cl, 2               ; neighbours in the same gradient: leave
        jbe  ap_x
        mov  dx, 0xA000
        mov  es, dx
        mov  al, [es:si-1]
        mov  ah, [es:di-1]
        xor  bh, bh
        mov  bl, al
        shl  bx, 1
        mov  dx, [cs:rgb12+bx]
        mov  [cs:aa_rp], dx
        xor  bh, bh
        mov  bl, ah
        shl  bx, 1
        mov  dx, [cs:rgb12+bx]
        mov  [cs:aa_rq], dx
        mov  bx, [cs:aa_rp]
        mov  ax, [cs:aa_rq]
        call blend12
        mov  [cs:aa_m], ax
        mov  bx, [cs:aa_rp]
        call blend12             ; ax = 3/4 p + 1/4 q
        mov  bx, ax
        mov  al, [cs:invmap+bx]
        mov  [es:si-1], al
        mov  bx, [cs:aa_rq]
        mov  ax, [cs:aa_m]
        call blend12
        mov  bx, ax
        mov  al, [cs:invmap+bx]
        mov  [es:di-1], al
        mov  es, bp
ap_x:   ret

smooth_edges:
        push ds
        push es
        push bp
        mov  bp, [bseg]
        mov  ds, bp
        mov  es, bp
        ; pairs side by side
        xor  si, si
sm_row: mov  di, si
        inc  di
        mov  cx, 319
sm_h:   repe cmpsb
        jz   sm_hn
        push cx
        push si
        push di
        call aa_pair
        pop  di
        pop  si
        pop  cx
        or   cx, cx
        jnz  sm_h
sm_hn:  mov  si, di
        cmp  si, 64000
        jb   sm_row
        ; pairs on top of each other
        xor  si, si
        mov  di, 320
        mov  cx, 63680
sm_v:   repe cmpsb
        jz   sm_end
        push cx
        push si
        push di
        call aa_pair
        pop  di
        pop  si
        pop  cx
        or   cx, cx
        jnz  sm_v
sm_end: pop  bp
        pop  es
        pop  ds
        ret

slow:   db 0
autooff: db 0
aa_rp: dw 0
aa_rq: dw 0
aa_m:  dw 0
invmap: times 4096 db 0
rgb12:  times 256 dw 0

; ---------------------------------------------- colour gradients (VGA DAC)
; the 16 basic colours (r,g,b in 0..63)
ega_tab:
        db 0,0,0,      10,14,40,   10,36,16,   10,40,44
        db 44,6,8,     34,12,40,   40,22,6,    40,42,46
        db 20,22,26,   26,40,63,   28,58,32,   30,58,63
        db 63,26,22,   58,28,58,   63,58,20,   63,63,63
; each gradient: first colour, how many, start r,g,b, end r,g,b
pal_defs:
        db 16,22,  6,26,56,   46,56,63    ; sky (22 bands)
        db 38,24,  30,31,35,  11,12,14    ; asphalt, far = light ... near = dark
        db 62,24,  35,36,40,  15,16,18    ; asphalt, second stripe
        db 86,16,  42,43,46,  50,51,54    ; pavement
        db 102,16, 39,40,43,  47,48,51    ; pavement, second stripe
        db 118,12, 28,10,2,   63,50,22    ; paint 0  orange
        db 130,12, 6,10,30,   36,48,63    ; paint 1  blue
        db 142,12, 28,2,4,    63,28,26    ; paint 2  red
        db 154,12, 4,22,10,   34,58,40    ; paint 3  green
        db 166,12, 34,26,2,   63,60,26    ; paint 4  yellow
        db 178,12, 14,15,18,  63,63,63    ; paint 5  silver
        db 190,12, 3,5,14,    30,44,60    ; glass
        db 202,4,  30,40,52,  18,26,38    ; haze (distant buildings)
        db 206,16, 2,2,3,     40,41,44    ; dashboard greys
        db 222,4,  5,5,7,     14,14,16    ; soft shadow
        db 226,8,  30,16,2,   63,52,10    ; gold
        db 234,16, 4,6,16,    16,24,52    ; night blue (panels, garage)
        db 250,6,  24,26,30,  62,62,64    ; chrome
        db 0
rp_s: db 0
rp_n: dw 0
rp_c: times 6 db 0
rp_v: times 3 db 0

; setcol: ax = colour number, rp_v = r,g,b  ->  DAC and our own copy
setcol: push ax
        push bx
        push cx
        push dx
        mov  bx, ax
        mov  dx, 0x3C8
        out  dx, al
        inc  dx
        mov  al, [rp_v]
        out  dx, al
        mov  al, [rp_v+1]
        out  dx, al
        mov  al, [rp_v+2]
        out  dx, al
        mov  cl, 2
        mov  al, [rp_v]
        shr  al, cl
        mov  ah, al              ; ah = red / 4
        mov  al, [rp_v+1]
        shr  al, cl
        mov  cl, 4
        shl  al, cl
        mov  dl, [rp_v+2]
        mov  cl, 2
        shr  dl, cl
        or   al, dl              ; al = green * 16 + blue
        shl  bx, 1
        mov  [rgb12+bx], ax
        pop  dx
        pop  cx
        pop  bx
        pop  ax
        ret

setpal: push ax
        push bx
        push cx
        push dx
        push si
        push di
        mov  si, ega_tab
        xor  bx, bx
pl_e:   lodsb
        mov  [rp_v], al
        lodsb
        mov  [rp_v+1], al
        lodsb
        mov  [rp_v+2], al
        mov  ax, bx
        call setcol
        inc  bx
        cmp  bx, 16
        jb   pl_e
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
pl_i:   xor  di, di
pl_c:   mov  al, [rp_c+di+3]
        sub  al, [rp_c+di]
        cbw
        imul bx
        mov  cx, [rp_n]
        dec  cx
        idiv cx
        add  al, [rp_c+di]
        mov  [rp_v+di], al
        inc  di
        cmp  di, 3
        jb   pl_c
        xor  ah, ah
        mov  al, [rp_s]
        add  ax, bx
        call setcol
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

; build_invmap: for every colour of a 16 x 16 x 16 colour cube, the number of
; the closest palette entry (palette entries are marked first, then the
; empty cells are filled from their neighbours)
build_invmap:
        push ax
        push bx
        push cx
        push dx
        push si
        push di
        push es
        push ds
        pop  es
        mov  di, invd
        mov  cx, 2048
        xor  ax, ax
        rep  stosw
        xor  bx, bx
bi1:    mov  si, bx
        shl  si, 1
        mov  si, [rgb12+si]
        cmp  byte [invd+si], 0
        jne  bi2
        mov  byte [invd+si], 1
        mov  ax, bx
        mov  [invmap+si], al
bi2:    inc  bx
        cmp  bx, 256
        jb   bi1
        mov  byte [bi_pass], 2
bi3:    xor  dx, dx              ; cells filled in this pass
        xor  si, si
bi4:    cmp  byte [invd+si], 0
        jne  bi9
        mov  ax, si
        and  ax, 15
        jz   bi5
        mov  bx, si
        dec  bx
        call bi_try
        jc   bi8
bi5:    mov  ax, si
        and  ax, 15
        cmp  ax, 15
        je   bi6
        mov  bx, si
        inc  bx
        call bi_try
        jc   bi8
bi6:    mov  ax, si
        and  ax, 0xF0
        jz   bi7
        mov  bx, si
        sub  bx, 16
        call bi_try
        jc   bi8
bi7:    mov  ax, si
        and  ax, 0xF0
        cmp  ax, 0xF0
        je   bi7a
        mov  bx, si
        add  bx, 16
        call bi_try
        jc   bi8
bi7a:   cmp  si, 256
        jb   bi7b
        mov  bx, si
        sub  bx, 256
        call bi_try
        jc   bi8
bi7b:   cmp  si, 3840
        jae  bi9
        mov  bx, si
        add  bx, 256
        call bi_try
        jc   bi8
        jmp  bi9
bi8:    mov  [invmap+si], al
        mov  al, [bi_pass]
        mov  [invd_new], al      ; remember that this cell is new
        mov  [invnew+si], al
        inc  dx
bi9:    inc  si
        cmp  si, 4096
        jb   bi4
        or   dx, dx
        jz   bi_x
        ; cells filled in this pass become usable for the next one
        xor  si, si
bi10:   mov  al, [invnew+si]
        or   al, al
        jz   bi11
        mov  [invd+si], al
        mov  byte [invnew+si], 0
bi11:   inc  si
        cmp  si, 4096
        jb   bi10
        inc  byte [bi_pass]
        jmp  bi3
bi_x:   pop  es
        pop  di
        pop  si
        pop  dx
        pop  cx
        pop  bx
        pop  ax
        ret

; bi_try: cell bx was filled in an earlier pass?  carry set and al = colour
bi_try: cmp  byte [invd+bx], 0
        je   bt_no
        mov  al, [invd+bx]
        cmp  al, [bi_pass]
        jae  bt_no
        mov  al, [invmap+bx]
        stc
        ret
bt_no:  clc
        ret

bi_pass: db 2
invd_new: db 0
invd:    times 4096 db 0
invnew:  times 4096 db 0

; ------------------------------------------------ saved game (DOS files)
savefile: db "DRDRIVE.SAV",0
sv_sig:   db 0
bank:     dw 0                  ; points collected
unl:      db 1                  ; bit mask of the unlocked cars
selcar:   db 0
usercam:  db 1
smooth:   db 1
sv_end:
SAVELEN   equ 7

save_game:
        push ax
        push bx
        push cx
        push dx
        mov  byte [sv_sig], 0xD5
        mov  dx, savefile
        xor  cx, cx
        mov  ah, 0x3C            ; create file
        int  0x21
        jc   sv_x
        mov  bx, ax
        mov  dx, sv_sig
        mov  cx, SAVELEN
        mov  ah, 0x40            ; write
        int  0x21
        mov  ah, 0x3E            ; close
        int  0x21
sv_x:   pop  dx
        pop  cx
        pop  bx
        pop  ax
        ret

load_game:
        push ax
        push bx
        push cx
        push dx
        mov  dx, savefile
        mov  ax, 0x3D00          ; open for reading
        int  0x21
        jc   ld_x
        mov  bx, ax
        mov  dx, sv_sig
        mov  cx, SAVELEN
        mov  ah, 0x3F            ; read
        int  0x21
        mov  ah, 0x3E
        int  0x21
        cmp  byte [sv_sig], 0xD5
        je   ld_x
        mov  word [bank], 0      ; not our file: start from scratch
        mov  byte [unl], 1
        mov  byte [selcar], 0
        mov  byte [usercam], 1
        mov  byte [smooth], 1
ld_x:   pop  dx
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
state:    db 0                  ; 0 menu, 1 highway, 2 parking, 3 message, 4 garage, 5 pause
cam:      db 0                  ; camera: 0 cockpit, 1 chase, 2 high chase
camnote:  dw 0
msel:     db 0                  ; selected line of the main menu
psel:     db 0                  ; selected line of the pause menu
gsel:     db 0                  ; car shown in the garage
gmsg:     dw 0                  ; garage message timer
earned:   dw 0
glide:    dw 4                  ; sideways speed of the camera (car handling)
cam_hi:   dw 1
cam_lo:   dw 0x5E00
cam_lwm:  dw 8
cam_lwa:  dw 7
cam_cb:   dw 0
cam_gnd:  dw 167
cam_jmin: dw 0
cam_kmin: dw 2
; the cars you can drive
car_vmax:  dw 2240,2400,2640,2400,3040
car_acc:   db 7,7,6,7,6
car_brk:   dw 24,26,30,26,36
car_glide: dw 4,4,5,3,6
car_price: dw 0,2500,6000,10000,16000
car_pntof: db 0,1,2,3,4
car_dsgof: db 0,1,2,3,4
; camera tables: hi, lo (distance constant), lane scale, lane base, camera back, last ground row, first building
camh_tab: dw 1,0x5E00,8,7,0,167,0
          dw 2,43228,5,7,800,200,-1
          dw 4,1856,4,7,2000,200,-2
camp_tab: dw 0,18560,16,20,0,167,0
          dw 0,55000,8,15,900,200,0
          dw 1,39464,6,12,1500,200,0

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
car_pnt:  dw 1,5,3,2,4,0,1,3,2,5       ; paint of every traffic car
car_des:  dw 1,0,3,2,4,1,0,2,3,1       ; body shape of every traffic car
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
        mov  byte [cam], 1
        call set_cam
        call apply_car
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
        cmp  al, 4
        je   u_gar
        cmp  al, 5
        je   u_pause
        jmp  upd_menu
u_hwy:  jmp  upd_hwy
u_park: jmp  upd_park
u_end:  jmp  upd_end
u_gar:  jmp  upd_garage
u_pause: jmp upd_pause

; set_cam: loads the numbers of the chosen camera (cam) for the world shown
set_cam:
        push ax
        push bx
        push cx
        push si
        push di
        xor  ah, ah
        mov  al, [cam]
        mov  bx, 14
        mul  bx
        mov  si, camh_tab
        cmp  byte [scene], 2
        jne  sc1
        mov  si, camp_tab
sc1:    add  si, ax
        mov  di, cam_hi
        mov  cx, 7
sc2:    lodsw
        mov  [di], ax
        add  di, 2
        loop sc2
        mov  ax, [cam_hi]
        inc  ax
        mov  [cam_kmin], ax
        pop  di
        pop  si
        pop  cx
        pop  bx
        pop  ax
        ret

; next_cam: C key / pause menu
next_cam:
        mov  al, [usercam]
        inc  al
        cmp  al, 3
        jb   nc1
        xor  al, al
nc1:    mov  [usercam], al
        mov  [cam], al
        call set_cam
        mov  word [camnote], 150
        call save_game
        ret

; apply_car: speed, acceleration, brakes and handling of the chosen car
apply_car:
        push ax
        push bx
        xor  bh, bh
        mov  bl, [selcar]
        mov  ax, bx
        shl  bx, 1
        mov  ax, [car_vmax+bx]
        mov  [vmax], ax
        mov  ax, [car_brk+bx]
        mov  [brk], ax
        mov  ax, [car_glide+bx]
        mov  [glide], ax
        mov  bl, [selcar]
        xor  bh, bh
        mov  al, [car_acc+bx]
        mov  [accsh], al
        pop  bx
        pop  ax
        ret

; ---------------------------------------------------------------- menu
upd_menu:
        mov  word [advp], 15
        mov  ax, [odo]
        add  ax, 15
        mov  [odo], ax
        call traffic_update
        mov  al, [lastkey]
        mov  byte [lastkey], 0
        cmp  al, 0x48
        jne  um1
        mov  al, [msel]
        dec  al
        and  al, 3
        mov  [msel], al
        ret
um1:    cmp  al, 0x50
        jne  um2
        mov  al, [msel]
        inc  al
        and  al, 3
        mov  [msel], al
        ret
um2:    cmp  al, 2
        je   um_hwy
        cmp  al, 3
        je   um_park
        cmp  al, 4
        je   um_gar
        cmp  al, 1
        je   um_quit
        cmp  al, 0x1C
        jne  um_x
        mov  al, [msel]
        or   al, al
        jz   um_hwy
        cmp  al, 1
        je   um_park
        cmp  al, 2
        je   um_gar
um_quit:
        mov  byte [quitflag], 1
um_x:   ret
um_hwy: jmp  hwy_start
um_park: jmp park_start
um_gar: mov  byte [state], 4
        mov  al, [selcar]
        mov  [gsel], al
        mov  word [gmsg], 0
        ret

; ---------------------------------------------------------------- garage
upd_garage:
        cmp  word [gmsg], 0
        je   ug0
        dec  word [gmsg]
ug0:    mov  al, [lastkey]
        mov  byte [lastkey], 0
        cmp  al, 1
        jne  ug1
        mov  byte [state], 0
        ret
ug1:    cmp  al, 0x4B
        jne  ug2
        mov  al, [gsel]
        or   al, al
        jnz  ug1a
        mov  al, 5
ug1a:   dec  al
        mov  [gsel], al
        ret
ug2:    cmp  al, 0x4D
        jne  ug3
        mov  al, [gsel]
        inc  al
        cmp  al, 5
        jb   ug2a
        xor  al, al
ug2a:   mov  [gsel], al
        ret
ug3:    cmp  al, 0x1C
        je   ug4
        cmp  al, 0x39
        je   ug4
        ret
ug4:    xor  bh, bh
        mov  bl, [gsel]
        mov  cl, bl
        mov  al, 1
        shl  al, cl
        test [unl], al
        jnz  ug6                 ; already owned: just choose it
        shl  bx, 1
        mov  dx, [car_price+bx]
        cmp  [bank], dx
        jb   ug5
        sub  [bank], dx          ; pay with points and unlock
        or   [unl], al
        jmp  ug6
ug5:    mov  word [gmsg], 90     ; not enough points
        ret
ug6:    mov  al, [gsel]
        mov  [selcar], al
        mov  word [gmsg], 0
        call apply_car
        call save_game
        ret

; ------------------------------------------------------------ pause menu
upd_pause:
        mov  al, [lastkey]
        mov  byte [lastkey], 0
        cmp  al, 1
        je   pa_resume
        cmp  al, 0x48
        jne  pa1
        mov  al, [psel]
        or   al, al
        jnz  pa0
        mov  al, 5
pa0:    dec  al
        mov  [psel], al
        ret
pa1:    cmp  al, 0x50
        jne  pa2
        mov  al, [psel]
        inc  al
        cmp  al, 5
        jb   pa1a
        xor  al, al
pa1a:   mov  [psel], al
        ret
pa2:    cmp  al, 0x1C
        je   pa_go
        cmp  al, 0x39
        je   pa_go
        cmp  al, 0x4B
        je   pa_side
        cmp  al, 0x4D
        je   pa_side
        ret
pa_side: mov  al, [psel]
        cmp  al, 2
        je   pa_cam
        cmp  al, 3
        je   pa_sm
        ret
pa_go:  mov  al, [psel]
        or   al, al
        jz   pa_resume
        cmp  al, 1
        je   pa_restart
        cmp  al, 2
        je   pa_cam
        cmp  al, 3
        je   pa_sm
        jmp  menu_reset
pa_resume:
        mov  al, [scene]
        mov  [state], al
        ret
pa_restart:
        cmp  byte [scene], 2
        je   pa_rp
        jmp  hwy_start
pa_rp:  jmp  park_start
pa_cam: call next_cam
        ret
pa_sm:  xor  byte [smooth], 1
        mov  byte [autooff], 0
        call save_game
        ret

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
        mov  al, [usercam]
        mov  [cam], al
        call set_cam
        call apply_car
        mov  word [spd], 0
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
        call level_keys
        cmp  byte [state], 1
        je   uh0
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
        ; the score of the run is added to your points
        mov  ax, [score]
        mov  [earned], ax
        add  ax, [bank]
        jnc  el1
        mov  ax, 0xFFFF
el1:    mov  [bank], ax
        call save_game
        ret

; level_keys: ESC opens the pause menu, C changes the camera
level_keys:
        mov  al, [lastkey]
        mov  byte [lastkey], 0
        cmp  al, 1
        jne  lk1
        mov  byte [state], 5
        mov  byte [psel], 0
        ret
lk1:    cmp  al, 0x2E
        jne  lk2
        call next_cam
lk2:    cmp  word [camnote], 0
        je   lk3
        dec  word [camnote]
lk3:    ret

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
li_r:   add  bx, [glide]
        cmp  bx, ax
        jle  li5
        mov  bx, ax
        jmp  li5
li_l:   sub  bx, [glide]
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
        mov  al, [usercam]
        mov  [cam], al
        call set_cam
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
        call level_keys
        cmp  byte [state], 2
        je   up0
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
c_W:  dw 0
c_H:  dw 0
c_sh: dw 0
c_bh: dw 0
c_x0: dw 0
c_ytb: dw 0
c_xc: dw 0
c_wc: dw 0
c_yc: dw 0
c_t:  dw 0
tdone: times NC dw 0
t_cnt: dw 0
pdrawn: dw 0
pp_x: dw 0
pp_z: dw 0
sc_t: dw 0

bld_ht:  db 7,10,8,12,9,6,11,8
bld_col: db 5,0,1,5,3,4,5,1
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
s_camt:  db "CAMERA  ",0
s_cam0:  db "COCKPIT",0
s_cam1:  db "CHASE",0
s_cam2:  db "HIGH CHASE",0
cam_names: dw s_cam0,s_cam1,s_cam2
s_touch: db "TOUCH  -50",0


game_render:
        cmp  byte [state], 4
        jne  gr0
        jmp  render_garage
gr0:    cmp  byte [scene], 2
        je   gr_p
        call render_highway
        jmp  gr_c
gr_p:   call render_parking
gr_c:   cmp  byte [state], 0
        je   gr_menu
        cmp  byte [cam], 0
        jne  gr_ch
        call draw_cockpit
        jmp  gr_h
gr_ch:  call draw_chase_hud
gr_h:   call draw_hud
        mov  al, [state]
        cmp  al, 3
        je   gr_end
        cmp  al, 5
        je   gr_pause
        cmp  word [crash], 0
        je   gr_cn
        test byte [crash], 8
        jz   gr_cn
        mov  si, s_crash
        cmp  byte [scene], 2
        jne  gr_c2
        mov  si, s_touch
gr_c2:  mov  bx, 100
        mov  dx, 66
        mov  al, 12
        mov  ah, 2
        call puts_sh
gr_cn:  cmp  word [camnote], 0
        je   gr_x
        mov  si, s_camt
        mov  bx, 112
        mov  dx, 32
        mov  al, 7
        mov  ah, 1
        call puts_sh
        xor  bh, bh
        mov  bl, [cam]
        shl  bx, 1
        mov  si, [cam_names+bx]
        mov  bx, [t_x]
        mov  dx, 32
        mov  al, 14
        mov  ah, 1
        call puts_sh
gr_x:   ret
gr_menu: call draw_menu
        ret
gr_end: call draw_endpanel
        ret
gr_pause: call draw_pause
        ret

; ------------------------------------------------------------ sky
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
        shr  ax, 1
        shr  ax, 1               ; 4 rows share one colour of the gradient
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

; a soft round cloud: bx = x, dx = y
cloud:  push ax
        push bx
        push cx
        push dx
        push si
        mov  [c_xc], bx
        mov  [c_yc], dx
        ; shaded underside
        mov  si, dtab8
        mov  cx, 8
        mov  bx, [c_xc]
        add  bx, 10
        mov  dx, [c_yc]
        add  dx, 4
        mov  al, 11
        call drawdisc
        ; white puffs
        mov  si, dtab8
        mov  cx, 8
        mov  bx, [c_xc]
        mov  dx, [c_yc]
        mov  al, 15
        call drawdisc
        mov  si, dtab10
        mov  cx, 10
        mov  bx, [c_xc]
        add  bx, 11
        mov  dx, [c_yc]
        sub  dx, 3
        call drawdisc
        mov  si, dtab8
        mov  cx, 8
        mov  bx, [c_xc]
        add  bx, 22
        mov  dx, [c_yc]
        call drawdisc
        pop  si
        pop  dx
        pop  cx
        pop  bx
        pop  ax
        ret

draw_sky_hwy:
        mov  cx, 88
        call skyrows
        mov  bx, 40
        mov  dx, 30
        call cloud
        mov  bx, 205
        mov  dx, 40
        call cloud
        ; far away skyline
        xor  si, si
sk1:    xor  ax, ax
        mov  al, [sky_h+si]
        mov  [c_t], ax
        mov  ax, si
        mov  bx, 20
        mul  bx
        mov  [c_xc], ax
        mov  ax, 88
        sub  ax, [c_t]
        mov  [c_yc], ax
        mov  bx, 202
        test si, 2
        jz   sk2
        mov  bx, 203
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
        mul  word [cam_lwm]
        mov  cl, 3
        shr  ax, cl
        add  ax, [cam_lwa]
        mov  [g_lw], ax          ; width of a lane on this row
        mov  bx, [g_k]
        cmp  bx, [cam_kmin]
        jae  gh1
        mov  bx, [cam_kmin]
gh1:    mov  dx, [cam_hi]
        mov  ax, [cam_lo]
        div  bx                  ; distance of this row
        sub  ax, [cam_cb]
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
        ; pavement on both sides
        mov  ax, [g_k]
        mov  cl, 3
        shr  ax, cl
        cmp  ax, 15
        jbe  gh2a
        mov  ax, 15
gh2a:   add  ax, 86
        test word [g_zw], 512
        jz   gh2
        add  ax, 16
gh2:    xor  cx, cx
        mov  dx, [g_xl]
        call span
        mov  cx, [g_xr]
        mov  dx, 320
        call span
        ; asphalt: lighter far away, darker near
        mov  ax, [g_k]
        shr  ax, 1
        shr  ax, 1
        cmp  ax, 23
        jbe  gh3a
        mov  ax, 23
gh3a:   add  ax, 38
        test word [g_zw], 512
        jz   gh3
        add  ax, 24
gh3:    mov  cx, [g_xl]
        add  cx, [g_ew]
        mov  dx, [g_xr]
        sub  dx, [g_ew]
        call span
        ; white edge lines
        mov  al, 15
        mov  cx, [g_xl]
        mov  dx, cx
        add  dx, [g_ew]
        call span
        mov  dx, [g_xr]
        mov  cx, dx
        sub  cx, [g_ew]
        call span
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
        mov  al, 15
        mov  cx, [g_cx]
        sub  cx, si
        mov  dx, [g_dw]
        shr  dx, 1
        sub  cx, dx
        mov  dx, cx
        add  dx, [g_dw]
        call span
        mov  cx, [g_cx]
        add  cx, si
        mov  dx, [g_dw]
        shr  dx, 1
        sub  cx, dx
        mov  dx, cx
        add  dx, [g_dw]
        call span
gh_nd:  inc  word [g_y]
        mov  ax, [cam_gnd]
        cmp  [g_y], ax
        jae  gh_dn
        jmp  gh_row
gh_dn:  ret

; ------------------------------------------------------- buildings
; b_project: ax = distance z (camera space, >= 448);
;            sets b_k, b_lw, b_yb, b_cx
b_project:
        mov  bx, ax
        mov  dx, [cam_hi]
        mov  ax, [cam_lo]
        div  bx
        mov  [b_k], ax
        mul  word [cam_lwm]
        mov  cl, 3
        shr  ax, cl
        add  ax, [cam_lwa]
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
        add  ax, [cam_cb]
        cmp  ax, 448
        jl   bl_nx
        mov  [b_z], ax
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
        mov  ax, [b_j]
        cmp  ax, [cam_jmin]
        jl   bl_dn
        jmp  bl_lp
bl_dn:  ret

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
        mov  bx, ax
        shl  ax, 1
        add  ax, bx
        shl  ax, 1
        shl  ax, 1
        add  ax, 118             ; paint ramp of this building
        mov  [c_t], ax
        mov  ax, [b_yb]
        sub  ax, [b_h]
        mov  [c_yc], ax
        mov  ax, [c_t]
        add  ax, 5
        mov  [c_wc], ax
        RECT [b_x0],[c_yc],[b_bw],[b_h],[c_wc]
        ; lit and shaded sides, roof edge: the building looks round
        mov  ax, [b_bw]
        mov  cl, 4
        shr  ax, cl
        inc  ax
        mov  [c_H], ax
        mov  ax, [c_t]
        add  ax, 8
        mov  [c_wc], ax
        RECT [b_x0],[c_yc],[c_H],[b_h],[c_wc]
        mov  ax, [b_x0]
        add  ax, [b_bw]
        sub  ax, [c_H]
        mov  [c_xc], ax
        mov  ax, [c_t]
        add  ax, 2
        mov  [c_wc], ax
        RECT [c_xc],[c_yc],[c_H],[b_h],[c_wc]
        mov  ax, [c_t]
        add  ax, 10
        mov  [c_wc], ax
        RECT [b_x0],[c_yc],[b_bw],[c_H],[c_wc]
        ; shop front
        mov  ax, [b_lw]
        shr  ax, 1
        inc  ax
        mov  [b_ph], ax
        mov  ax, [b_yb]
        sub  ax, [b_ph]
        mov  [c_yc], ax
        RECT [b_x0],[c_yc],[b_bw],[b_ph],211
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
        mov  [b_wh], ax
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
        mov  word [c_t], 195
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

; ------------------------------------------------------ player's car
; (seen from behind in the chase camera)
draw_player:
        mov  ax, [cam_cb]
        add  ax, 1300
        call b_project
        mov  ax, [b_yb]
        mov  [dc_yb], ax
        mov  ax, [b_lw]
        mov  [dc_lw], ax
        mov  ax, [wheel]
        mov  bx, 3
        imul bx
        add  ax, 160
        mov  [dc_cx], ax
        call player_look
        ret

; player_look: shape, paint and brake lights of the car you drive
player_look:
        xor  bh, bh
        mov  bl, [selcar]
        mov  al, [car_dsgof+bx]
        xor  ah, ah
        mov  [dc_des], ax
        mov  al, [car_pntof+bx]
        xor  ah, ah
        mov  [dc_pnt], ax
        mov  word [dc_brk], 0
        cmp  byte [keys+0x39], 0
        je   pl1
        mov  word [dc_brk], 1
pl1:    call drawcar
        ret

; traffic, drawn from the far one to the near one
draw_traffic:
        mov  word [pdrawn], 0
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
        add  dx, [cam_cb]        ; distance seen from the camera
        cmp  byte [cam], 0
        je   dt_c
        cmp  word [pdrawn], 0
        jne  dt_c
        mov  ax, [cam_cb]
        add  ax, 1300
        cmp  dx, ax
        jge  dt_c
        push si
        push dx
        call draw_player         ; this car is nearer than yours: yours first
        pop  dx
        pop  si
        mov  word [pdrawn], 1
dt_c:   cmp  dx, 448
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
        mov  ax, [car_pnt+si]
        mov  [dc_pnt], ax
        mov  ax, [car_des+si]
        mov  [dc_des], ax
        mov  word [dc_brk], 0
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
dt_end: cmp  byte [cam], 0
        je   dt_x
        cmp  word [pdrawn], 0
        jne  dt_x
        call draw_player
dt_x:   ret

render_highway:
        call draw_sky_hwy
        call draw_ground_hwy
        call draw_buildings
        call draw_traffic
        ret

; =====================================================================
;                         CAR  PAINTER  (rear view)
;  every car is drawn row by row: a rounded roof, glass with a gradient,
;  a shaded body, tail lights, bumper, tyres - all in smooth colour ramps
; =====================================================================
dc_cx:  dw 0
dc_yb:  dw 0
dc_lw:  dw 0
dc_des: dw 0
dc_pnt: dw 0
dc_brk: dw 0
cW:     dw 0
cHt:     dw 0
cCab:   dw 0
cCth:   dw 0
cCbh:   dw 0
cW2:    dw 0
cWh:    dw 0
cUnder: dw 0
cRc:    dw 0
cEw:    dw 0
cPb:    dw 0
cTop:   dw 0
cBodyH: dw 0
cR:     dw 0
cRb:    dw 0
cY:     dw 0
cHw:    dw 0
cCol:   dw 0
cG0:    dw 0
cG1:    dw 0
cGl:    dw 0
cGm:    dw 0
cT0:    dw 0
cT1:    dw 0
cLw:    dw 0
cSpoil: dw 0
cTmp:   dw 0
; per design: height/width (x16), cabin rows (x16), cabin bottom width,
;             cabin top width (x32 of the car width), spoiler
dsg_tab: db 10,7,26,22,0        ; city hatch
         db 9,6,24,18,0         ; sedan
         db 8,5,25,15,0         ; coupe
         db 12,8,28,25,0        ; suv
         db 7,4,24,13,1         ; super gt

; dc_hspan: one row of the car (row cY, half width cHw, colour cCol) with
; darker edges so the body looks round
dc_hspan:
        mov  bx, [cY]
        mov  cx, [dc_cx]
        sub  cx, [cHw]
        mov  dx, [dc_cx]
        add  dx, [cHw]
        inc  dx
        mov  ax, [cCol]
        call span
        mov  ax, [cCol]
        sub  ax, 3
        mov  bx, [cY]
        mov  cx, [dc_cx]
        sub  cx, [cHw]
        mov  dx, cx
        add  dx, [cEw]
        call span
        mov  cx, [dc_cx]
        add  cx, [cHw]
        inc  cx
        mov  dx, cx
        sub  cx, [cEw]
        call span
        ret

; dc_plain: row cY, half width cHw, one colour (cCol)
dc_plain:
        mov  bx, [cY]
        mov  cx, [dc_cx]
        sub  cx, [cHw]
        mov  dx, [dc_cx]
        add  dx, [cHw]
        inc  dx
        mov  ax, [cCol]
        call span
        ret

; dc_box: row cY, from x = cx to dx (exclusive), colour cCol
dc_box: mov  bx, [cY]
        mov  ax, [cCol]
        call span
        ret

drawcar:
        mov  ax, [dc_lw]
        mov  bx, ax
        shl  ax, 1
        shl  ax, 1
        shl  ax, 1
        sub  ax, bx
        mov  cl, 3
        shr  ax, cl              ; W = 7/8 of the lane
        cmp  ax, 3
        jae  dcw1
        mov  ax, 3
dcw1:   mov  [cW], ax
        cmp  ax, 14
        jae  dc_big
        jmp  drawcar_small
dc_big: mov  bx, [dc_des]
        mov  ax, bx
        shl  ax, 1
        shl  ax, 1
        add  ax, bx
        add  ax, dsg_tab
        mov  si, ax
        lodsb
        xor  ah, ah
        mul  word [cW]
        mov  cl, 4
        shr  ax, cl
        mov  [cHt], ax
        lodsb
        xor  ah, ah
        mul  word [cHt]
        mov  cl, 4
        shr  ax, cl
        cmp  ax, 4
        jae  dc1
        mov  ax, 4
dc1:    mov  [cCab], ax
        lodsb
        xor  ah, ah
        mul  word [cW]
        mov  cl, 6
        shr  ax, cl
        mov  [cCbh], ax
        lodsb
        xor  ah, ah
        mul  word [cW]
        mov  cl, 6
        shr  ax, cl
        mov  [cCth], ax
        lodsb
        xor  ah, ah
        mov  [cSpoil], ax
        mov  ax, [cW]
        shr  ax, 1
        mov  [cW2], ax
        mov  ax, [cHt]
        mov  bx, ax
        shl  ax, 1
        add  ax, bx
        mov  cl, 4
        shr  ax, cl
        cmp  ax, 2
        jae  dc2
        mov  ax, 2
dc2:    mov  [cWh], ax
        shr  ax, 1
        cmp  ax, 1
        jae  dc3
        mov  ax, 1
dc3:    mov  [cUnder], ax
        mov  ax, [cW]
        mov  cl, 3
        shr  ax, cl
        cmp  ax, 2
        jae  dc4
        mov  ax, 2
dc4:    mov  [cRc], ax
        mov  ax, [cW]
        mov  cl, 5
        shr  ax, cl
        inc  ax
        mov  [cEw], ax
        mov  ax, [dc_pnt]
        mov  bx, ax
        shl  ax, 1
        add  ax, bx
        shl  ax, 1
        shl  ax, 1
        add  ax, 118
        mov  [cPb], ax
        mov  ax, [dc_yb]
        sub  ax, [cHt]
        inc  ax
        mov  [cTop], ax
        mov  ax, [cHt]
        sub  ax, [cCab]
        sub  ax, [cUnder]
        cmp  ax, 3
        jge  dc5
        mov  ax, 3
dc5:    mov  [cBodyH], ax
        ; glass rows
        mov  ax, [cCab]
        shr  ax, 1
        shr  ax, 1
        mov  [cG0], ax
        mov  ax, [cCab]
        mov  bx, ax
        shr  bx, 1
        shr  bx, 1
        shr  bx, 1
        sub  ax, bx
        dec  ax
        mov  [cG1], ax
        sub  ax, [cG0]
        cmp  ax, 1
        jge  dc6
        mov  ax, 1
dc6:    mov  [cGl], ax
        mov  ax, [cW]
        mov  cl, 4
        shr  ax, cl
        inc  ax
        mov  [cGm], ax
        ; soft shadow on the road
        mov  ax, [cW2]
        mov  bx, [cW]
        shr  bx, 1
        shr  bx, 1
        add  ax, bx
        mov  [cTmp], ax
        mov  word [cCol], 222
        mov  word [cR], 0
dc_sh:  mov  bx, [dc_yb]
        inc  bx
        add  bx, [cR]
        mov  cx, [dc_cx]
        sub  cx, [cTmp]
        mov  dx, [dc_cx]
        add  dx, [cTmp]
        mov  ax, [cCol]
        call span
        sub  word [cTmp], 2
        inc  word [cCol]
        inc  word [cR]
        cmp  word [cR], 3
        jb   dc_sh
        ; ------------------------------------------------ the rows
        mov  word [cR], 0
dcr:    mov  ax, [cTop]
        add  ax, [cR]
        mov  [cY], ax
        mov  ax, [cR]
        cmp  ax, [cCab]
        jb   dcr_cab
        jmp  dcr_body
; ---- cabin (roof and rear window)
dcr_cab:
        mov  ax, [cCbh]
        sub  ax, [cCth]
        mul  word [cR]
        div  word [cCab]
        add  ax, [cCth]
        cmp  word [cR], 3
        jae  dcc1
        mov  bx, 3
        sub  bx, [cR]
        push ax
        mov  ax, [cW]
        mov  cl, 5
        shr  ax, cl
        inc  ax
        mul  bx
        mov  bx, ax
        pop  ax
        sub  ax, bx
dcc1:   cmp  ax, 1
        jge  dcc2
        mov  ax, 1
dcc2:   mov  [cHw], ax
        mov  ax, [cR]
        mov  bx, 3
        mul  bx
        div  word [cCab]
        mov  bx, 10
        sub  bx, ax
        add  bx, [cPb]
        mov  [cCol], bx
        call dc_hspan
        mov  ax, [cR]
        cmp  ax, [cG0]
        jb   dcc9
        cmp  ax, [cG1]
        jae  dcc9
        sub  ax, [cG0]
        mov  bx, 9
        mul  bx
        div  word [cGl]
        mov  bx, 199
        sub  bx, ax
        mov  [cCol], bx
        mov  ax, [cHw]
        sub  ax, [cGm]
        jle  dcc9
        mov  [cHw], ax
        call dc_plain
dcc9:   jmp  dcr_next
; ---- body, lights, plate, bumper
dcr_body:
        sub  ax, [cCab]
        mov  [cRb], ax
        cmp  ax, [cBodyH]
        jb   dcb1
        jmp  dcr_under
dcb1:   mov  ax, [cW2]
        mov  bx, [cRc]
        shr  bx, 1
        inc  bx                  ; small radius of the shoulder
        mov  cx, [cRb]
        cmp  cx, bx
        jae  dcb2
        mov  dx, bx
        sub  dx, cx
        push ax
        mov  ax, dx
        mul  dx
        div  bx
        mov  dx, ax
        pop  ax
        sub  ax, dx
dcb2:   mov  cx, [cBodyH]
        sub  cx, [cRb]           ; rows left down to the bottom
        cmp  cx, [cRc]
        ja   dcb3
        mov  dx, [cRc]
        sub  dx, cx
        push ax
        mov  ax, dx
        mul  dx
        div  word [cRc]
        mov  dx, ax
        pop  ax
        sub  ax, dx
dcb3:   mov  [cHw], ax
        mov  ax, [cRb]
        mov  bx, 5
        mul  bx
        div  word [cBodyH]
        mov  bx, 8
        sub  bx, ax
        cmp  word [cRb], 0
        jne  dcb4
        mov  bx, 11
dcb4:   mov  ax, [cBodyH]
        mov  cx, ax
        shr  cx, 1
        shr  cx, 1
        sub  ax, cx              ; start of the bumper
        cmp  [cRb], ax
        jb   dcb5
        sub  bx, 2
dcb5:   add  bx, [cPb]
        mov  [cCol], bx
        call dc_hspan
        ; chrome line on top of the bumper
        mov  ax, [cBodyH]
        mov  cx, ax
        shr  cx, 1
        shr  cx, 1
        sub  ax, cx
        cmp  [cRb], ax
        jne  dcb6
        mov  ax, [cHw]
        sub  ax, [cRc]
        jle  dcb6
        mov  [cHw], ax
        mov  word [cCol], 254
        call dc_plain
dcb6:   ; tail lights
        mov  ax, [cBodyH]
        xor  dx, dx
        mov  bx, 6
        div  bx
        inc  ax
        mov  [cT0], ax
        mov  ax, [cBodyH]
        shl  ax, 1
        xor  dx, dx
        mov  bx, 5
        div  bx
        cmp  ax, 2
        jae  dcb7
        mov  ax, 2
dcb7:   add  ax, [cT0]
        mov  [cT1], ax
        mov  ax, [cRb]
        cmp  ax, [cT0]
        jb   dcb_pl
        cmp  ax, [cT1]
        jae  dcb_pl
        mov  ax, [cW]
        mov  cl, 2
        shr  ax, cl
        mov  [cLw], ax
        mov  ax, [cW]
        mov  cl, 4
        shr  ax, cl
        inc  ax                  ; margin from the edge of the car
        mov  [cTmp], ax
        ; left light
        mov  cx, [dc_cx]
        sub  cx, [cW2]
        add  cx, [cTmp]
        mov  dx, cx
        add  dx, [cLw]
        mov  word [cCol], 12
        call dc_box
        ; right light
        mov  dx, [dc_cx]
        add  dx, [cW2]
        sub  dx, [cTmp]
        mov  cx, dx
        sub  cx, [cLw]
        call dc_box
        cmp  word [dc_brk], 0
        je   dcb_pl
        ; brake lights glow
        mov  cx, [dc_cx]
        sub  cx, [cW2]
        add  cx, [cTmp]
        inc  cx
        mov  dx, cx
        add  dx, [cLw]
        sub  dx, 2
        mov  word [cCol], 14
        call dc_box
        mov  dx, [dc_cx]
        add  dx, [cW2]
        sub  dx, [cTmp]
        dec  dx
        mov  cx, dx
        sub  cx, [cLw]
        add  cx, 2
        call dc_box
dcb_pl: ; number plate
        cmp  word [cW], 24
        jb   dcr_next
        mov  ax, [cBodyH]
        mov  bx, 11
        mul  bx
        mov  bx, 20
        div  bx
        mov  [cT0], ax
        mov  ax, [cBodyH]
        mov  cl, 2
        shr  ax, cl
        cmp  ax, 2
        jae  dcb8
        mov  ax, 2
dcb8:   add  ax, [cT0]
        mov  [cT1], ax
        mov  ax, [cRb]
        cmp  ax, [cT0]
        jb   dcr_next
        cmp  ax, [cT1]
        jae  dcr_next
        mov  ax, [cW]
        mov  cl, 3
        shr  ax, cl
        mov  [cHw], ax
        mov  word [cCol], 15
        call dc_plain
        jmp  dcr_next
; ---- dark underbody
dcr_under:
        mov  ax, [cW2]
        sub  ax, [cRc]
        mov  [cHw], ax
        mov  word [cCol], 206
        call dc_plain
dcr_next:
        inc  word [cR]
        mov  ax, [cR]
        cmp  ax, [cHt]
        jae  dcr_end
        jmp  dcr
dcr_end:
        ; ------------------------------------------------- tyres
        mov  ax, [cW]
        mov  cl, 3
        shr  ax, cl
        add  ax, 2
        mov  [cLw], ax           ; tyre width
        mov  ax, [cW]
        mov  cl, 4
        shr  ax, cl
        mov  [cTmp], ax
        mov  word [cR], 0
dct:    mov  ax, [cTop]
        add  ax, [cHt]
        sub  ax, [cWh]
        add  ax, [cR]
        mov  [cY], ax
        mov  word [cCol], 0
        cmp  word [cR], 0
        jne  dct1
        mov  word [cCol], 8
dct1:   mov  cx, [dc_cx]
        sub  cx, [cW2]
        add  cx, [cTmp]
        mov  dx, cx
        add  dx, [cLw]
        call dc_box
        mov  dx, [dc_cx]
        add  dx, [cW2]
        sub  dx, [cTmp]
        inc  dx
        mov  cx, dx
        sub  cx, [cLw]
        call dc_box
        inc  word [cR]
        mov  ax, [cR]
        cmp  ax, [cWh]
        jb   dct
        ; ---------------------------------------------------- spoiler
        cmp  word [cSpoil], 0
        je   dc_done
        mov  ax, [cHt]
        mov  cl, 4
        shr  ax, cl
        cmp  ax, 2
        jae  dcs1
        mov  ax, 2
dcs1:   mov  [cLw], ax           ; thickness
        mov  word [cR], 0
dcs2:   mov  ax, [cTop]
        add  ax, [cCab]
        sub  ax, [cLw]
        add  ax, [cR]
        mov  [cY], ax
        mov  word [cCol], 8
        cmp  word [cR], 0
        jne  dcs3
        mov  word [cCol], 7
dcs3:   mov  ax, [cW]
        mov  cl, 4
        shr  ax, cl
        mov  bx, [cW2]
        add  bx, ax
        mov  cx, [dc_cx]
        sub  cx, bx
        mov  dx, [dc_cx]
        add  dx, bx
        inc  dx
        call dc_box
        inc  word [cR]
        mov  ax, [cR]
        cmp  ax, [cLw]
        jb   dcs2
dc_done: ret

; small cars far away: three simple shapes
drawcar_small:
        mov  ax, [dc_pnt]
        mov  bx, ax
        shl  ax, 1
        add  ax, bx
        shl  ax, 1
        shl  ax, 1
        add  ax, 118
        mov  [cPb], ax
        mov  ax, [cW]
        mov  bx, ax
        shl  ax, 1
        shl  ax, 1
        add  ax, bx
        mov  cl, 3
        shr  ax, cl
        cmp  ax, 2
        jae  dsm1
        mov  ax, 2
dsm1:   mov  [cHt], ax            ; height 5/8 of the width
        shl  ax, 1
        add  ax, [cHt]
        mov  cl, 2
        shr  ax, cl
        cmp  ax, 1
        jae  dsm2
        mov  ax, 1
dsm2:   mov  [cBodyH], ax
        mov  ax, [cHt]
        sub  ax, [cBodyH]
        cmp  ax, 1
        jge  dsm3
        mov  ax, 1
dsm3:   mov  [cCab], ax
        mov  ax, [cW]
        shr  ax, 1
        mov  [cW2], ax
        ; body
        mov  ax, [dc_yb]
        sub  ax, [cBodyH]
        inc  ax
        mov  [cTop], ax
        mov  ax, [dc_cx]
        sub  ax, [cW2]
        mov  [cT0], ax
        mov  ax, [cPb]
        add  ax, 7
        mov  [cCol], ax
        RECT [cT0],[cTop],[cW],[cBodyH],[cCol]
        ; cabin
        mov  ax, [cTop]
        sub  ax, [cCab]
        mov  [cTop], ax
        mov  ax, [cW]
        mov  cl, 3
        shr  ax, cl
        mov  bx, [cT0]
        add  bx, ax
        mov  [cT0], bx
        shl  ax, 1
        mov  bx, [cW]
        sub  bx, ax
        mov  [cT1], bx
        mov  ax, [cPb]
        add  ax, 9
        mov  [cCol], ax
        RECT [cT0],[cTop],[cT1],[cCab],[cCol]
        ; tail lights
        mov  ax, [dc_yb]
        sub  ax, [cBodyH]
        inc  ax
        mov  [cTop], ax
        mov  ax, [dc_cx]
        sub  ax, [cW2]
        mov  [cT0], ax
        RECT [cT0],[cTop],1,1,12
        mov  ax, [dc_cx]
        add  ax, [cW2]
        dec  ax
        mov  [cT0], ax
        RECT [cT0],[cTop],1,1,12
        ret

; =====================================================================
;                    COCKPIT  (bonnet, dials, wheel)  and  HUD
; =====================================================================
draw_bonnet:
        xor  bh, bh
        mov  bl, [selcar]
        xor  ah, ah
        mov  al, [car_pntof+bx]
        mov  bx, ax
        shl  ax, 1
        add  ax, bx
        shl  ax, 1
        shl  ax, 1
        add  ax, 118
        mov  [c_t], ax           ; paint colours of the chosen car
        mov  word [g_y], 143
bn1:    mov  ax, [g_y]
        sub  ax, 143             ; r = row inside the bonnet
        mov  di, ax
        mov  bx, 7
        mul  bx
        mov  bx, 23
        div  bx                  ; 0..7 from the top of the bonnet to its bottom
        mov  bx, 10
        sub  bx, ax
        add  bx, [c_t]
        mov  [c_wc], bx          ; colour of this row
        mov  si, bonnet_hw
        add  si, di
        xor  ah, ah
        mov  al, [si]
        mov  cx, 160
        sub  cx, ax
        mov  dx, 160
        add  dx, ax
        mov  ax, [c_wc]
        mov  bx, [g_y]
        call span
        inc  word [g_y]
        cmp  word [g_y], 167
        jb   bn1
        ret

draw_dashbase:
        mov  word [g_y], 167
db_g:   mov  ax, [g_y]
        sub  ax, 167
        shr  ax, 1
        shr  ax, 1
        mov  bx, 219
        sub  bx, ax
        mov  ax, bx
        mov  bx, [g_y]
        xor  cx, cx
        mov  dx, 320
        call span
        inc  word [g_y]
        cmp  word [g_y], 200
        jb   db_g
        RECT 0,167,320,1,221
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
        mov  ax, 121
        mov  bx, 128
        mov  cx, 130
        cmp  byte [cam], 0
        je   sy1
        mov  ax, 42
        mov  bx, 49
        mov  cx, 51
sy1:    mov  [sens_y], ax
        mov  [sens_y2], bx
        mov  [sens_y3], cx
        mov  si, s_sens
        mov  bx, 125
        mov  dx, [sens_y]
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
        mov  dx, [sens_y]
        mov  al, 15
        mov  ah, 1
        call puts_sh
        mov  si, s_dot
        mov  bx, [t_x]
        mov  dx, [sens_y]
        mov  al, 15
        mov  ah, 1
        call puts_sh
        pop  ax
        mov  cl, 1
        call num2str
        mov  bx, [t_x]
        mov  dx, [sens_y]
        mov  al, 15
        mov  ah, 1
        call puts_sh
        mov  si, s_m
        mov  bx, [t_x]
        mov  dx, [sens_y]
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
        RECT 123,[sens_y2],83,9,0
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
        RECT [c_xc],[sens_y3],8,5,[c_wc]
        inc  si
        cmp  si, 8
        jb   sl3
hd_end: ret

sens_y:  dw 121
sens_y2: dw 128
sens_y3: dw 130

; draw_chase_hud: instruments of the chase cameras (a bar at the bottom)
draw_chase_hud:
        mov  word [g_y], 176
ch1:    mov  ax, [g_y]
        sub  ax, 176
        shr  ax, 1
        shr  ax, 1
        mov  bx, 214
        sub  bx, ax
        mov  ax, bx
        mov  bx, [g_y]
        xor  cx, cx
        mov  dx, 320
        call span
        inc  word [g_y]
        cmp  word [g_y], 200
        jb   ch1
        RECT 0,176,320,1,221
        ; gear
        RECT 8,180,22,18,8
        RECT 9,181,20,16,206
        mov  si, s_d
        mov  al, 10
        cmp  word [spd], 0
        jge  ch2
        mov  si, s_r
        mov  al, 12
ch2:    mov  bx, 14
        mov  dx, 182
        mov  ah, 2
        call puts
        ; speed
        mov  ax, [spd]
        cmp  ax, 0
        jge  ch3
        neg  ax
ch3:    mov  cl, 4
        shr  ax, cl
        mov  cl, 3
        call num2str
        mov  bx, 46
        mov  dx, 181
        mov  al, 14
        mov  ah, 2
        call puts_sh
        mov  si, s_kmh
        mov  bx, 86
        mov  dx, 190
        mov  al, 7
        mov  ah, 1
        call puts
        ; fuel bar
        mov  si, s_fuel_l
        mov  bx, 140
        mov  dx, 179
        mov  al, 7
        mov  ah, 1
        call puts
        RECT 140,188,94,9,8
        RECT 141,189,92,7,206
        mov  ax, [fuel]
        mov  bx, 90
        mul  bx
        div  word [fuelmax]
        mov  [c_t], ax
        mov  bx, 10
        mov  ax, [fuelmax]
        shr  ax, 1
        shr  ax, 1
        cmp  [fuel], ax
        jae  ch4
        mov  bx, 12
ch4:    mov  [c_wc], bx
        RECT 142,190,[c_t],5,[c_wc]
        ; indicators
        mov  al, 2
        cmp  word [wheel], 0
        jge  ch5
        mov  al, 10
ch5:    mov  si, bmp_larr
        mov  bx, 246
        mov  dx, 182
        call drawbmp
        mov  al, 2
        cmp  word [wheel], 0
        jle  ch6
        mov  al, 10
ch6:    mov  si, bmp_rarr
        mov  bx, 286
        mov  dx, 182
        call drawbmp
        mov  al, 4
        cmp  word [crash], 0
        je   ch7
        test byte [crash], 8
        jz   ch7
        mov  al, 12
ch7:    mov  si, bmp_haz
        mov  bx, 266
        mov  dx, 180
        call drawbmp
        ret
s_fuel_l: db "FUEL",0

; =====================================================================
;              PARKING LOT, MENUS, GARAGE  (smooth gradient panels)
; =====================================================================
tree_y: db 52,48,55,50,53,47,54,51,49,55
cor_tab: db 5,3,2,1,1
car_stats: db 36,30,30,34,  44,32,34,36,  54,48,44,42,  44,34,34,24,  60,58,56,50
s_title: db "DR. DRIVING",0
s_lite:  db "LITE",0
s_sub:   db "COAL FINAL PROJECT",0
s_o1:    db "HIGHWAY",0
s_o2:    db "PARKING",0
s_o3:    db "GARAGE",0
s_o4:    db "QUIT",0
s_menu_h: db "UP DOWN ENTER  OR 1 2 3",0
s_points: db "POINTS ",0
s_carl:   db "CAR  ",0
s_enter: db "PRESS ENTER",0
s_scorel: db "SCORE ",0
s_total:  db "TOTAL POINTS ",0
s_newcar: db "NEW CAR AVAILABLE IN THE GARAGE",0
s_paused: db "PAUSED",0
s_p0: db "RESUME",0
s_p1: db "RESTART",0
s_p2: db "CAMERA",0
s_p3: db "SMOOTH EDGES",0
s_p4: db "MAIN MENU",0
s_on: db "ON",0
s_off: db "OFF",0
s_pause_h: db "ESC RESUME   C CAMERA",0
s_garage: db "GARAGE",0
s_gh:     db "LEFT RIGHT CHOOSE  ENTER SELECT  ESC BACK",0
s_owned:  db "OWNED",0
s_sel:    db "SELECTED",0
s_lock:   db "LOCKED  PRICE ",0
s_nopts:  db "NOT ENOUGH POINTS",0
s_st0: db "SPEED",0
s_st1: db "ACCEL",0
s_st2: db "BRAKES",0
s_st3: db "GRIP",0
st_names: dw s_st0,s_st1,s_st2,s_st3
cn0: db "CITY HATCH",0
cn1: db "SEDAN S",0
cn2: db "COUPE R",0
cn3: db "TREK SUV",0
cn4: db "SUPER GT",0
car_names: dw cn0,cn1,cn2,cn3,cn4

; ------------------------------------------------- gradient panels
; rbox: push x, y, w, h, top colour, bottom colour  - rounded, gradient
rbox:   push bp
        mov  bp, sp
        push ax
        push bx
        push cx
        push dx
        push si
        push di
        xor  di, di              ; row
rb1:    xor  si, si              ; inset
        cmp  di, 5
        jae  rb2
        mov  bx, di
        mov  al, [cor_tab+bx]
        xor  ah, ah
        mov  si, ax
rb2:    mov  ax, [bp+8]
        sub  ax, di
        dec  ax
        cmp  ax, 5
        jae  rb3
        mov  bx, ax
        mov  al, [cor_tab+bx]
        xor  ah, ah
        mov  si, ax
rb3:    mov  ax, [bp+4]
        sub  ax, [bp+6]
        imul di
        idiv word [bp+8]
        add  ax, [bp+6]
        mov  bx, [bp+12]
        add  bx, di
        mov  cx, [bp+14]
        add  cx, si
        mov  dx, [bp+14]
        add  dx, [bp+10]
        sub  dx, si
        call span
        inc  di
        cmp  di, [bp+8]
        jb   rb1
        pop  di
        pop  si
        pop  dx
        pop  cx
        pop  bx
        pop  ax
        pop  bp
        ret  12

%macro RBOX 6
        PUSHV %1
        PUSHV %2
        PUSHV %3
        PUSHV %4
        PUSHV %5
        PUSHV %6
        call rbox
%endmacro
; a panel: gold frame, dark blue gradient inside
%macro PANEL 4
        RBOX %1-2,%2-2,%3+4,%4+4,233,227
        RBOX %1,%2,%3,%4,236,246
%endmacro

; strlen: si = string -> cx = length
strlen: push si
        xor  cx, cx
sl_1:   cmp  byte [si], 0
        je   sl_2
        inc  si
        inc  cx
        jmp  sl_1
sl_2:   pop  si
        ret

; putsc: centred text. si = string, dx = y, al = colour, ah = scale
putsc:  push bx
        push cx
        push dx
        push ax
        call strlen              ; cx = number of letters
        mov  al, ah
        xor  ah, ah
        mov  bx, 6
        mul  bx
        mul  cx                  ; width = letters * 6 * scale
        shr  ax, 1
        mov  bx, 160
        sub  bx, ax
        pop  ax
        pop  dx
        call puts_sh
        pop  cx
        pop  bx
        ret


; mkline: si = label text, ax = number  ->  si = "label number" (one string)
mkline: push ax
        push bx
        push di
        mov  di, linebuf
mk1:    mov  bl, [si]
        or   bl, bl
        jz   mk2
        mov  [di], bl
        inc  si
        inc  di
        jmp  mk1
mk2:    mov  cl, 1
        call num2str
mk3:    mov  bl, [si]
        mov  [di], bl
        inc  si
        inc  di
        or   bl, bl
        jnz  mk3
        mov  si, linebuf
        pop  di
        pop  bx
        pop  ax
        ret
linebuf: times 40 db 0

; goldtext: three layers (shadow, dark gold, bright gold) - elegant title
goldtext:
        push ax
        push bx
        push dx
        add  bx, 2
        add  dx, 2
        mov  al, 0
        call puts
        pop  dx
        pop  bx
        push bx
        push dx
        inc  bx
        inc  dx
        mov  al, 229
        call puts
        pop  dx
        pop  bx
        pop  ax
        mov  al, 233
        call puts
        ret

; ------------------------------------------------------------ parking
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
        mov  bx, 36
        mov  dx, 24
        call cloud
        mov  bx, 215
        mov  dx, 34
        call cloud
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
        RECT 0,80,320,8,219
        RECT 0,80,320,1,15
        RECT 0,87,320,1,212
        xor  si, si
tp2:    mov  ax, si
        mov  cl, 4
        shl  ax, cl
        mov  [c_xc], ax
        RECT [c_xc],81,2,6,210
        inc  si
        cmp  si, 20
        jb   tp2
        ret

draw_ground_park:
        mov  word [g_y], 88
gp_row: mov  ax, [g_y]
        sub  ax, 87
        mov  [g_k], ax
        mul  word [cam_lwm]
        mov  cl, 3
        shr  ax, cl
        add  ax, [cam_lwa]
        mov  [g_lw], ax
        mov  bx, [g_k]
        cmp  bx, [cam_kmin]
        jae  gp0
        mov  bx, [cam_kmin]
gp0:    mov  dx, [cam_hi]
        mov  ax, [cam_lo]
        div  bx
        add  ax, [pz]
        sub  ax, 115
        sub  ax, [cam_cb]
        mov  [g_zw], ax
        mov  bx, [g_y]
        mov  ax, [g_k]
        shr  ax, 1
        shr  ax, 1
        cmp  ax, 23
        jbe  gp1a
        mov  ax, 23
gp1a:   add  ax, 38
        xor  cx, cx
        mov  dx, 320
        call span
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
        mov  al, 2
        mov  cx, [g_xl]
        mov  dx, [g_xr]
        call span
        mov  al, 15
        mov  cx, [g_xl]
        mov  dx, cx
        add  dx, [g_ew]
        call span
        mov  dx, [g_xr]
        mov  cx, dx
        sub  cx, [g_ew]
        call span
        cmp  word [g_zw], 616
        jge  gp2
        mov  cx, [g_xl]
        mov  dx, [g_xr]
        call span
gp2:    mov  ax, -56
        call bayx
        mov  cx, ax
        mov  dx, ax
        add  dx, [g_ew]
        mov  al, 15
        call span
        mov  ax, 184
        call bayx
        mov  cx, ax
        mov  dx, ax
        add  dx, [g_ew]
        mov  al, 15
        call span
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
        mov  al, 14
        call span
gp_nx:  inc  word [g_y]
        mov  ax, [cam_gnd]
        cmp  [g_y], ax
        jae  gp_dn
        jmp  gp_row
gp_dn:  ret

; park_zproj: bx = distance seen from the camera
;             -> g_k, g_lw, dc_yb ; carry set when not visible
park_zproj:
        cmp  bx, 200
        jl   pj_no
        mov  dx, [cam_hi]
        mov  ax, [cam_lo]
        cmp  dx, bx
        jae  pj_no
        div  bx
        cmp  ax, 1
        jl   pj_no
        mov  [g_k], ax
        add  ax, 87
        mov  [dc_yb], ax
        mov  ax, [g_k]
        mul  word [cam_lwm]
        mov  cl, 3
        shr  ax, cl
        add  ax, [cam_lwa]
        mov  [g_lw], ax
        clc
        ret
pj_no:  stc
        ret

; park_proj: [pp_x] = world x, [pp_z] = world z -> dc_cx, dc_yb, g_lw
park_proj:
        mov  bx, [pp_z]
        sub  bx, [pz]
        add  bx, 115
        add  bx, [cam_cb]
        call park_zproj
        jc   pj_x
        mov  ax, [pp_x]
        call bayx
        mov  [dc_cx], ax
        clc
pj_x:   ret

pp_pnt: dw 0
pp_des: dw 0

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
        mov  ax, [pp_pnt]
        mov  [dc_pnt], ax
        mov  ax, [pp_des]
        mov  [dc_des], ax
        mov  word [dc_brk], 0
        call drawcar
pc_x:   ret

; the car you drive, in the chase cameras
draw_player_park:
        mov  bx, [cam_cb]
        sub  bx, 167
        call park_zproj
        jc   dpp_x
        mov  ax, [g_lw]
        mov  bx, ax
        shl  ax, 1
        shl  ax, 1
        add  ax, bx
        mov  cl, 3
        shr  ax, cl
        mov  [dc_lw], ax
        mov  ax, [wheel]
        mov  bx, 3
        imul bx
        add  ax, 160
        mov  [dc_cx], ax
        call player_look
dpp_x:  mov  word [pdrawn], 1
        ret

; draws your car first if the next object is nearer than it: ax = object z
maybe_player:
        cmp  byte [cam], 0
        je   mp_x
        cmp  word [pdrawn], 0
        jne  mp_x
        mov  bx, [pz]
        sub  bx, 282
        cmp  bx, ax
        jle  mp_x
        call draw_player_park
mp_x:   ret

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
        RECT [c_x0],[c_ytb],[c_W],[c_bh],206
pk_x:   ret

draw_park_objects:
        mov  word [pdrawn], 0
        ; big letter P in the bay
        mov  bx, 899
        sub  bx, [pz]
        add  bx, [cam_cb]        ; distance to the middle of the bay
        cmp  bx, 300
        jl   dpo1
        mov  dx, [cam_hi]
        cmp  dx, bx
        jae  dpo1
        mov  ax, [cam_lo]
        div  bx
        cmp  ax, 70
        jg   dpo1
        mov  [g_k], ax
        add  ax, 87
        mov  [dc_yb], ax
        mov  ax, [g_k]
        mul  word [cam_lwm]
        mov  cl, 3
        shr  ax, cl
        add  ax, [cam_lwa]
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
dpo2:   cmp  byte [cam], 0
        je   dpo3
        mov  ah, 1               ; chase cameras see the bay flat: small letter
dpo3:   mov  [t_sc], ah
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
        mov  word [pp_pnt], 2
        mov  word [pp_des], 1
        call park_car
        mov  word [pp_x], 116
        mov  word [pp_z], 2700
        mov  word [pp_pnt], 5
        mov  word [pp_des], 0
        call park_car
        mov  word [pp_x], -70
        mov  word [pp_z], 2500
        mov  word [pp_pnt], 4
        mov  word [pp_des], 2
        call park_car
        mov  word [pp_x], 60
        mov  word [pp_z], 3000
        mov  word [pp_pnt], 1
        mov  word [pp_des], 3
        call park_car
        mov  word [pp_x], 170
        mov  word [pp_z], 2400
        mov  word [pp_pnt], 3
        mov  word [pp_des], 4
        call park_car
        ; neighbours of the bay
        mov  ax, 595
        call maybe_player
        mov  word [pp_x], -16
        mov  word [pp_z], 595
        mov  word [pp_pnt], 5
        mov  word [pp_des], 1
        call park_car
        mov  word [pp_x], 144
        mov  word [pp_z], 595
        mov  word [pp_pnt], 2
        mov  word [pp_des], 3
        call park_car
        ; cones at the bay entrance
        mov  ax, 576
        call maybe_player
        mov  word [pp_x], 20
        mov  word [pp_z], 576
        call park_cone
        mov  word [pp_x], 108
        mov  word [pp_z], 576
        call park_cone
        cmp  byte [cam], 0
        je   dpo9
        cmp  word [pdrawn], 0
        jne  dpo9
        call draw_player_park
dpo9:   ret

render_parking:
        call draw_sky_park
        call draw_ground_park
        call draw_park_objects
        ret

; ------------------------------------------------------------ main menu
; menu_item: si = text, dx = y, al = item number
menu_item:
        push ax
        push bx
        push dx
        cmp  al, [msel]
        jne  mi1
        mov  [c_t], dx
        RBOX 84,[c_t],152,17,243,238
        pop  dx
        pop  bx
        pop  ax
        push ax
        push bx
        push dx
        mov  al, 233
        jmp  mi2
mi1:    mov  al, 7
mi2:    mov  bx, 112
        add  dx, 2
        mov  ah, 2
        call puts_sh
        pop  dx
        pop  bx
        pop  ax
        ret

draw_menu:
        PANEL 60,24,200,166
        mov  si, s_title
        mov  bx, 62
        mov  dx, 32
        mov  al, 233
        mov  ah, 3
        call goldtext
        mov  si, s_lite
        mov  bx, 137
        mov  dx, 56
        mov  ah, 2
        call goldtext
        mov  si, s_sub
        mov  dx, 76
        mov  al, 7
        mov  ah, 1
        call putsc
        RECT 84,88,152,1,230
        mov  si, s_o1
        mov  dx, 94
        xor  al, al
        call menu_item
        mov  si, s_o2
        mov  dx, 112
        mov  al, 1
        call menu_item
        mov  si, s_o3
        mov  dx, 130
        mov  al, 2
        call menu_item
        mov  si, s_o4
        mov  dx, 148
        mov  al, 3
        call menu_item
        ; points and chosen car
        mov  si, s_points
        mov  bx, 70
        mov  dx, 170
        mov  al, 233
        mov  ah, 1
        call puts_sh
        mov  ax, [bank]
        mov  cl, 1
        call num2str
        mov  bx, [t_x]
        mov  dx, 170
        mov  al, 15
        mov  ah, 1
        call puts_sh
        xor  bh, bh
        mov  bl, [selcar]
        shl  bx, 1
        mov  si, [car_names+bx]
        mov  bx, 180
        mov  dx, 170
        mov  al, 14
        mov  ah, 1
        call puts_sh
        mov  si, s_menu_h
        mov  dx, 180
        mov  al, 8
        mov  ah, 1
        call putsc
        ret

; ----------------------------------------------------------- pause menu
pause_item:
        push ax
        push bx
        push dx
        cmp  al, [psel]
        jne  pi1
        mov  [c_t], dx
        RBOX 94,[c_t],132,14,243,238
pi1:    pop  dx
        pop  bx
        pop  ax
        push ax
        push bx
        push dx
        mov  bx, 102
        add  dx, 3
        mov  al, 15
        mov  ah, 1
        call puts_sh
        pop  dx
        pop  bx
        pop  ax
        ret

draw_pause:
        PANEL 80,36,160,132
        mov  si, s_paused
        mov  dx, 44
        mov  al, 233
        mov  ah, 2
        call putsc
        mov  si, s_p0
        mov  dx, 70
        xor  al, al
        call pause_item
        mov  si, s_p1
        mov  dx, 86
        mov  al, 1
        call pause_item
        mov  si, s_p2
        mov  dx, 102
        mov  al, 2
        call pause_item
        xor  bh, bh
        mov  bl, [cam]
        shl  bx, 1
        mov  si, [cam_names+bx]
        mov  bx, 168
        mov  dx, 105
        mov  al, 14
        mov  ah, 1
        call puts
        mov  si, s_p3
        mov  dx, 118
        mov  al, 3
        call pause_item
        mov  si, s_on
        cmp  byte [smooth], 0
        jne  dp1
        mov  si, s_off
dp1:    mov  bx, 200
        mov  dx, 121
        mov  al, 14
        mov  ah, 1
        call puts
        mov  si, s_p4
        mov  dx, 134
        mov  al, 4
        call pause_item
        mov  si, s_pause_h
        mov  dx, 156
        mov  al, 8
        mov  ah, 1
        call putsc
        ret

; ------------------------------------------------------------ end panel
draw_endpanel:
        PANEL 50,50,220,104
        mov  si, [msg_t]
        mov  dx, 60
        mov  al, [msg_c]
        mov  ah, 2
        call putsc
        mov  si, s_scorel
        mov  ax, [earned]
        call mkline
        mov  dx, 86
        mov  al, 14
        mov  ah, 2
        call putsc
        mov  si, s_total
        mov  ax, [bank]
        call mkline
        mov  dx, 108
        mov  al, 233
        mov  ah, 1
        call putsc
        ; is there a car you can afford now?
        xor  si, si
ep1:    mov  al, 1
        mov  cx, si
        shl  al, cl
        test [unl], al
        jnz  ep2
        mov  bx, si
        shl  bx, 1
        mov  ax, [bank]
        cmp  ax, [car_price+bx]
        jb   ep2
        mov  si, s_newcar
        mov  dx, 122
        mov  al, 10
        mov  ah, 1
        call putsc
        jmp  ep3
ep2:    inc  si
        cmp  si, 5
        jb   ep1
ep3:    test byte [ticks], 32
        jz   ep9
        mov  si, s_enter
        mov  dx, 138
        mov  al, 7
        mov  ah, 1
        call putsc
ep9:    ret

; ------------------------------------------------------------- garage
render_garage:
        ; background: deep blue gradient
        xor  bx, bx
rg1:    mov  ax, bx
        mov  cl, 4
        shr  ax, cl
        add  ax, 234
        xor  cx, cx
        mov  dx, 320
        call span
        inc  bx
        cmp  bx, 200
        jb   rg1
        mov  si, s_garage
        mov  dx, 8
        mov  al, 233
        mov  ah, 2
        call putsc
        ; points
        mov  si, s_points
        mov  bx, 214
        mov  dx, 10
        mov  al, 233
        mov  ah, 1
        call puts_sh
        mov  ax, [bank]
        mov  cl, 1
        call num2str
        mov  bx, [t_x]
        mov  dx, 10
        mov  al, 15
        mov  ah, 1
        call puts_sh
        ; spot light and podium
        RBOX 70,150,180,16,222,214
        RBOX 70,148,180,3,230,233
        xor  bh, bh
        mov  bl, [gsel]
        mov  al, [car_dsgof+bx]
        xor  ah, ah
        mov  [dc_des], ax
        mov  al, [car_pntof+bx]
        xor  ah, ah
        mov  [dc_pnt], ax
        mov  word [dc_brk], 0
        mov  word [dc_cx], 160
        mov  word [dc_yb], 146
        mov  word [dc_lw], 150
        call drawcar
        ; arrows
        mov  si, s_larr
        mov  bx, 16
        mov  dx, 100
        mov  al, 233
        mov  ah, 3
        call puts_sh
        mov  si, s_rarr
        mov  bx, 288
        mov  dx, 100
        mov  al, 233
        mov  ah, 3
        call puts_sh
        ; name
        xor  bh, bh
        mov  bl, [gsel]
        shl  bx, 1
        mov  si, [car_names+bx]
        mov  dx, 172
        mov  al, 15
        mov  ah, 2
        call putsc
        ; stats
        xor  di, di
rg2:    mov  ax, di
        mov  bx, 11
        mul  bx
        add  ax, 36
        mov  [c_yc], ax
        mov  bx, di
        shl  bx, 1
        mov  si, [st_names+bx]
        mov  bx, 8
        mov  dx, [c_yc]
        mov  al, 7
        mov  ah, 1
        call puts_sh
        RECT 46,[c_yc],54,6,236
        xor  bh, bh
        mov  bl, [gsel]
        shl  bx, 1
        shl  bx, 1
        add  bx, di
        xor  ah, ah
        mov  al, [car_stats+bx]
        mov  [c_t], ax
        mov  ax, [c_yc]
        inc  ax
        mov  [c_wc], ax
        RECT 47,[c_wc],[c_t],4,232
        inc  di
        cmp  di, 4
        jb   rg2
        ; status line
        mov  al, 1
        mov  cl, [gsel]
        shl  al, cl
        test [unl], al
        jnz  rg3
        mov  si, s_lock
        xor  bh, bh
        mov  bl, [gsel]
        shl  bx, 1
        mov  ax, [car_price+bx]
        call mkline
        mov  dx, 188
        mov  al, 12
        mov  ah, 1
        call putsc
        jmp  rg5
rg3:    mov  si, s_owned
        mov  al, [gsel]
        cmp  al, [selcar]
        jne  rg4
        mov  si, s_sel
rg4:    mov  dx, 188
        mov  al, 10
        mov  ah, 1
        call putsc
rg5:    cmp  word [gmsg], 0
        je   rg6
        test byte [ticks], 8
        jz   rg6
        mov  si, s_nopts
        mov  dx, 124
        mov  al, 12
        mov  ah, 2
        call putsc
rg6:    mov  si, s_gh
        mov  dx, 24
        mov  al, 8
        mov  ah, 1
        call putsc
        ret
s_larr: db "<",0
s_rarr: db ">",0


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
    db 0x01, 0x02, 0x04, 0x08, 0x04, 0x02, 0x01      ; '<'
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