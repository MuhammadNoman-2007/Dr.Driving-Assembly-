; =====================================================================
;  DR. DRIVING LITE  -  COAL Final Project  (8088 assembly, NASM, .COM)
;  PHASE 1 : SCREEN SETUP
;  Build :  nasm phase1.asm -o phase1.com
;
;  Draws the highway screen once: time bar, distance and score, road with
;  3 lanes, traffic, bonnet, speed box (078 km/h), fuel bar (half full),
;  steering wheel.  Nothing moves.   ESC = leave.
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

; ------------------------------------------------------------ settings
selcar:   db 0
smooth:   db 1
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
ZLOW    equ 384

quitflag: db 0
cam_hi:   dw 1
cam_lo:   dw 0x5E00
cam_lwm:  dw 8
cam_lwa:  dw 7
cam_cb:   dw 0
cam_gnd:  dw 167
cam_jmin: dw 0
cam_kmin: dw 2
car_pntof: db 0,1,2,3,4
; camera numbers of the cockpit view: hi, lo (distance constant), lane scale,
; lane base, camera back, last ground row, first building
camh_tab: dw 1,0x5E00,8,7,0,167,0

spd:      dw 0                  ; speed, 1/16 km/h, negative = reversing
odo:      dw 0                  ; distance driven, 1/64 m
advp:     dw 0                  ; world movement of this frame (1/64 m)
camu:     dw 64                 ; camera sideways position, 64 per lane
wheel:    dw 0                  ; steering wheel angle -4..4
score:    dw 0
timeleft: dw 0
timetotal:dw 1
fuel:     dw 0
fuelmax:  dw 1
crash:    dw 0
car_z:    times NC dw 0
car_lane: dw 1,0,2,2,1,0,0,1,2,1
car_pnt:  dw 1,5,3,2,4,0,1,3,2,5       ; paint of every traffic car
car_des:  dw 1,0,3,2,4,1,0,2,3,1       ; body shape of every traffic car
car_off:  dw 0,2240,2240,4480,6720,6720,8960,11200,11200,13440

; =====================================================================
;                              GAME LOGIC
; =====================================================================
; the screen of Phase 1 is a still picture: fixed values, nothing moves
game_init:
        call set_cam
        mov  word [spd], 1248    ; 078 km/h
        mov  word [odo], 7680    ; 120 m  (1 m = 64 units)
        mov  word [advp], 0
        mov  word [camu], 64     ; middle lane
        mov  word [wheel], 0
        mov  word [score], 1200
        mov  word [timeleft], 3200
        mov  word [timetotal], 4800
        mov  word [fuel], 18000  ; half full
        mov  word [fuelmax], 36000
        mov  word [crash], 0
        call cars_init
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

; only ESC does something: leave the program
game_update:
        mov  al, [lastkey]
        mov  byte [lastkey], 0
        cmp  al, 1
        jne  gu1
        mov  byte [quitflag], 1
gu1:    ret

; set_cam: loads the camera numbers of the cockpit view
set_cam:
        push ax
        push cx
        push si
        push di
        mov  si, camh_tab
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
        pop  ax
        ret

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
c_H:  dw 0
c_xc: dw 0
c_wc: dw 0
c_yc: dw 0
c_t:  dw 0
tdone: times NC dw 0
t_cnt: dw 0
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
s_s:     db "S",0
s_d:     db "D",0
s_r:     db "R",0
game_render:
        call render_highway
        call draw_cockpit
        call draw_hud
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

; ------------------------------------------------------------ traffic
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
        add  dx, [cam_cb]        ; distance seen from the camera
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
dt_end:
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
        mov  si, s_score
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
hd_end: ret

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