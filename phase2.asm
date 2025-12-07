[org 0x0100]

jmp start

; ============================================
; DATA SECTION
; ============================================
player_x:          dw 160
player_y:          dw 155
obstacle_x:        dw 172
obstacle_y:        dw 60
obstacle_active:   db 0

; Multiple coins (6 max)
MAX_COINS          equ 6
coins_x:           times MAX_COINS dw 0
coins_y:           times MAX_COINS dw 0
coins_active:      times MAX_COINS db 0

seed:              dw 0
scroll_offset:     dw 0
scroll_frac: dw 0
spawn_timer:       dw 0
coin_timer:        dw 0

coin_batch_timer:  dw 30     ; Counts up to 5 seconds
coins_remaining:   dw 0     ; How many coins left to spawn in the current line
current_coin_lane: dw 160    ; Which lane the current line is in
coin_gap_timer:    dw 0     ; Spacing between coins in the line

fuel:              dw 10
fuel_timer:        dw 0        ; now used as a frame counter
score:             dw 0
game_over_flag:    db 0
; Add after existing variables
player_speed:   dw 0        ; Current forward speed (0–5)
max_speed:      equ 5
accel:          equ 1
decel:          equ 1
min_y:          equ 80      ; Top boundary for player
max_y:          equ 155     ; Bottom (starting) position
base_scroll:    dw 1        ; Base scroll per frame
BUFFER_SEG equ 0xB000
buffer_seg: dw BUFFER_SEG


; ============================================
; MAIN PROGRAM
; ============================================
start:
    mov ax, 0x0013
    int 0x10

    mov ax, 0xA000
    mov es, ax

    mov ax, BUFFER_SEG
    mov [buffer_seg], ax
    mov es, ax                     ; ES now points to the buffer

    call init_random

game_loop:
    cmp byte [game_over_flag], 1
    je  near game_over_screen

    call update_fuel
    call update_player_position
    call update_background_scroll
    call spawn_and_update_obstacles
    call spawn_coins
    call update_all_coins
    call check_obstacle_collision
    call check_all_coin_collisions
    call clear_buffer
    call draw_scene
    call draw_ui
    call draw_curbs
    call draw_road_markings
    call draw_all_trees
    call draw_guardrails
    call flip_buffer

    call get_input

    ; Small delay using BIOS wait (just slows the loop a bit)
    mov cx, 0x0001
    mov dx, 0x0000
    mov ah, 0x86
    int 0x15

    jmp near game_loop

game_over_screen:
    call draw_game_over
    call flip_buffer
    call wait_for_key

    mov ax, 0x0003
    int 0x10
    mov ax, 0x4C00
    int 0x21

; ==============================================================
;  DOUBLE-BUFFER HELPERS
; ==============================================================
clear_buffer:
    push es
    push di
    push cx
    mov es, [buffer_seg]
    xor di, di
    mov cx, 320*200/2
    xor ax, ax
    rep stosw
    pop cx
    pop di
    pop es
    ret

flip_buffer:
    push ds
    push es
    push si
    push di
    push cx

    mov ax, [buffer_seg]
    mov ds, ax                     ; DS:SI = buffer
    xor si, si
mov ax, 0xA000
    mov es, ax                 ; ES:DI = video memory
    xor di, di
    mov cx, 320*200/2
    rep movsw                      ; 16-bit copy → 2× faster than byte copy

    pop cx
    pop di
    pop si
    pop es
    pop ds
    ret

; ============================================
; UPDATE FUEL (simple frame-based decrement)
; ============================================
; Every ~60 frames: fuel--
; When fuel reaches 0: game_over_flag = 1
; ============================================
update_fuel:
    push ax

    mov ax, [fuel_timer]
    inc ax
    mov [fuel_timer], ax

    cmp ax, 60          ; adjust this for faster/slower fuel usage
    jb  near .done

    ; time to decrement fuel
    mov word [fuel_timer], 0
    cmp word [fuel], 0
    je  near .set_game_over
    dec word [fuel]
    cmp word [fuel], 0
    jne near .done

.set_game_over:
    mov byte [game_over_flag], 1

.done:
    pop ax
    ret

; ============================================
; update_background_scroll
; ============================================
update_background_scroll:
    ; scroll_amount = base_scroll + player_speed
    mov ax, [base_scroll]
    add ax, [player_speed]
    add [scroll_offset], ax
    mov ax, [scroll_frac]
    shr ax, 8                ; integer part
    add [scroll_offset], ax
    and word [scroll_frac], 0xFF

    mov ax, [scroll_offset]
    cmp word [scroll_offset], 200
    jb .done
    sub word [scroll_offset], 200
.done:
    ret
; ============================================
; RANDOM SEED INIT & CLEANUP
; ============================================
init_random:
    push dx
    push ax
    push si
    push cx

    ; 1. Get Timer Seed
    mov ah, 0x00
    int 0x1A
    mov [seed], dx

    ; 2. Reset Timers
    mov word [fuel_timer], 0
    mov word [spawn_timer], 0
    mov word [coin_timer], 0
    mov word [coin_batch_timer], 70
    
    ; 3. SET CONSTANT SPEED (So road moves)
    mov word [player_speed], 3   ; Fixed cruising speed
    
    ; 4. Reset Coin Logic
    mov word [coins_remaining], 0
    mov word [current_coin_lane], 160
    mov word [coin_gap_timer], 0

    ; 5. Clear coins
    mov cx, MAX_COINS
    xor si, si
.clear_loop:
    mov byte [coins_active + si], 0
    inc si
    loop .clear_loop

    pop cx
    pop si
    pop ax
    pop dx
    ret    

; ============================================
; random_lane (STRICT: Returns 100, 160, or 220)
; ============================================
random_lane:
    push bx
    push dx
    
    mov ax, [seed]
    mov bx, 25173
    mul bx
    add ax, 13849
    mov [seed], ax
    
    xor dx, dx
    mov bx, 3       ; Divide by 3
    div bx          ; DX = Remainder (0, 1, or 2)
    
    cmp dx, 0
    je .lane_left
    cmp dx, 1
    je .lane_mid
    
    ; .lane_right
    mov ax, 220     ; Right Lane Center
    jmp .done_rnd
    
.lane_left:
    mov ax, 100     ; Left Lane Center
    jmp .done_rnd
    
.lane_mid:
    mov ax, 160     ; Middle Lane Center
    
.done_rnd:
    pop dx
    pop bx
    ret
; ============================================
; random_road_x (returns x on road: 110 - 199)
; ============================================
random_road_x:
    mov ax, [seed]
    mov bx, 25173
    mul bx
    add ax, 13849
    mov [seed], ax

    xor dx, dx
    mov bx, 90
    div bx              ; AX = q, DX = r (0..89)
    add dx, 110         ; 110..199
    mov ax, dx
    ret

; (still available if you want random Y, but not used for spawn now)
random_y_position:
    mov ax, [seed]
    mov bx, 25173
    mul bx
    add ax, 13849
    mov [seed], ax

    xor dx, dx
    mov bx, 80
    div bx              ; DX = 0..79
    add dx, 20          ; 20..99
    mov ax, dx
    ret

; ============================================
; spawn_and_update_obstacles
; ============================================
spawn_and_update_obstacles:
    inc word [spawn_timer]
    mov ax, 80
    sub ax, [player_speed]     ; Faster spawn at higher speed
    cmp ax, 30
    jge .ok
    mov ax, 30
.ok:
    cmp word [spawn_timer], ax
    jb .update
    mov word [spawn_timer], 0
    cmp byte [obstacle_active], 1
    je .update

    call random_lane
    sub ax ,8
    mov [obstacle_x], ax
    mov word [obstacle_y], 0
    mov byte [obstacle_active], 1
.update:
    cmp byte [obstacle_active], 0
    je .done
    ; Move obstacle down: base + player_speed
    mov ax, [base_scroll]
    add ax, [player_speed]
    add [obstacle_y], ax
    mov ax, [obstacle_y]
; ---- keep the car inside the road while it moves ----
    mov ax, [obstacle_x]
    cmp ax, 100-8                    ; left road edge – half car width
    jge .not_left
    mov ax, 100-8
    mov [obstacle_x], ax
.not_left:
    cmp ax, 220+8                    ; right road edge – half car width
    jle .not_right
    mov ax, 220+8
    mov [obstacle_x], ax
.not_right:

    mov ax, [obstacle_y]
    cmp ax, 200
    jb .done
    mov byte [obstacle_active], 0
.done:
    ret
    ;cmp ax, 200
    ;jb .done
    ;mov byte [obstacle_active], 0

; ==============================================================
; NEW: draw_golden_coin  (realistic 11×11 golden coin)
; Input : SI = centre X, BX = centre Y
; Uses  : ES = buffer segment (0xB000)
; ==============================================================
draw_golden_coin:
    pusha

    ; ----- Row -5 (top edge) -----
    mov  ax, bx
    sub  ax, 5
    js   .skip_r5
    cmp  ax, 199
    jg   .skip_r5
    push ax
    mov  cx, 320
    mul  cx
    add  ax, [buffer_seg]      ; ES points to buffer
    mov  di, ax
    add  di, si
    sub  di, 2
    mov  byte [es:di+0], 0      ; shadow
    mov  byte [es:di+1], 6      ; dark outline
    mov  byte [es:di+2], 6
    mov  byte [es:di+3], 6
    mov  byte [es:di+4], 0
    pop  ax
.skip_r5:

    ; ----- Row -4 -----
    mov  ax, bx
    sub  ax, 4
    js   .skip_r4
    cmp  ax, 199
    jg   .skip_r4
    push ax
    mov  cx, 320
    mul  cx
    add  ax, [buffer_seg]
    mov  di, ax
    add  di, si
    sub  di, 3
    mov  byte [es:di+0], 0
    mov  byte [es:di+1], 6
    mov  byte [es:di+2], 14     ; gold
    mov  byte [es:di+3], 15     ; bright highlight
    mov  byte [es:di+4], 14
    mov  byte [es:di+5], 6
    mov  byte [es:di+6], 0
    pop  ax
.skip_r4:

    ; ----- Row -3 -----
    mov  ax, bx
    sub  ax, 3
    js   .skip_r3
    cmp  ax, 199
    jg   .skip_r3
    push ax
    mov  cx, 320
    mul  cx
    add  ax, [buffer_seg]
    mov  di, ax
    add  di, si
    sub  di, 4
    mov  byte [es:di+0], 0
    mov  byte [es:di+1], 6
    mov  byte [es:di+2], 14
    mov  byte [es:di+3], 15
    mov  byte [es:di+4], 15
    mov  byte [es:di+5], 15
    mov  byte [es:di+6], 14
    mov  byte [es:di+7], 6
    mov  byte [es:di+8], 0
    pop  ax
.skip_r3:

    ; ----- Row -2 -----
    mov  ax, bx
    sub  ax, 2
    js   .skip_r2
    cmp  ax, 199
    jg   .skip_r2
    push ax
    mov  cx, 320
    mul  cx
    add  ax, [buffer_seg]
    mov  di, ax
    add  di, si
    sub  di, 4
    mov  byte [es:di+0], 6
    mov  byte [es:di+1], 14
    mov  byte [es:di+2], 15
    mov  byte [es:di+3], 15
    mov  byte [es:di+4], 14
    mov  byte [es:di+5], 14
    mov  byte [es:di+6], 14
    mov  byte [es:di+7], 14
    mov  byte [es:di+8], 6
    pop  ax
.skip_r2:

    ; ----- Row -1 -----
    mov  ax, bx
    dec  ax
    js   .skip_r1
    cmp  ax, 199
    jg   .skip_r1
    push ax
    mov  cx, 320
    mul  cx
    add  ax, [buffer_seg]
    mov  di, ax
    add  di, si
    sub  di, 4
    mov  byte [es:di+0], 6
    mov  byte [es:di+1], 14
    mov  byte [es:di+2], 14
    mov  byte [es:di+3], 14
    mov  byte [es:di+4], 14
    mov  byte [es:di+5], 14
    mov  byte [es:di+6], 14
    mov  byte [es:di+7], 14
    mov  byte [es:di+8], 6
    pop  ax
.skip_r1:

    ; ----- Row 0 (center) -----
    mov  ax, bx
    js   .skip_r0
    cmp  ax, 199
    jg   .skip_r0
    push ax
    mov  cx, 320
    mul  cx
    add  ax, [buffer_seg]
    mov  di, ax
    add  di, si
    sub  di, 4
    mov  byte [es:di+0], 6
    mov  byte [es:di+1], 14
    mov  byte [es:di+2], 14
    mov  byte [es:di+3], 14
    mov  byte [es:di+4], 14
    mov  byte [es:di+5], 14
    mov  byte [es:di+6], 14
    mov  byte [es:di+7], 14
    mov  byte [es:di+8], 6
    pop  ax
.skip_r0:

    ; ----- Row +1 -----
    mov  ax, bx
    inc  ax
    js   .skip_r1b
    cmp  ax, 199
    jg   .skip_r1b
    push ax
    mov  cx, 320
    mul  cx
    add  ax, [buffer_seg]
    mov  di, ax
    add  di, si
    sub  di, 4
    mov  byte [es:di+0], 6
    mov  byte [es:di+1], 14
    mov  byte [es:di+2], 14
    mov  byte [es:di+3], 14
    mov  byte [es:di+4], 14
    mov  byte [es:di+5], 14
    mov  byte [es:di+6], 6
    mov  byte [es:di+7], 6
    mov  byte [es:di+8], 6
    pop  ax
.skip_r1b:

    ; ----- Row +2 -----
    mov  ax, bx
    add  ax, 2
    js   .skip_r2b
    cmp  ax, 199
    jg   .skip_r2b
    push ax
    mov  cx, 320
    mul  cx
    add  ax, [buffer_seg]
    mov  di, ax
    add  di, si
    sub  di, 4
    mov  byte [es:di+0], 6
    mov  byte [es:di+1], 14
    mov  byte [es:di+2], 14
    mov  byte [es:di+3], 6
    mov  byte [es:di+4], 6
    mov  byte [es:di+5], 6
    mov  byte [es:di+6], 6
    mov  byte [es:di+7], 6
    mov  byte [es:di+8], 6
    pop  ax
.skip_r2b:

    ; ----- Row +3 -----
    mov  ax, bx
    add  ax, 3
    js   .skip_r3b
    cmp  ax, 199
    jg   .skip_r3b
    push ax
    mov  cx, 320
    mul  cx
    add  ax, [buffer_seg]
    mov  di, ax
    add  di, si
    sub  di, 4
    mov  byte [es:di+0], 0
    mov  byte [es:di+1], 6
    mov  byte [es:di+2], 6
    mov  byte [es:di+3], 6
    mov  byte [es:di+4], 6
    mov  byte [es:di+5], 6
    mov  byte [es:di+6], 6
    mov  byte [es:di+7], 6
    mov  byte [es:di+8], 0
    pop  ax
.skip_r3b:

    ; ----- Row +4 -----
    mov  ax, bx
    add  ax, 4
    js   .skip_r4b
    cmp  ax, 199
    jg   .skip_r4b
    push ax
    mov  cx, 320
    mul  cx
    add  ax, [buffer_seg]
    mov  di, ax
    add  di, si
    sub  di, 3
    mov  byte [es:di+0], 0
    mov  byte [es:di+1], 6
    mov  byte [es:di+2], 6
    mov  byte [es:di+3], 6
    mov  byte [es:di+4], 6
    mov  byte [es:di+5], 6
    mov  byte [es:di+6], 0
    pop  ax
.skip_r4b:

    ; ----- Row +5 (bottom edge) -----
    mov  ax, bx
    add  ax, 5
    js   .skip_r5b
    cmp  ax, 199
    jg   .skip_r5b
    push ax
    mov  cx, 320
    mul  cx
    add  ax, [buffer_seg]
    mov  di, ax
    add  di, si
    sub  di, 2
    mov  byte [es:di+0], 0
    mov  byte [es:di+1], 6
    mov  byte [es:di+2], 6
    mov  byte [es:di+3], 6
    mov  byte [es:di+4], 0
    pop  ax
.skip_r5b:

    popa
    ret
; ============================================
; spawn_coins (FIXED: 4 Seconds Gap + Axis Alignment)
; ============================================
spawn_coins:
    ; Update Timer
    inc word [coin_batch_timer]
    
    ; CHANGE: Wait approx 4-5 seconds (approx 70 frames at your speed)
    cmp word [coin_batch_timer], 70 
    jb .check_queue

    ; --- START NEW BATCH ---
    mov word [coin_batch_timer], 0
    mov word [coins_remaining], 3      ; Set of 3 coins
    
    call random_lane
    mov [current_coin_lane], ax        ; Lock the lane

.check_queue:
    ; Are we spawning a set?
    cmp word [coins_remaining], 0
    je .done

    ; Gap Logic (keep them close together in the set)
    inc word [coin_gap_timer]
    cmp word [coin_gap_timer], 6       
    jb .done
    mov word [coin_gap_timer], 0

    ; --- SPAWN A COIN ---
    ; Find empty slot
    mov cx, MAX_COINS
    xor si, si
.find_slot:
    cmp byte [coins_active + si], 0
    je .found_slot
    inc si
    loop .find_slot
    jmp .done

.found_slot:
    mov bx, si
    shl bx, 1

    ; --- SAFETY & AXIS ALIGNMENT ---
    mov ax, [current_coin_lane]
    
    ; Safety: Force onto road if glitches occur
    cmp ax, 80
    jae .check_right
    mov ax, 160
    mov [current_coin_lane], ax    
    jmp .apply_offset

.check_right:
    cmp ax, 240
    jbe .apply_offset
    mov ax, 160
    mov [current_coin_lane], ax

.apply_offset:
    ; CHANGE: Add +6 pixels so coin aligns with CAR CENTER
    ; This fixes the collision issue!
    add ax, 6 

    mov [coins_x + bx], ax         ; Set Aligned X
    mov word [coins_y + bx], 0     ; Set Y (Top)
    mov byte [coins_active + si], 1
    dec word [coins_remaining]

.done:
    ret
; ============================================
; update_all_coins
; ============================================
update_all_coins:
    mov cx, MAX_COINS
    xor si, si
.update_loop:
    cmp byte [coins_active + si], 0
    je .next
    mov bx, si
    shl bx, 1
    ; Move coin down: base + player_speed
    mov ax, [base_scroll]
    add ax, [player_speed]
    add [coins_y + bx], ax
    mov ax, [coins_y + bx]
    cmp ax, 200
    jb .next
    mov byte [coins_active + si], 0
.next:
    inc si
    loop .update_loop
    ret
; ============================================
; check_obstacle_collision
; ============================================
check_obstacle_collision:
    cmp byte [obstacle_active], 0
    je  near .done

    mov ax, [obstacle_x]
    mov dx, [obstacle_y]
; In check_obstacle_collision, after 'mov dx, [obstacle_y]':
    ; X overlap (generous 28px)
    mov di, [player_x]
    sub di, 6
    cmp ax, di
    jb near .no_collision
    add di, 28
    cmp ax, di
    ja near .no_collision
    ; Y overlap (generous 40px)
    mov di, [player_y]
    sub di, 6
    cmp dx, di
    jb near .no_collision
    add di, 40
    cmp dx, di
    ja near .no_collision
    ; Collision! Game over
    mov byte [game_over_flag], 1
.no_collision:


.done:
    ret


; ============================================
; check_all_coin_collisions - FIXED: Only when coin center enters car body
; Hitbox exactly matches drawn red car (precise "hits the car")
; Car body: X=[player_x+2, player_x+14] (12px wide, skips bumpers), Y=[player_y+2, player_y+26] (24px tall, body/windows)
; ============================================
check_all_coin_collisions:
    mov cx, MAX_COINS
    xor si, si
.check_loop:
    push cx
    push si
    cmp byte [coins_active + si], 0
    je near .next_coin
    ; Get coin center position
    mov bx, si
    shl bx, 1
    mov ax, [coins_x + bx]
    mov dx, [coins_y + bx]
    ; X overlap: coin_x >= player_x + 2 && coin_x <= player_x + 14 (exact car body width)
    mov di, [player_x]
    add di, 2               ; left edge of car body
    cmp ax, di
    jb near .no_collision
    add di, 12              ; body width 12px
    cmp ax, di
    ja near .no_collision
    ; Y overlap: coin_y >= player_y + 2 && coin_y <= player_y + 26 (exact car body height)
    mov di, [player_y]
    add di, 2               ; top of car body (skip roof)
    cmp dx, di
    jb near .no_collision
    add di, 24              ; body height 24px (to bottom before wheels)
    cmp dx, di
    ja near .no_collision
    ; PERFECT HIT! Coin center inside car body → increment score
    mov byte [coins_active + si], 0
    inc word [score]
.no_collision:
.next_coin:
    pop si
    pop cx
    inc si
    loop .check_loop
    ret
; ============================================
; draw_scene
; ============================================
draw_scene:
    call draw_scrolling_background   ; 1. Background first
    call draw_curbs                  ; 2. Curbs
    call draw_road_markings          ; 3. Lane markings
    call draw_guardrails             ; 4. Guardrails
    call draw_all_trees              ; 5. Trees (static in world)
    call draw_all_coins              ; 6. Coins
    call draw_obstacle_car           ; 7. Obstacle
    call draw_player_car             ; 8. Player (on top)
    ret
; ============================================
; draw_ui (score and fuel in VGA mode)
; ============================================
draw_ui:
    pusha

    ; Draw "FUEL:" at (y=5,x=5)
    mov bx, 5           ; y
    mov si, 5           ; x
    mov al, 15
    call draw_char_F
    add si, 8
    call draw_char_U
    add si, 8
    call draw_char_E
    add si, 8
    call draw_char_L
    add si, 8
    call draw_char_colon


    ; Draw fuel number
    add si, 8
    mov ax, [fuel]
    call draw_number

    ; Draw "SCORE:" at (y=20,x=5)
    mov bx, 5
    mov si, 260
    call draw_char_S
    add si, 8
    call draw_char_C
    add si, 8
    call draw_char_O
    add si, 8
    call draw_char_R
    add si, 8
    call draw_char_E
    add si, 8
    call draw_char_colon

    add si,8
    mov ax, [score]
    call draw_number

    popa
    ret

; ============================================
; DRAW CURBS - SCROLLING VERSION
; Continuous scrolling curbs with pattern
; ============================================
draw_curbs:
    pusha
    
    xor bx, bx      ; screen row (0-199)
.curb_row_loop:
    cmp bx, 200
    jge .done
    
    ; World Y for this screen row = (scroll_offset + bx) % 200
    mov ax, [scroll_offset]
    add ax, bx
    cmp ax, 200
    jb .no_curb_wrap
    sub ax, 200
.no_curb_wrap:
    mov si, ax      ; world_y
    
    ; Screen offset for this row
    mov ax, bx
    mov dx, 320
    mul dx
    mov di, ax
    
    ; LEFT CURB (2px wide at x=98-99)
    add di, 68
    mov ax, si      ; world_y
    and ax, 16      ; pattern repeat every 16 world pixels
    test ax, ax
    jnz .left_white
    mov byte [es:di], 12      ; red
    mov byte [es:di+1], 12
    jmp .right_curb
.left_white:
    mov byte [es:di], 15      ; white
    mov byte [es:di+1], 15
    
.right_curb:
    ; RIGHT CURB (2px wide at x=218-219)
    mov ax, bx
    mov dx, 320
    mul dx
    mov di, ax
    add di, 250
    mov ax, si
    and ax, 16
    test ax, ax
    jnz .right_white
    mov byte [es:di], 12      ; red
    mov byte [es:di+1], 12
    jmp .next_curb_row
.right_white:
    mov byte [es:di], 15      ; white
    mov byte [es:di+1], 15
    
.next_curb_row:
    inc bx
    jmp .curb_row_loop
    
.done:
    popa
    ret
; ============================================
; draw_road_markings - 3 LANE VERSION
; ============================================
draw_road_markings:
    pusha
    
    mov bx, 0       ; Screen row (0-199)
    
.row_loop:
    cmp bx, 200
    jge .done
    
    ; World Y = (scroll_offset + bx) % 200
    mov ax, [scroll_offset]
    add ax, bx
    cmp ax, 200
    jb .no_mark_wrap
    sub ax, 200
.no_mark_wrap:
    mov si, ax      ; si = world_y
    
    ; Check if we should draw a dash here (dashed line logic)
    ; We want dashes 10 pixels long, with 10 pixels gaps
    xor dx, dx
    mov ax, si      ; world_y
    mov cx, 20
    div cx          ; dx = world_y % 20
    cmp dx, 10
    jge .skip_marks ; If remainder > 10, skip (gap)
    
    ; Calculate screen offset for this row
    mov ax, bx
    mov dx, 320
    mul dx
    mov di, ax      ; di = start of the line on screen
    
    ; --- LINE 1 (Separates Left and Middle Lane) ---
    ; Position: X = 130
    push di
    add di, 130
    mov byte [es:di], 15   ; White
    pop di

    ; --- LINE 2 (Separates Middle and Right Lane) ---
    ; Position: X = 190
    push di
    add di, 190
    mov byte [es:di], 15   ; White
    pop di
    
.skip_marks:
    inc bx
    jmp .row_loop
    
.done:
    popa
    ret
;============================================
; DRAW ALL TREES - SCROLLING VERSION
; Trees move with world scroll (infinite road)
; ============================================
draw_all_trees:
    pusha
    
    ; Left side trees
    mov si, 50        ; Y position
    mov di, 30        ; X position
    call draw_one_tree
    
    mov si, 100
    mov di, 45
    call draw_one_tree
    
    mov si, 150
    mov di, 25
    call draw_one_tree
    
    ; Right side trees
    mov si, 60
    mov di, 270
    call draw_one_tree
    
    mov si, 110
    mov di, 285
    call draw_one_tree
    
    mov si, 165
    mov di, 255
    call draw_one_tree
    
    popa
    ret
; ============================================
; DRAW ONE TREE
; Input: SI = Y position, DI = X position
; ============================================
draw_one_tree:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    
    ; Draw foliage in multiple layers for depth
    ; Layer 1 - Dark green background/shadow
    mov bx, si
    add bx, 2
    mov cx, 18
    
.dark_foliage:
    push cx
    
    mov ax, bx
    mov dx, 320
    mul dx
    add ax, di
    sub ax, 8
    push di
    mov di, ax
    
    push cx
    ; Create rounded shape
    cmp cx, 16
    jg .dark_top
    cmp cx, 4
    jl .dark_bottom
    
    ; Middle (widest)
    mov al, 2         ; Dark green
    mov cx, 24
    rep stosb
    jmp .dark_done
    
.dark_top:
    add di, 4
    mov al, 2
    mov cx, 16
    rep stosb
    jmp .dark_done
    
.dark_bottom:
    add di, 2
    mov al, 2
    mov cx, 20
    rep stosb
    
.dark_done:
    pop cx
    pop di
    inc bx
    pop cx
    loop .dark_foliage
    
    ; Layer 2 - Lighter green highlights
    mov bx, si
    mov cx, 16
    
.light_foliage:
    push cx
    
    mov ax, bx
    mov dx, 320
    mul dx
    add ax, di
    sub ax, 5
    push di
    mov di, ax
    
    push cx
    ; Highlight pattern (not full coverage)
    cmp cx, 14
    jg .light_top
    cmp cx, 5
    jl .light_bottom
    
    ; Middle highlights - scattered
    mov al, 10        ; Light green
    ; Draw scattered pixels
    stosb
    add di, 2
    stosb
    stosb
    add di, 3
    stosb
    add di, 2
    stosb
    stosb
    add di, 1
    stosb
    jmp .light_done
    
.light_top:
    add di, 3
    mov al, 10
    stosb
    add di, 1
    stosb
    add di, 2
    stosb
    jmp .light_done
    
.light_bottom:
    add di, 2
    mov al, 10
    stosb
    add di, 3
    stosb
    add di, 2
    stosb
    
.light_done:
    pop cx
    pop di
    inc bx
    pop cx
    loop .light_foliage
    
    ; Draw trunk with texture
    mov bx, si
    add bx, 16        ; Start trunk below foliage
    mov cx, 18        ; Trunk height
    
.trunk_row:
    push cx
    
    mov ax, bx
    mov dx, 320
    mul dx
    add ax, di
    push di
    mov di, ax
    
    ; Create bark texture with variations
    push cx
    mov ax, cx
    and ax, 3         ; Pattern every 4 rows
    
    cmp ax, 0
    je .trunk_dark
    cmp ax, 1
    je .trunk_mixed
    
    ; Normal brown
    mov al, 6
    mov cx, 8
    rep stosb
    jmp .trunk_done
    
.trunk_dark:
    ; Darker brown spots
    mov byte [es:di], 6
    mov byte [es:di+1], 6
    mov byte [es:di+2], 0    ; Dark spot
    mov byte [es:di+3], 6
    mov byte [es:di+4], 6
    mov byte [es:di+5], 0    ; Dark spot
    mov byte [es:di+6], 6
    mov byte [es:di+7], 6
    jmp .trunk_done
    
.trunk_mixed:
    ; Light and dark brown mix
    mov byte [es:di], 6
    mov byte [es:di+1], 14   ; Lighter brown
    mov byte [es:di+2], 6
    mov byte [es:di+3], 6
    mov byte [es:di+4], 14   ; Lighter brown
    mov byte [es:di+5], 6
    mov byte [es:di+6], 6
    mov byte [es:di+7], 6
    
.trunk_done:
    pop cx
    pop di
    inc bx
    pop cx
    loop .trunk_row
    
    ; Add small branches sticking out
    ; Left branch
    mov ax, si
    add ax, 20
    mov bx, ax
    mov dx, 320
    mul dx
    add ax, di
    sub ax, 4
    mov di, ax
    mov byte [es:di], 6
    mov byte [es:di+1], 6
    mov byte [es:di+2], 6
    
    ; Right branch
    mov ax, si
    add ax, 23
    mov bx, ax
    mov dx, 320
    mul dx
    pop di
    push di
    add ax, di
    add ax, 8
    mov di, ax
    mov byte [es:di], 6
    mov byte [es:di+1], 6
    mov byte [es:di+2], 6
    
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ============================================
; DRAW GUARDRAILS - SCROLLING VERSION
; 8 posts per side, spaced ~25 pixels apart
; ============================================
draw_guardrails:
    pusha
    
    ; LEFT GUARDRAIL (8 posts)
    mov cx, 8
    xor si, si
.left_posts:
    ; World Y = post spacing * index + scroll_offset
    mov ax, si
    mov bx, 25      ; post spacing
    mul bx
    add ax, [scroll_offset]
    mov bx, ax      ; world_y
    
.wrap_left:
    cmp bx, 200
    jb .screen_left_post
    sub bx, 200
    jmp .wrap_left
    
.screen_left_post:
    ; Skip if off-screen
    cmp bx, 0
    jl .next_left_post
    cmp bx, 15      ; post height=8, so visible if top <=199
    jg .next_left_post
    
    ; Draw 8-pixel tall post at X=92 (left road edge)
    mov di, bx      ; start y
    mov dx, 92      ; fixed x
    
    push cx
    mov cx, 8       ; height
.left_post_rows:
    push cx
    mov ax, di
    mov cx, 320
    mul cx
    add ax, dx
    mov bp, ax      ; temp di
    
    mov byte [es:bp], 7     ; gray post (3px wide)
    mov byte [es:bp+1], 7
    mov byte [es:bp+2], 7
    
    inc di
    pop cx
    loop .left_post_rows
    pop cx
    
.next_left_post:
    inc si
    loop .left_posts
    
    ; RIGHT GUARDRAIL (8 posts, offset by 12)
    mov cx, 8
    xor si, si
.right_posts:
    mov ax, si
    mov bx, 25
    mul bx
    add ax, 12      ; right offset
    add ax, [scroll_offset]
    mov bx, ax
    
.wrap_right:
    cmp bx, 200
    jb .screen_right_post
    sub bx, 200
    jmp .wrap_right
    
.screen_right_post:
    cmp bx, 0
    jl .next_right_post
    cmp bx, 15
    jg .next_right_post
    
    mov di, bx
    mov dx, 225     ; right road edge
    
    push cx
    mov cx, 8
.right_post_rows:
    push cx
    mov ax, di
    mov cx, 320
    mul cx
    add ax, dx
    mov bp, ax
    
    mov byte [es:bp], 7
    mov byte [es:bp+1], 7
    mov byte [es:bp+2], 7
    
    inc di
    pop cx
    loop .right_post_rows
    pop cx
    
.next_right_post:
    inc si
    loop .right_posts
    
    popa
    ret
; ============================================
; draw_number (draw number in AX at BX, SI)
; ============================================
draw_number:
    push ax
    push bx
    push cx
    push dx
    push di
    push si

    mov di, si          ; current x position

    cmp ax, 0
    jne near .not_zero

    ; draw single '0'
    mov dx, 0
    mov si, di
    call draw_digit
    jmp near .done

.not_zero:
    mov cx, 0           ; digit count
    mov bx, 10

.loop_push:
    xor dx, dx
    div bx              ; AX = q, DX = r
    push dx             ; store digit
    inc cx
    test ax, ax
    jnz near .loop_push

.loop_pop:
    pop dx              ; digit
    mov si, di
    call draw_digit
    add di, 8           ; move to next digit position
    dec cx
    jnz near .loop_pop

.done:
    pop si
    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ============================================
; draw_digit (draw digit in DX at BX, SI)
; ============================================
draw_digit:
    push ax
    push bx
    push cx
    push dx
    push di
    push si

    mov cx, dx          ; CX = digit (0..9)

    ; compute screen offset: y = BX, x = SI
    mov ax, bx
    mov dx, 320
    mul dx
    add ax, si
    mov di, ax

    ; Branch based on digit value in CX
    cmp cx, 0
    je  near .digit_0
    cmp cx, 1
    je  near .digit_1
    cmp cx, 2
    je  near .digit_2
    cmp cx, 3
    je  near .digit_3
    cmp cx, 4
    je  near .digit_4
    cmp cx, 5
    je  near .digit_5
    cmp cx, 6
    je  near .digit_6
    cmp cx, 7
    je  near .digit_7
    cmp cx, 8
    je  near .digit_8
    cmp cx, 9
    je  near .digit_9
    jmp near .done_digit

.digit_0:
    mov al, 14
    mov byte [es:di], al
    mov byte [es:di+1], al
    mov byte [es:di+2], al
    add di, 320
    mov byte [es:di], al
    mov byte [es:di+2], al
    add di, 320
    mov byte [es:di], al
    mov byte [es:di+2], al
    add di, 320
    mov byte [es:di], al
    mov byte [es:di+2], al
    add di, 320
    mov byte [es:di], al
    mov byte [es:di+1], al
    mov byte [es:di+2], al
    jmp near .done_digit

.digit_1:
    mov al, 14
    add di, 1
    mov byte [es:di], al
    add di, 320
    mov byte [es:di], al
    add di, 320
    mov byte [es:di], al
    add di, 320
    mov byte [es:di], al
    add di, 320
    mov byte [es:di], al
    jmp near .done_digit

.digit_2:
    mov al, 14
    mov byte [es:di], al
    mov byte [es:di+1], al
    mov byte [es:di+2], al
    add di, 320
    mov byte [es:di+2], al
    add di, 320
    mov byte [es:di], al
    mov byte [es:di+1], al
    mov byte [es:di+2], al
    add di, 320
    mov byte [es:di], al
    add di, 320
    mov byte [es:di], al
    mov byte [es:di+1], al
    mov byte [es:di+2], al
    jmp near .done_digit

.digit_3:
    mov al, 14
    mov byte [es:di], al
    mov byte [es:di+1], al
    mov byte [es:di+2], al
    add di, 320
    mov byte [es:di+2], al
    add di, 320
    mov byte [es:di], al
    mov byte [es:di+1], al
    mov byte [es:di+2], al
    add di, 320
    mov byte [es:di+2], al
    add di, 320
    mov byte [es:di], al
    mov byte [es:di+1], al
    mov byte [es:di+2], al
    jmp near .done_digit

.digit_4:
    mov al, 14
    mov byte [es:di], al
    mov byte [es:di+2], al
    add di, 320
    mov byte [es:di], al
    mov byte [es:di+2], al
    add di, 320
    mov byte [es:di], al
    mov byte [es:di+1], al
    mov byte [es:di+2], al
    add di, 320
    mov byte [es:di+2], al
    add di, 320
    mov byte [es:di+2], al
    jmp near .done_digit

.digit_5:
    mov al, 14
    mov byte [es:di], al
    mov byte [es:di+1], al
    mov byte [es:di+2], al
    add di, 320
    mov byte [es:di], al
    add di, 320
    mov byte [es:di], al
    mov byte [es:di+1], al
    mov byte [es:di+2], al
    add di, 320
    mov byte [es:di+2], al
    add di, 320
    mov byte [es:di], al
    mov byte [es:di+1], al
    mov byte [es:di+2], al
    jmp near .done_digit

.digit_6:
    mov al, 14
    mov byte [es:di], al
    mov byte [es:di+1], al
    mov byte [es:di+2], al
    add di, 320
    mov byte [es:di], al
    add di, 320
    mov byte [es:di], al
    mov byte [es:di+1], al
    mov byte [es:di+2], al
    add di, 320
    mov byte [es:di], al
    mov byte [es:di+2], al
    add di, 320
    mov byte [es:di], al
    mov byte [es:di+1], al
    mov byte [es:di+2], al
    jmp near .done_digit

.digit_7:
    mov al, 14
    mov byte [es:di], al
    mov byte [es:di+1], al
    mov byte [es:di+2], al
    add di, 320
    mov byte [es:di+2], al
    add di, 320
    mov byte [es:di+2], al
    add di, 320
    mov byte [es:di+2], al
    add di, 320
    mov byte [es:di+2], al
    jmp near .done_digit

.digit_8:
    mov al, 14
    mov byte [es:di], al
    mov byte [es:di+1], al
    mov byte [es:di+2], al
    add di, 320
    mov byte [es:di], al
    mov byte [es:di+2], al
    add di, 320
    mov byte [es:di], al
    mov byte [es:di+1], al
    mov byte [es:di+2], al
    add di, 320
    mov byte [es:di], al
    mov byte [es:di+2], al
    add di, 320
    mov byte [es:di], al
    mov byte [es:di+1], al
    mov byte [es:di+2], al
    jmp near .done_digit

.digit_9:
    mov al, 14
    mov byte [es:di], al
    mov byte [es:di+1], al
    mov byte [es:di+2], al
    add di, 320
    mov byte [es:di], al
    mov byte [es:di+2], al
    add di, 320
    mov byte [es:di], al
    mov byte [es:di+1], al
    mov byte [es:di+2], al
    add di, 320
    mov byte [es:di+2], al
    add di, 320
    mov byte [es:di], al
    mov byte [es:di+1], al
    mov byte [es:di+2], al

.done_digit:
    pop si
    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ============================================
; Character drawing routines (simple 5x7)
; ============================================
draw_char_F:
    push ax
    push di
    mov ax, bx
    mov di, 320
    mul di
    add ax, si
    mov di, ax
    mov al, 15
    mov byte [es:di], al
    mov byte [es:di+1], al
    mov byte [es:di+2], al
    add di, 320
    mov byte [es:di], al
    add di, 320
    mov byte [es:di], al
    mov byte [es:di+1], al
    add di, 320
    mov byte [es:di], al
    add di, 320
    mov byte [es:di], al
    pop di
    pop ax
    ret

draw_char_U:
    push ax
    push di
    mov ax, bx
    mov di, 320
    mul di
    add ax, si
    mov di, ax
    mov al, 15
    mov byte [es:di], al
    mov byte [es:di+2], al
    add di, 320
    mov byte [es:di], al
    mov byte [es:di+2], al
    add di, 320
    mov byte [es:di], al
    mov byte [es:di+2], al
    add di, 320
    mov byte [es:di], al
    mov byte [es:di+2], al
    add di, 320
    mov byte [es:di], al
    mov byte [es:di+1], al
    mov byte [es:di+2], al
    pop di
    pop ax
    ret

draw_char_E:
    push ax
    push di
    mov ax, bx
    mov di, 320
    mul di
    add ax, si
    mov di, ax
    mov al, 15
    mov byte [es:di], al
    mov byte [es:di+1], al
    mov byte [es:di+2], al
    add di, 320
    mov byte [es:di], al
    add di, 320
    mov byte [es:di], al
    mov byte [es:di+1], al
    add di, 320
    mov byte [es:di], al
    add di, 320
    mov byte [es:di], al
    mov byte [es:di+1], al
    mov byte [es:di+2], al
    pop di
    pop ax
    ret

draw_char_L:
    push ax
    push di
    mov ax, bx
    mov di, 320
    mul di
    add ax, si
    mov di, ax
    mov al, 15
    mov byte [es:di], al
    add di, 320
    mov byte [es:di], al
    add di, 320
    mov byte [es:di], al
    add di, 320
    mov byte [es:di], al
    add di, 320
    mov byte [es:di], al
    mov byte [es:di+1], al
    mov byte [es:di+2], al
    pop di
    pop ax
    ret

draw_char_S:
    push ax
    push di
    mov ax, bx
    mov di, 320
    mul di
    add ax, si
    mov di, ax
    mov al, 15
    mov byte [es:di], al
    mov byte [es:di+1], al
    mov byte [es:di+2], al
    add di, 320
    mov byte [es:di], al
    add di, 320
    mov byte [es:di], al
    mov byte [es:di+1], al
    mov byte [es:di+2], al
    add di, 320
    mov byte [es:di+2], al
    add di, 320
    mov byte [es:di], al
    mov byte [es:di+1], al
    mov byte [es:di+2], al
    pop di
    pop ax
    ret

draw_char_C:
    push ax
    push di
    mov ax, bx
    mov di, 320
    mul di
    add ax, si
    mov di, ax
    mov al, 15
    mov byte [es:di], al
    mov byte [es:di+1], al
    mov byte [es:di+2], al
    add di, 320
    mov byte [es:di], al
    add di, 320
    mov byte [es:di], al
    add di, 320
    mov byte [es:di], al
    add di, 320
    mov byte [es:di], al
    mov byte [es:di+1], al
    mov byte [es:di+2], al
    pop di
    pop ax
    ret

draw_char_O:
    push ax
    push di
    mov ax, bx
    mov di, 320
    mul di
    add ax, si
    mov di, ax
    mov al, 15
    mov byte [es:di], al
    mov byte [es:di+1], al
    mov byte [es:di+2], al
    add di, 320
    mov byte [es:di], al
    mov byte [es:di+2], al
    add di, 320
    mov byte [es:di], al
    mov byte [es:di+2], al
    add di, 320
    mov byte [es:di], al
    mov byte [es:di+2], al
    add di, 320
    mov byte [es:di], al
    mov byte [es:di+1], al
    mov byte [es:di+2], al
    pop di
    pop ax
    ret

draw_char_R:
    push ax
    push di
    mov ax, bx
    mov di, 320
    mul di
    add ax, si
    mov di, ax
    mov al, 15
    mov byte [es:di], al
    mov byte [es:di+1], al
    mov byte [es:di+2], al
    add di, 320
    mov byte [es:di], al
    mov byte [es:di+2], al
    add di, 320
    mov byte [es:di], al
    mov byte [es:di+1], al
    add di, 320
    mov byte [es:di], al
    mov byte [es:di+2], al
    add di, 320
    mov byte [es:di], al
    mov byte [es:di+2], al
    pop di
    pop ax
    ret

draw_char_colon:
    push ax
    push di
    mov ax, bx
    mov di, 320
    mul di
    add ax, si
    mov di, ax
    add di, 640
    mov al, 15
    mov byte [es:di], al
    add di, 640
    mov byte [es:di], al
    pop di
    pop ax
    ret

draw_char_dollar:
    push ax
    push di
    mov ax, bx
    mov dx, 320
    mul dx
    add ax, si
    mov di, ax
    mov al, 14           ; yellow

    ; Row 0: center
    add di, 1
    mov byte [es:di], al

    ; Row 1: all three
    mov di, ax
    add di, 320
    mov byte [es:di], al
    mov byte [es:di+1], al
    mov byte [es:di+2], al

    ; Row 2: center
    mov di, ax
    add di, 640
    add di, 1
    mov byte [es:di], al

    ; Row 3: all three
    mov di, ax
    add di, 960
    mov byte [es:di], al
    mov byte [es:di+1], al
    mov byte [es:di+2], al

    ; Row 4: center
    mov di, ax
    add di, 1280
    add di, 1
    mov byte [es:di], al

    pop di
    pop ax
    ret

; ============================================
; get_input
; ============================================
get_input:
    mov ah, 0x01
    int 0x16
    jz  near .no_key

    mov ah, 0x00
    int 0x16

    cmp al, 27           ; ESC
    je  near .exit

    cmp ah, 0x4B         ; left
    je  near .move_left

    cmp ah, 0x4D         ; right
    je  near .move_right
    cmp ah, 0x48        ; Up Arrow - Accelerate
    je .move_up_block
    cmp ah, 0x50        ; Down Arrow - Brake/Reverse
    je .move_down_block

    jmp near .no_key
.move_left:
    ; If at Right (220) -> Go Middle (160)
    cmp word [player_x], 220
    je .go_mid_from_right
    ; If at Middle (160) -> Go Left (100)
    cmp word [player_x], 160
    je .go_left
    jmp near .no_key ; Already at left, do nothing

.go_mid_from_right:
    mov word [player_x], 160
    jmp near .no_key
.go_left:
    mov word [player_x], 100
    jmp near .no_key

.move_right:
    ; If at Left (100) -> Go Middle (160)
    cmp word [player_x], 100
    je .go_mid_from_left
    ; If at Middle (160) -> Go Right (220)
    cmp word [player_x], 160
    je .go_right
    jmp near .no_key

.go_mid_from_left:
    mov word [player_x], 160
    jmp near .no_key
.go_right:
    mov word [player_x], 220
    jmp near .no_key


.move_up_block:
    ; Move up by 25 pixels (1 block)
    sub word [player_y], 25
    ; Clamp to Top
    cmp word [player_y], min_y
    jge .no_key
    mov word [player_y], min_y
    jmp .no_key

.move_down_block:
    ; Move down by 25 pixels (1 block)
    add word [player_y], 25
    ; Clamp to Bottom
    cmp word [player_y], max_y
    jle .no_key
    mov word [player_y], max_y
    jmp .no_key
.exit:
    mov ax, 0x0003
    int 0x10
    mov ax, 0x4C00
    int 0x21

.no_key:
    ret
; ============================================
; update_player_position
; (DISABLED: Movement is now handled strictly in get_input)
; ============================================
update_player_position:
    ; Do nothing. 
    ; Position is now updated instantly when keys are pressed.
    ret
; ============================================
; draw_scrolling_background
; ============================================
draw_scrolling_background:
    pusha
    xor bx, bx                  ; bx = screen row (0 to 199)

.row_loop:
    cmp bx, 200
    jge near .done

    ; --- Compute world_y = (scroll_offset + bx) % 200 ---
    mov ax, [scroll_offset]
    add ax, bx                  ; world_y = scroll_offset + screen_y
    cmp ax, 200
    jb .no_wrap
    sub ax, 200
.no_wrap:
    mov si, ax                  ; si = world_y (0–199)

    ; --- Draw one row at screen row bx ---
    ; Calculate screen offset: bx * 320
    mov ax, bx
    mov dx, 320
    mul dx
    mov di, ax                  ; di = screen offset

    ; --- Left grass (100 px) ---
    mov cx, 70
    mov al, 2                   ; dark green
    rep stosb

    ; --- Road (120 px) ---
    mov cx, 180
    mov al, 8                   ; gray
    rep stosb

    ; --- Right grass (100 px) ---
    mov cx, 70
    mov al, 2
    rep stosb

 
.skip_dash:
    inc bx
    jmp .row_loop

.done:
    popa
    ret
; ============================================
; draw_all_coins (With Visual Filter)
; ============================================
draw_all_coins:
    pusha
    mov cx, MAX_COINS
    xor si, si
.loop:
    push cx
    push si
    
    cmp byte [coins_active + si], 0
    je .next

    ; Get Coordinates
    mov bx, si
    shl bx, 1
    mov ax, [coins_x + bx]      ; X center
    mov dx, [coins_y + bx]      ; Y center

    ; --- VISUAL FILTER: DO NOT DRAW IF ON GRASS ---
    cmp ax, 80                  ; Left grass edge
    jb .next                    ; Skip drawing
    cmp ax, 250                 ; Right grass edge
    ja .next                    ; Skip drawing

    ; Draw the coin
    sub ax, 5                   ; Offset for width
    mov si, ax
    sub dx, 5                   ; Offset for height
    mov bx, dx
    call draw_golden_coin

.next:
    pop si
    pop cx
    inc si
    loop .loop
    popa
    ret
; Safe pixel setting with bounds checking
; Input: SI = x, BX = y, AL = color
set_pixel_safe:
    push ax
    push bx
    push si
    push di
    
    ; Check bounds (0-319 for x, 0-199 for y)
    cmp si, 320
    jae .skip
    cmp bx, 200
    jae .skip
    
    ; Calculate offset: DI = y * 320 + x
    mov di, bx
    shl di, 6         ; di = y * 64
    mov ax, bx
    shl ax, 8         ; ax = y * 256
    add di, ax        ; di = y * 320
    add di, si        ; di = y * 320 + x
    
    ; Set pixel in video memory (0xA000:0000)
    push es
    mov ax, 0A000h
    mov es, ax
    mov [es:di], al
    pop es
    
.skip:
    pop di
    pop si
    pop bx
    pop ax
    ret

; Alternative: Simpler 5x7 dollar sign if the above is too large
draw_simple_dollar:
    pusha
    mov al, 14        ; Yellow color
    
    ; Draw a simpler $ pattern
    ; Row 0
    inc si
    call set_pixel_safe
    inc si
    call set_pixel_safe
    inc si
    call set_pixel_safe
    sub si, 3
    inc bx
    
    ; Row 1
    call set_pixel_safe
    inc bx
    
    ; Row 2 (middle)
    call set_pixel_safe
    inc si
    call set_pixel_safe
    inc si
    call set_pixel_safe
    sub si, 2
    inc bx
    
    ; Row 3
    add si, 3
    call set_pixel_safe
    sub si, 3
    inc bx
    
    ; Row 4
    inc si
    call set_pixel_safe
    inc si
    call set_pixel_safe
    sub si, 2
    inc bx
    
    ; Vertical line
    sub bx, 4
    inc si
    mov cx, 5
.vline:
    call set_pixel_safe
    inc bx
    loop .vline
    
    popa
    ret

; ============================================
; draw_player_car
; ============================================

draw_player_car:
    pusha
    
    mov bx, [player_y]  ; Y position
    mov si, [player_x]  ; X position
    mov cx, 28          ; Car height
    
.car_row:
    push cx
    push bx
    
    ; Calculate row offset
    mov ax, bx
    mov dx, 320
    mul dx
    add ax, si
    mov di, ax
    
    ; Determine what part of car we're drawing
    pop bx
    pop cx
    
    push cx
    push bx
    
    ; Top rows (1-6) - roof (narrower)
    cmp cx, 23
    jl .not_roof
    
    add di, 3         ; Offset for narrow roof
    mov al, 4         ; Dark red
    push cx
    mov cx, 10
    rep stosb
    pop cx
    jmp .next_row
    
.not_roof:
    ; Middle rows (7-22) - body
    cmp cx, 7
    jl .wheels
    
    ; Check for window rows (17-22)
    cmp cx, 17
    jl .no_window
    
    ; Draw body with windows
    mov al, 12        ; Bright red
    stosb
    stosb
    stosb
    
    mov al, 14        ; Yellow window
    mov dx, 10
.window_px:
    stosb
    dec dx
    jnz .window_px
    
    mov al, 12        ; Bright red
    stosb
    stosb
    stosb
    jmp .next_row
    
.no_window:
    ; Just body
    mov al, 12
    mov dx, 16
.body_px:
    stosb
    dec dx
    jnz .body_px
    jmp .next_row
    
.wheels:
    ; Bottom rows with wheels
    mov al, 4
    stosb
    stosb
    
    ; Left wheel
    mov al, 0
    stosb
    stosb
    stosb
    stosb
    
    ; Between wheels
    mov al, 4
    stosb
    stosb
    
    ; Right wheel
    mov al, 0
    stosb
    stosb
    stosb
    stosb
    
    ; End
    mov al, 4
    stosb
    stosb
    
.next_row:
    pop bx
    inc bx
    pop cx
    loop .car_row
    
    popa
    ret

; ============================================
; draw_obstacle_car
; ============================================
draw_obstacle_car:
    pusha
    
    mov bx, [obstacle_y]
    mov si, [obstacle_x]
    mov cx, 28
    
.car_row:
    push cx
    push bx
    
    mov ax, bx
    mov dx, 320
    mul dx
    add ax, si
    mov di, ax
    
    pop bx
    pop cx
    
    push cx
    push bx
    
    ; Roof
    cmp cx, 23
    jl .not_roof
    
    add di, 3
    mov al, 1         ; Dark blue
    push cx
    mov cx, 10
    rep stosb
    pop cx
    jmp .next_row
    
.not_roof:
    ; Body
    cmp cx, 7
    jl .wheels
    
    ; Window rows
    cmp cx, 17
    jl .no_window
    
    mov al, 9         ; Bright blue
    stosb
    stosb
    stosb
    
    mov al, 11        ; Cyan window
    mov dx, 10
.window_px:
    stosb
    dec dx
    jnz .window_px
    
    mov al, 9
    stosb
    stosb
    stosb
    jmp .next_row
    
.no_window:
    mov al, 9
    mov dx, 16
.body_px:
    stosb
    dec dx
    jnz .body_px
    jmp .next_row
    
.wheels:
    mov al, 1
    stosb
    stosb
    
    mov al, 0
    stosb
    stosb
    stosb
    stosb
    
    mov al, 1
    stosb
    stosb
    
    mov al, 0
    stosb
    stosb
    stosb
    stosb
    
    mov al, 1
    stosb
    stosb
    
.next_row:
    pop bx
    inc bx
    pop cx
    loop .car_row
    
    popa
    ret
; ============================================
; draw_game_over
; ============================================
draw_game_over:
    pusha

    ; Clear screen
    xor di, di
    mov cx, 32000
    xor ax, ax
    rep stosw

    ; "GAME OVER" centered (approx)
    mov bx, 70
    mov si, 104
    call draw_char_large_G
    add si, 16
    call draw_char_large_A
    add si, 16
    call draw_char_large_M
    add si, 16
    call draw_char_large_E

    add si, 24
    call draw_char_large_O
    add si, 16
    call draw_char_large_V
    add si, 16
    call draw_char_large_E
    add si, 16
    call draw_char_large_R

    ; Draw final score below
    mov bx, 20
    mov si, 128
    call draw_char_S
    add si, 8
    call draw_char_C
    add si, 8
    call draw_char_O
    add si, 8
    call draw_char_R
    add si, 8
    call draw_char_E
    add si, 8
    call draw_char_colon

; Reset X so digits appear exactly after SCORE:
mov bx,110
mov si, 130 +48     ; SCORE + colon + spacing
                          ; 6 characters × 8 pixels each = 48 pixels

mov ax, [score]
call draw_number

        popa
    ret

; ============================================
; Large character routines for "GAME OVER"
; ============================================
draw_char_large_G:
    push ax
    push di
    push cx

    ; compute start offset
    mov ax, bx            ; y
    mov dx, 320
    mul dx
    add ax, si            ; x
    mov di, ax

    mov al, 12            ; color = red

    ; ----- ROW 0: top bar (full width) -----
    mov cx, 12
    rep stosb
    add di, 308           ; next row

    ; ----- ROWS 1–3: left vertical line -----
    mov cx, 3
.row_left1:
    mov byte [es:di], al      ; left edge
    add di, 320
    loop .row_left1

    ; ----- ROW 4: middle row with opening -----
    mov byte [es:di], al
    mov byte [es:di + 1], al
    mov byte [es:di + 2], al
    mov byte [es:di + 3], al
    ; OPEN GAP HERE
    mov byte [es:di + 7], al
    mov byte [es:di + 8], al
    mov byte [es:di + 9], al
    mov byte [es:di + 10], al
    mov byte [es:di + 11], al
    add di, 320

    ; ----- ROWS 5–7: left + right vertical walls -----
    mov cx, 3
.row_wall2:
    mov byte [es:di], al
    mov byte [es:di + 11], al
    add di, 320
    loop .row_wall2

    ; ----- ROW 8: bottom bar (full width) -----
    mov cx, 12
    rep stosb

    pop cx
    pop di
    pop ax
    ret

draw_char_large_A:
    push ax
    push di
    push cx

    ; compute start offset (y * 320 + x)
    mov ax, bx
    mov dx, 320
    mul dx
    add ax, si
    mov di, ax

    mov al, 12      ; red

    ; -------------------------------------------
    ; Row 0: full bar (######)
    ; -------------------------------------------
    mov cx, 12
    rep stosb
    add di, 308

    ; -------------------------------------------
    ; Rows 1–3: left and right vertical bars
    ; -------------------------------------------
    mov cx, 3
.rowA_top:
    mov byte [es:di], al          ; left bar
    mov byte [es:di+11], al       ; right bar
    add di, 320
    loop .rowA_top

    ; -------------------------------------------
    ; Row 4: center bar
    ; -------------------------------------------
    mov cx, 12
    rep stosb
    add di, 308

    ; -------------------------------------------
    ; Rows 5–9: vertical bars again
    ; -------------------------------------------
    mov cx, 5
.rowA_bottom:
    mov byte [es:di], al
    mov byte [es:di+11], al
    add di, 320
    loop .rowA_bottom

    pop cx
    pop di
    pop ax
    ret
draw_char_large_M:
    push ax
    push di
    push cx

    ; compute start offset
    mov ax, bx        ; y
    mov dx, 320
    mul dx
    add ax, si        ; + x
    mov di, ax

    mov al, 12        ; red color

    ; -------------------------------------------
    ; Row 0: #        #
    ; -------------------------------------------
    mov byte [es:di], al
    mov byte [es:di+11], al
    add di, 320

    ; -------------------------------------------
    ; Row 1: ##      ##
    ; -------------------------------------------
    mov byte [es:di], al
    mov byte [es:di+1], al
    mov byte [es:di+10], al
    mov byte [es:di+11], al
    add di, 320

    ; -------------------------------------------
    ; Row 2: # #    # #
    ; -------------------------------------------
    mov byte [es:di], al
    mov byte [es:di+2], al
    mov byte [es:di+9], al
    mov byte [es:di+11], al
    add di, 320

    ; -------------------------------------------
    ; Row 3: #  #  #  #
    ; -------------------------------------------
    mov byte [es:di], al
    mov byte [es:di+3], al
    mov byte [es:di+8], al
    mov byte [es:di+11], al
    add di, 320

    ; -------------------------------------------
    ; Row 4: #   ##   #
    ; -------------------------------------------
    mov byte [es:di], al
    mov byte [es:di+4], al
    mov byte [es:di+5], al
    mov byte [es:di+6], al
    mov byte [es:di+11], al
    add di, 320

    ; -------------------------------------------
    ; Row 5: #        #
    ; -------------------------------------------
    mov byte [es:di], al
    mov byte [es:di+11], al
    add di, 320

    ; -------------------------------------------
    ; Row 6: #        #
    ; -------------------------------------------
    mov byte [es:di], al
    mov byte [es:di+11], al
    add di, 320

    ; -------------------------------------------
    ; Row 7: #        #
    ; -------------------------------------------
    mov byte [es:di], al
    mov byte [es:di+11], al
    add di, 320

    ; -------------------------------------------
    ; Row 8: #        #
    ; -------------------------------------------
    mov byte [es:di], al
    mov byte [es:di+11], al
    add di, 320

    ; -------------------------------------------
    ; Row 9: #        #
    ; -------------------------------------------
    mov byte [es:di], al
    mov byte [es:di+11], al

    pop cx
    pop di
    pop ax
    ret


draw_char_large_E:
    push ax
    push di
    push cx
    mov ax, bx
    mov di, 320
    mul di
    add ax, si
    mov di, ax
    mov al, 12
    mov cx, 12
    rep stosb
    add di, 308
    mov cx, 4
.loop1_E:
    mov byte [es:di], al
    add di, 320
    loop .loop1_E
    mov cx, 12
    rep stosb
    add di, 308
    mov cx, 4
.loop2_E:
    mov byte [es:di], al
    add di, 320
    loop .loop2_E
    mov cx, 12
    rep stosb
    pop cx
    pop di
    pop ax
    ret

draw_char_large_O:
    push ax
    push di
    push cx
    mov ax, bx
    mov di, 320
    mul di
    add ax, si
    mov di, ax
    mov al, 12
    mov cx, 12
    rep stosb
    add di, 308
    mov cx, 8
.loop1_O:
    push cx
    mov byte [es:di], al
    mov byte [es:di+11], al
    add di, 320
    pop cx
    loop .loop1_O
    mov cx, 12
    rep stosb
    pop cx
    pop di
    pop ax
    ret

draw_char_large_V:
    push ax
    push di
    push cx
    mov ax, bx
    mov di, 320
    mul di
    add ax, si
    mov di, ax
    mov al, 12
    mov cx, 8
.loop1_V:
    push cx
    mov byte [es:di], al
    mov byte [es:di+11], al
    add di, 320
    pop cx
    loop .loop1_V
    mov byte [es:di+1], al
    mov byte [es:di+10], al
    add di, 320
    mov byte [es:di+5], al
    pop cx
    pop di
    pop ax
    ret

draw_char_large_R:
    push ax
    push di
    push cx
    mov ax, bx
    mov di, 320
    mul di
    add ax, si
    mov di, ax
    mov al, 12
    mov cx, 12
    rep stosb
    add di, 308
    mov cx, 4
.loop1_R:
    push cx
    mov byte [es:di], al
    mov byte [es:di+11], al
    add di, 320
    pop cx
    loop .loop1_R
    mov cx, 12
    rep stosb
    add di, 308
    mov cx, 4
.loop2_R:
    push cx
    mov byte [es:di], al
    mov byte [es:di+11], al
    add di, 320
    pop cx
    loop .loop2_R
    pop cx
    pop di
    pop ax
    ret
; ============================================
; wait_for_key
; ============================================
wait_for_key:
    mov ah, 0x00
    int 0x16
    ret
