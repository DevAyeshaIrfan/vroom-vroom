[org 0x0100]

jmp start

; ============================================
; DATA SECTION
; ============================================

player_x:      dw 122        ; Left lane (between left edge and center)
player_y:      dw 155
obstacle_x:    dw 172        ; Right lane (between center and right edge)
obstacle_y:    dw 40
seed:          dw 0

address_text:  db 'HIGHWAY 66 - LAHORE', 0
speed_text:    db '60', 0

; ============================================
; MAIN PROGRAM
; ============================================
start:
    ; Set video mode 13h (320x200, 256 colors)
    mov ax, 0x0013
    int 0x10
    
    ; Set ES to video memory
    mov ax, 0xA000
    mov es, ax
    
    ; Initialize random
    call init_random
    call random_obstacle_position
    
    ; Draw everything in order
    call fill_background
    call fill_grass
    call fill_road
    call draw_curbs
    call draw_road_markings
    call draw_all_trees
    call draw_guardrails
    call draw_player_car
    call draw_obstacle_car
    call draw_headboard
    
    ; Wait for keypress
    xor ah, ah
    int 0x16
    
    ; Back to text mode
    mov ax, 0x0003
    int 0x10
    
    ; Exit
    mov ax, 0x4c00
    int 0x21

; ============================================
init_random:
    push ax
    push dx
    mov ah, 0x00
    int 0x1A
    mov [seed], dx
    pop dx
    pop ax
    ret

; ============================================
random_obstacle_position:
    push ax
    push bx
    push dx
    
    mov ax, [seed]
    mov bx, 25173
    mul bx
    add ax, 13849
    mov [seed], ax
    
    xor dx, dx
    mov bx, 2         ; 0 or 1 for two lanes
    div bx
    
    ; DX now contains 0 or 1
    cmp dx, 0
    je .left_lane
    
    ; Right lane
    mov word [obstacle_x], 172
    jmp .done
    
.left_lane:
    mov word [obstacle_x], 122
    
.done:
    pop dx
    pop bx
    pop ax
    ret

; ============================================
; FILL BACKGROUND - Simple gray/blue gradient
; ============================================
fill_background:
    pusha
    
    mov bx, 0         ; Start row
    
.row_loop:
    cmp bx, 200
    jge .done
    
    ; Calculate row offset
    mov ax, bx
    mov dx, 320
    mul dx
    mov di, ax
    
    ; Choose color based on row
    cmp bx, 40
    jl .dark_blue
    
    ; Light blue for lower portion
    mov al, 11
    jmp .fill_row
    
.dark_blue:
    mov al, 9         ; Darker blue for top
    
.fill_row:
    mov cx, 320
    rep stosb
    
    inc bx
    jmp .row_loop
    
.done:
    popa
    ret

; ============================================
; DRAW HEADBOARD - Highway sign and speed limit
; ============================================
draw_headboard:
    pusha
    
    ; Draw main highway sign (green background)
    mov bx, 5         ; Y position
    mov cx, 20        ; Height
    
.sign_bg:
    push cx
    
    mov ax, bx
    mov dx, 320
    mul dx
    add ax, 60        ; X position (left side)
    mov di, ax
    
    mov al, 2         ; Green
    mov cx, 140       ; Width
    rep stosb
    
    inc bx
    pop cx
    loop .sign_bg
    
    ; Draw white border around sign
    ; Top border
    mov ax, 4
    mov dx, 320
    mul dx
    add ax, 59
    mov di, ax
    mov al, 15
    mov cx, 142
    rep stosb
    
    ; Bottom border
    mov ax, 25
    mov dx, 320
    mul dx
    add ax, 59
    mov di, ax
    mov al, 15
    mov cx, 142
    rep stosb
    
    ; Left border
    mov bx, 5
    mov cx, 20
.left_border:
    push cx
    mov ax, bx
    mov dx, 320
    mul dx
    add ax, 59
    mov di, ax
    mov byte [es:di], 15
    inc bx
    pop cx
    loop .left_border
    
    ; Right border
    mov bx, 5
    mov cx, 20
.right_border:
    push cx
    mov ax, bx
    mov dx, 320
    mul dx
    add ax, 200
    mov di, ax
    mov byte [es:di], 15
    inc bx
    pop cx
    loop .right_border
    
    ; Draw text "HIGHWAY 66 - LAHORE" (simplified with pixels)
    call draw_highway_text
    
    ; Draw speed limit sign (white circle with red border)
    mov bx, 8         ; Y position
    mov cx, 14        ; Radius-like size
    
    ; Draw white background square
    mov bx, 6
    mov cx, 18
.speed_bg:
    push cx
    mov ax, bx
    mov dx, 320
    mul dx
    add ax, 230       ; X position (right side)
    mov di, ax
    
    mov al, 15        ; White
    push cx
    mov cx, 24
    rep stosb
    pop cx
    
    inc bx
    pop cx
    loop .speed_bg
    
    ; Draw red border
    ; Top line
    mov ax, 5
    mov dx, 320
    mul dx
    add ax, 229
    mov di, ax
    mov al, 12
    mov cx, 26
    rep stosb
    
    ; Bottom line
    mov ax, 24
    mov dx, 320
    mul dx
    add ax, 229
    mov di, ax
    mov al, 12
    mov cx, 26
    rep stosb
    
    ; Left and right lines
    mov bx, 6
    mov cx, 18
.speed_border:
    push cx
    mov ax, bx
    mov dx, 320
    mul dx
    add ax, 229
    mov di, ax
    mov byte [es:di], 12
    mov byte [es:di+25], 12
    inc bx
    pop cx
    loop .speed_border
    
    ; Draw "60" in the speed limit sign
    call draw_speed_number
    
    popa
    ret

; ============================================
; DRAW HIGHWAY TEXT (simplified pixel art)
; ============================================
draw_highway_text:
    push ax
    push bx
    push cx
    push di
    
    ; Draw "HIGHWAY 66" in white pixels
    ; Simplified letter patterns at Y=12, starting X=70
    
    ; H
    mov bx, 10
    mov cx, 8
.draw_h:
    push cx
    mov ax, bx
    mov dx, 320
    mul dx
    add ax, 70
    mov di, ax
    mov byte [es:di], 15
    mov byte [es:di+3], 15
    cmp cx, 4
    jne .skip_h_mid
    mov byte [es:di+1], 15
    mov byte [es:di+2], 15
.skip_h_mid:
    inc bx
    pop cx
    loop .draw_h
    
    ; W (simplified)
    mov bx, 10
    mov cx, 8
    mov si, 85
.draw_w:
    push cx
    mov ax, bx
    mov dx, 320
    mul dx
    add ax, si
    mov di, ax
    mov byte [es:di], 15
    mov byte [es:di+4], 15
    cmp cx, 2
    jg .skip_w_mid
    mov byte [es:di+1], 15
    mov byte [es:di+3], 15
.skip_w_mid:
    inc bx
    pop cx
    loop .draw_w
    
    ; Y
    mov bx, 10
    mov cx, 8
    mov si, 100
.draw_y:
    push cx
    mov ax, bx
    mov dx, 320
    mul dx
    add ax, si
    mov di, ax
    cmp cx, 5
    jl .y_bottom
    mov byte [es:di], 15
    mov byte [es:di+3], 15
    jmp .y_done
.y_bottom:
    mov byte [es:di+1], 15
.y_done:
    inc bx
    pop cx
    loop .draw_y
    
    ; 6
    mov bx, 10
    mov cx, 8
    mov si, 120
.draw_6_1:
    push cx
    mov ax, bx
    mov dx, 320
    mul dx
    add ax, si
    mov di, ax
    mov byte [es:di], 15
    cmp cx, 8
    je .skip_6_1
    cmp cx, 4
    jg .skip_6_1
    mov byte [es:di+2], 15
.skip_6_1:
    cmp cx, 8
    je .six_top
    cmp cx, 1
    je .six_top
    cmp cx, 4
    jne .skip_6_top
.six_top:
    mov byte [es:di+1], 15
.skip_6_top:
    inc bx
    pop cx
    loop .draw_6_1
    
    ; Second 6
    mov bx, 10
    mov cx, 8
    mov si, 130
.draw_6_2:
    push cx
    mov ax, bx
    mov dx, 320
    mul dx
    add ax, si
    mov di, ax
    mov byte [es:di], 15
    cmp cx, 8
    je .skip_6_2
    cmp cx, 4
    jg .skip_6_2
    mov byte [es:di+2], 15
.skip_6_2:
    cmp cx, 8
    je .six_top2
    cmp cx, 1
    je .six_top2
    cmp cx, 4
    jne .skip_6_top2
.six_top2:
    mov byte [es:di+1], 15
.skip_6_top2:
    inc bx
    pop cx
    loop .draw_6_2
    
    ; Draw "LAHORE" text
    mov bx, 10
    mov cx, 8
    mov si, 150
.draw_l:
    push cx
    mov ax, bx
    mov dx, 320
    mul dx
    add ax, si
    mov di, ax
    mov byte [es:di], 15
    cmp cx, 1
    jne .skip_l_bot
    mov byte [es:di+1], 15
    mov byte [es:di+2], 15
.skip_l_bot:
    inc bx
    pop cx
    loop .draw_l
    
    pop di
    pop cx
    pop bx
    pop ax
    ret

; ============================================
; DRAW SPEED NUMBER "60"
; ============================================
draw_speed_number:
    push ax
    push bx
    push cx
    push di
    
    ; Draw "6"
    mov bx, 10
    mov cx, 10
    mov si, 235
.draw_num_6:
    push cx
    mov ax, bx
    mov dx, 320
    mul dx
    add ax, si
    mov di, ax
    
    mov byte [es:di], 0
    cmp cx, 10
    je .skip_n6
    cmp cx, 5
    jg .skip_n6
    mov byte [es:di+4], 0
.skip_n6:
    cmp cx, 10
    je .n6_top
    cmp cx, 1
    je .n6_top
    cmp cx, 5
    jne .skip_n6_top
.n6_top:
    mov byte [es:di+1], 0
    mov byte [es:di+2], 0
    mov byte [es:di+3], 0
.skip_n6_top:
    
    inc bx
    pop cx
    loop .draw_num_6
    
    ; Draw "0"
    mov bx, 10
    mov cx, 10
    mov si, 243
.draw_num_0:
    push cx
    mov ax, bx
    mov dx, 320
    mul dx
    add ax, si
    mov di, ax
    
    mov byte [es:di], 0
    mov byte [es:di+4], 0
    cmp cx, 10
    je .n0_top
    cmp cx, 1
    jne .skip_n0_top
.n0_top:
    mov byte [es:di+1], 0
    mov byte [es:di+2], 0
    mov byte [es:di+3], 0
.skip_n0_top:
    
    inc bx
    pop cx
    loop .draw_num_0
    
    pop di
    pop cx
    pop bx
    pop ax
    ret

; ============================================
; FILL GRASS - Both sides
; ============================================
fill_grass:
    pusha
    
    mov bx, 0         ; Start row
    
.row_loop:
    cmp bx, 200
    jge .done
    
    ; Calculate row offset
    mov ax, bx
    mov dx, 320
    mul dx
    mov di, ax
    
    ; Left grass (0 to 99)
    mov cx, 100
    mov al, 2         ; Green
    rep stosb
    
    ; Skip road (100 to 219)
    add di, 120
    
    ; Right grass (220 to 319)
    mov cx, 100
    mov al, 2
    rep stosb
    
    inc bx
    jmp .row_loop
    
.done:
    popa
    ret

; ============================================
; FILL ROAD - Dark gray
; ============================================
fill_road:
    pusha
    
    mov bx, 0
    
.row_loop:
    cmp bx, 200
    jge .done
    
    mov ax, bx
    mov dx, 320
    mul dx
    add ax, 100       ; Road starts at X=100
    mov di, ax
    
    mov cx, 120       ; Road width
    mov al, 8         ; Dark gray
    rep stosb
    
    inc bx
    jmp .row_loop
    
.done:
    popa
    ret

; ============================================
; DRAW CURBS - White/red painted curbs
; ============================================
draw_curbs:
    pusha
    
    mov bx, 0         ; Start row
    
.row_loop:
    cmp bx, 200
    jge .done
    
    ; Calculate row offset
    mov ax, bx
    mov dx, 320
    mul dx
    mov si, ax
    
    ; Left curb (alternating red/white pattern)
    mov di, si
    add di, 98        ; Position at road edge
    
    ; Determine color based on Y position
    mov ax, bx
    and ax, 16        ; Pattern every 16 pixels
    cmp ax, 0
    je .left_red
    
    mov byte [es:di], 15    ; White
    mov byte [es:di+1], 15
    jmp .right_curb
    
.left_red:
    mov byte [es:di], 12    ; Red
    mov byte [es:di+1], 12
    
.right_curb:
    ; Right curb
    mov di, si
    add di, 220       ; Position at road edge
    
    mov ax, bx
    and ax, 16
    cmp ax, 0
    je .right_red
    
    mov byte [es:di], 15
    mov byte [es:di+1], 15
    jmp .next_row
    
.right_red:
    mov byte [es:di], 12
    mov byte [es:di+1], 12
    
.next_row:
    inc bx
    jmp .row_loop
    
.done:
    popa
    ret

; ============================================
draw_road_markings:
    pusha
    
    mov bx, 0
    
.row_loop:
    cmp bx, 200
    jge .done
    
    ; Calculate row offset
    mov ax, bx
    mov dx, 320
    mul dx
    mov si, ax
    
    ; Check if we should draw dash (every 20 pixels, draw 10)
    mov ax, bx
    mov dx, 0
    mov cx, 20
    div cx            ; DX = remainder
    cmp dx, 10
    jge .skip_marks
    
    ; Center line (white, bold)
    mov di, si
    add di, 158       ; Center of road
    mov byte [es:di], 15
    mov byte [es:di+1], 15
    mov byte [es:di+2], 15
    
    ; Left lane marker
    mov di, si
    add di, 130
    mov byte [es:di], 7
    
    ; Right lane marker  
    mov di, si
    add di, 188
    mov byte [es:di], 7
    
.skip_marks:
    inc bx
    jmp .row_loop
    
.done:
    popa
    ret

; ============================================
; DRAW ALL TREES
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
; DRAW GUARDRAILS
; ============================================
draw_guardrails:
    pusha
    
    ; Left guardrail (series of posts)
    mov si, 0         ; Counter for posts
    
.left_rail_loop:
    cmp si, 5
    jge .right_rail_start
    
    ; Calculate Y position
    mov ax, si
    mov bx, 35
    mul bx
    add ax, 30
    mov bx, ax        ; Y position
    
    ; Draw post
    mov cx, 8
    
.left_post_draw:
    push cx
    
    mov ax, bx
    mov dx, 320
    mul dx
    add ax, 92        ; X position (just before road)
    mov di, ax
    
    mov byte [es:di], 7     ; Gray
    mov byte [es:di+1], 7
    mov byte [es:di+2], 7
    
    inc bx
    pop cx
    loop .left_post_draw
    
    inc si
    jmp .left_rail_loop
    
.right_rail_start:
    ; Right guardrail
    mov si, 0
    
.right_rail_loop:
    cmp si, 5
    jge .rails_done
    
    ; Calculate Y position
    mov ax, si
    mov bx, 35
    mul bx
    add ax, 30
    mov bx, ax
    
    ; Draw post
    mov cx, 8
    
.right_post_draw:
    push cx
    
    mov ax, bx
    mov dx, 320
    mul dx
    add ax, 225       ; X position (just after road)
    mov di, ax
    
    mov byte [es:di], 7
    mov byte [es:di+1], 7
    mov byte [es:di+2], 7
    
    inc bx
    pop cx
    loop .right_post_draw
    
    inc si
    jmp .right_rail_loop
    
.rails_done:
    popa
    ret

; ============================================
; DRAW PLAYER CAR (RED)
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
; DRAW OBSTACLE CAR (BLUE)
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