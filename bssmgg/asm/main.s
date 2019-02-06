
.include "sys/sms_arch.s"
  ;.include "base/ram.s"
;.include "base/macros.s"
  ;.include "res/defines.s"

.rombankmap
  bankstotal 64
  banksize $4000
  banks 64
.endro

.emptyfill $FF

.background "bssmgg.gg"

.unbackground $80000 $FFFFF

; free unused space
.unbackground $7F00 $7FEF

.define oldPrintBaseX $C077
.define oldPrintBaseY $C078
.define oldPrintAreaW $C079
.define oldPrintAreaH $C07A
.define oldPrintNametableBase $C07B
.define oldPrintSrcPtr $C07D
.define oldPrintOffsetX $C080
.define oldPrintOffsetY $C081
.define oldPrintSpeed $C07F
.define oldPrintNextCharTimer $C082

.define waitIndicatorFgTile $090F

.define loadSizedTilemap $06A4
.define playVoice $5245

.include "vwf_consts.inc"
.include "ram.inc"
.include "util.s"
.include "vwf.s"
.include "vwf_user.s"

.macro orig_read16BitTable
  rst $20
.endm

; B = tile count
; DE = srcptr
; HL = dstcmd
.macro rawTilesToVdp_macro
  ; set vdp dst
  ld c,vdpCtrlPort
  out (c),l
  out (c),h
  ; write data to data port
  ex de,hl
  dec c
  ld a,b
  -:
    .rept bytesPerTile
      outi
    .endr
    dec a
    jr nz,-
.endm

; BC = tile count
; DE = srcptr
; HL = dstcmd
.macro rawTilesToVdp_big_macro
  push bc
    ; set vdp dst
    ld c,vdpCtrlPort
    out (c),l
    out (c),h
  pop bc
  ; write data to data port
  ex de,hl
  -:
    push bc
      ld c,vdpDataPort
      .rept bytesPerTile
        outi
      .endr
    pop bc
    
    dec bc
    ld a,b
    or c
    jr nz,-
.endm

;===============================================
; Update header after building
;===============================================
.smstag

;========================================
; use vwf and new strings where needed
;========================================

;========================================
; main strategy mode
;========================================
  
; base tile at which vwf tiles are initially allocated
.define vwfTileBase_main $0110
; one past the last index of assignable vwf tiles
.define vwfTileSize_main $0182-vwfTileBase_main
; if nonzero, assume nametable scroll is zero regardless of actual value
.define vwfScrollZeroFlag_main $00
; high byte for nametable prints
.define vwfNametableHighMask_main $09
  
.define vwfTileBase_minigameExplanation $0110+$28
.define vwfTileSize_minigameExplanation $0182-vwfTileBase_minigameExplanation
.define vwfScrollZeroFlag_minigameExplanation $00
.define vwfNametableHighMask_minigameExplanation $09

.define vwfTileBase_findTuxedoMask $0110
.define vwfTileSize_findTuxedoMask $0140-vwfTileBase_main
.define vwfScrollZeroFlag_findTuxedoMask $00
.define vwfNametableHighMask_findTuxedoMask $09

/*.bank $01 slot 1
.org $23D3
.section "set up vwf main game 1" overwrite
  doMakeBankedCall setUpVwf_main
.ends

.bank $01 slot 1
.section "set up vwf main game 2" superfree APPENDTO "vwf and friends"
  setUpVwf_main:
    ; make up work
    call $0432
    
    ld a,vwfTileSize_main
    ld b,vwfScrollZeroFlag_main
    ld c,vwfNametableHighMask_main
    ld hl,vwfTileBase_main
    jp setUpVwfTileAlloc
.ends */

;========================================
; script
;========================================

.include "out/script/string_bucket_hashtablemain.inc"

;========================================
; new string print init
;========================================

.bank $01 slot 1
.org $0F85
.section "new string print init pre" overwrite
  ; do not round box height down to multiple of 2
  call stringPreInit2
  jp $4F8D
.ends

.bank $01 slot 1
.section "new string print init pre 2" free
  stringPreInit2:
    ; divide print speed by 2 unless it's already 1
    ld a,(oldPrintSpeed)
    cp $01
    jr z,+
      sra a
      ld (oldPrintSpeed),a
    +:
    ret
.ends

.bank $01 slot 1
.org $0F9E
.section "new string print init" SIZE $11 overwrite
  newStringPrintInit:
    ; try to remap whatever initial string pointer (C07D) is
    ; (may be dummy value?)
    ld hl,(oldPrintSrcPtr)
    call getStringHash
    
    ; at this point, specs have already been written to C077-C07F
    jp newStringPrintInit_finish
.ends

.bank $01 slot 1
.section "new string print init 1c" free
  newStringPrintInit_noHash:
    ; at this point, specs have already been written to C077-C07F
    jp newStringPrintInit_finish
.ends

.bank $01 slot 1
.section "new string print init 1b" free
  newStringPrintInit_finish:
    ; at this point, specs have already been written to C077-C07F
    doBankedCall newStringPrintInit_ext
    ret
.ends

.slot 2
.section "new string print init 2" superfree
  ; C = string bank
  ; HL = string pointer
  newStringPrintInit_ext:
    ; if banknum == not found, assume that the game did not have the bank
    ; for the string loaded at the time it initialized the print.
    ; place sentinel and hope the print update check will find the right
    ; one.
    ld a,c
    cp noBankIdentifier
    jr nz,+
      ld a,newStringSentinel
      ld hl,(oldPrintSrcPtr)
    +:
    ld (curPrintSrcBank),a
    ld (oldPrintSrcPtr),hl
  newStringPrintInit_ext_manual:
    ld a,(oldPrintAreaW)
    ld b,a
    ld a,(oldPrintAreaH)
    ld c,a
    ld a,(oldPrintBaseX)
    ld d,a
    ld a,(oldPrintBaseY)
    ld e,a
    doBankedCall initVwfString
    
    ; look up the tile that we may cover with the wait indicator
    ld hl,(printBaseXY)
    ; target the lower-right corner of the text area, but with
    ; x - 1
    ld bc,(printAreaWH)
    dec b
    add hl,bc
    ; read target tile
    doBankedCall readLocalTileFromNametable
    ld (waitIndicatorBgTile),de
    
    ; remember last print srcptr
;    ld hl,(oldPrintSrcPtr)
;    ld (lastPrintSrcPtr),hl
    
    ret
.ends

;========================================
; new string print update
;========================================

;.unbackground $5001 $5010
.unbackground $4FF8 $500E

.bank $01 slot 1
.org $0FBA
;.section "new string print update" SIZE $55 overwrite
.section "new string print update" SIZE $3E overwrite
  newStringPrintUpdate:
/*    ; if current srcptr or srcbank has changed from last, new string has
    ; begun and srcptr must be remapped
    ; (can't do this. bank changes are not flagged by existing logic, and
    ; what if new pointer just happened to be the same as our last one but
    ; in a different bank?)
    
    ld hl,(oldPrintSrcPtr)
    ld de,(lastPrintSrcPtr)
    or a
    sbc hl,de
    jr nz,@stringChanged
    
    ld a,(lastPrintSrcBank)
    ld hl,curPrintSrcBank
    cp (hl)
    jr z,@stringNotChanged
  
    @stringChanged:
    
    @stringNotChanged: */
  
    doBankedCallNoParams newStringPrintUpdate_waitMarkerUpdate
    
    ; if string has changed (current bank == sentinel value), do hash
    ; on new string's address before printing
    ld a,(curPrintSrcBank)
    cp newStringSentinel
    jr nz,+
      @newHash:
;      doBankedCallNoParams newStringPrintInit_ext_manual
      call newStringPrintInit
;      ld hl,(oldPrintSrcPtr)
;      call getStringHash
;      ld (oldPrintSrcPtr),hl
;      ld a,c
;      ld (curPrintSrcBank),a
    +:
    
    ; done if text printing disabled
    ld a,($C084)
    or a
    ret nz
    
    ; tick countdown timer for next character print
    ld a,($C082)
    dec a
    ld ($C082),a
    ; done if nonzero
    ret nz
    
    doBankedCall newStringPrintUpdate_charPrintUpdate
    ret
    
    newStringPrintUpdate_charPrintFetch:
/*      ; fetch next character
      ld a,(mapperSlot2Ctrl)
      push af
        ; src bank values >= 0x80 are interpreted as "no change"
        ld a,(curPrintSrcBank)
        or a
        jp m,++
          ld (mapperSlot2Ctrl),a
        ++:
        
        ld hl,(oldPrintSrcPtr)
        ld a,(hl)
        ld c,a
      pop af
      ld (mapperSlot2Ctrl),a
      ld a,c */
      
      ld a,(curPrintSrcBank)
      ld b,a
      ld hl,(oldPrintSrcPtr)
      or a
      jp p,++
        ; src bank values >= 0x80 are interpreted as "no change"
        ld a,(hl)
        ret
      ++:
      jp bankedFetch
.ends

.slot 2
.section "new string print update 2" superfree
  newStringPrintUpdate_charPrintUpdate:
    ; reset print timer
    ld a,($C07F)
    ld ($C082),a
    
    ; loop counter for possible multiple-characters-per-frame printing
    ld b,$02
    @printLoop:
      push bc
      
        ; fetch next char
        call newStringPrintUpdate_charPrintFetch
        
        ; done if zero (terminator)
        or a
        jr nz,++
          pop bc
          ret
        ++:

        ; advance getpos
        @notTerminator:
        inc hl
        ld (oldPrintSrcPtr),hl
        
        call newCharPrint
      
      ; if print speed is 1 (nominally 1 character per second),
      ; print 2 characters per frame, because we have twice as much
      ; text and this annoys me
      pop bc
      ld a,(oldPrintSpeed)
      cp $01
      jr nz,+
        djnz @printLoop
    +:
    
    ret
.ends

; freed space from opcode handlers
;.unbackground $5012 $504B
;.unbackground $5078 $5165
.unbackground $5012 $5165

.bank $01 slot 1
.org $100F
.section "new string print update 3a" overwrite
  jp newCharPrint
.ends

.bank $01 slot 1
;.org $100F
.section "new string print update 3b" free
  ;=================================
  ; print a character
  ;
  ; A = character ID
  ;=================================
  newCharPrint:
    ; save character ID to C083
    ld ($C083),a
    
    ; if a wait command
    cp vwfWaitIndex
    jr nz,+
      ld a,$01
      ld ($C084),a
      ld ($C085),a
      ret
    +:
    
    doBankedCall printVwfChar_user
    
    ret
.ends

.slot 2
.section "new string print update 4" superfree
  ; removed to free space
  newStringPrintUpdate_waitMarkerUpdate:
    ; check if wait marker showing flag set
    ld a,($C085)
    or a
    jr z,@waitMarkerDone
      ; if C084 zero, then we've resumed printing after stopping
      ; and need to clear the wait marker
      ld a,($C084)
      or a
      jr nz,+
        ; zero timer and "wait marker showing" flag
        ld ($C086),a
        ld ($C085),a
      +:
/*      ; (print area W - 2) == x-offset
      ; y-offset does not change
      ld a,($C079)
      sub $02
      ld ($C080),a
      ; update and check state counter
      ld a,($C086)
      inc a
      ld ($C086),a
      and $10
      srl a
      srl a
      srl a
      srl a */
      ; get local XY of target tile
      ld hl,(printBaseXY)
      ; target the lower-right corner of the text area, but with
      ; x - 1
      ld bc,(printAreaWH)
      dec b
      add hl,bc
      
      ; update state counter
      ld a,($C086)
      inc a
      ld ($C086),a
      and $10
      srl a
      srl a
      srl a
      srl a
      
      ; check marker state
      or a
      jr nz,+
        ; zero: show bg
        ld de,(waitIndicatorBgTile)
        jr ++
      +:
        ; nonzero: show fg
        ld de,waitIndicatorFgTile
      ++:
      
      ; send char to nametable
      doBankedCall writeLocalTileToNametable
      
/*      ; print character from table at 5241 (0001/000F)
      ld hl,$5241
      orig_read16BitTable
      ld a,l
;      call $500F */

      ; clear printing x-offset
;      ld a,$00
;      ld ($C080),a
    @waitMarkerDone:
    ret
  
.ends

;========================================
; string hash lookup
;========================================

.slot 1
.section "string hash lookup" free

  ;========================================
  ; string hash lookup
  ; 
  ; HL = pointer to orig string (in
  ;      appropriate slot)
  ;
  ; returns:
  ;   C = new bank (or fail code)
  ;   HL = new pointer
  ;========================================
  getStringHash:
    call getPointerBank
    doBankedCall getStringHash_ext
    ret
  
.ends

.slot 2
.section "string hash lookup 2" superfree
  ;========================================
  ; string hash lookup
  ; 
  ; A = C = pointer to orig bank
  ; HL = pointer to orig string (in
  ;      appropriate slot)
  ;
  ; returns:
  ;   C = new bank (or fail code)
  ;   HL = new pointer
  ;========================================
  getStringHash_ext:
    ; if RAM identifier, no change needed
    cp ramBankIdentifier
    jr z,@done
    
      ; look up hash
      ld b,:bucketArrayHashTablemain
      doBankedCall lookUpHashedPointer
    
    @done:
    ret
.ends

;========================================
; minigame menu
;========================================

  ;=====
  ; set up vwf
  ;=====

  .bank $01 slot 1
  .org $183D
  .section "vwf setup minigame menu 1" overwrite
    doBankedCallNoParams setUpVwf_minigameMenu
  .ends

  .slot 2
  .section "vwf setup minigame menu 2" superfree
    setUpVwf_minigameMenu:
      ld a,vwfTileSize_minigameExplanation
      ld b,vwfScrollZeroFlag_minigameExplanation
      ld c,vwfNametableHighMask_minigameExplanation
      ld hl,vwfTileBase_minigameExplanation
      doBankedCall setUpVwfTileAlloc
      
      ; make up work
      ld ix,$C400
      ld (ix+$00),$00
      ret
  .ends

  ;=====
  ; load new minigame label graphic
  ;=====

  .bank $01 slot 1
  .org $182C
  .section "label minigame menu 1" overwrite
    call loadNewMinigameMenuLabel
  .ends

  .bank $01 slot 1
  .section "label minigame menu 2" free
    loadNewMinigameMenuLabel:
      ; make up work
      call $063E
      
      ; load new label graphic
      ld hl,minigameMenuLabel
      doBankedCall loadMinigameExplanationLabelGrp
      ret
  .ends

  ;=====
  ; mark string reset
  ;=====
  
  .bank 1 slot 1
  .org $18D2
  .section "minigame menu 1" SIZE $11 overwrite
    minigameMenuNewString:
      ; make up work
      ld (ix+$01),a
      ld hl,$9CAC
      rst $20
      ld ($C07D),hl
      jp minigameMenuNewString_ext2
  .ends
  
  .slot 2
  .section "minigame menu 2" superfree
    minigameMenuNewString_ext:
      ; make up work
      ld a,$01
      ld ($C082),a
      
      ; mark new string
      ld a,newStringSentinel
      ld (curPrintSrcBank),a
      
      ret
  .ends
  
  .bank 1 slot 1
  .section "minigame menu 3" free
    minigameMenuNewString_ext2:
      doBankedCallNoParams minigameMenuNewString_ext
      ret
  .ends
  
  .bank 1 slot 1
  .org $18AD
  .section "minigame menu 4" overwrite
    ; what in god's fucking name happened here
    jp $58D2
  .ends

;========================================
; minigame explanations
;========================================

  ;=====
  ; set up vwf
  ;=====

  .bank $01 slot 1
  .org $2611
  .section "vwf setup minigame explanation 1" overwrite
    doBankedCallNoParams setUpVwf_minigameExplanation
  .ends

  .slot 2
  .section "vwf setup minigame explanation 2" superfree
    setUpVwf_minigameExplanation:
      ld a,vwfTileSize_minigameExplanation
      ld b,vwfScrollZeroFlag_minigameExplanation
      ld c,vwfNametableHighMask_minigameExplanation
      ld hl,vwfTileBase_minigameExplanation
      doBankedCall setUpVwfTileAlloc
      
      ; make up work
      ld a,($C231)
      ld b,a
      add a,a
      add a,a
      add a,b
      ld b,a
      ret
  .ends

  ;=====
  ; use new labels
  ;=====

  .bank $01 slot 1
  .org $2670
  .section "vwf setup minigame explanation label 1" overwrite
    call setUpMinigameExplanationLabels
  .ends

  .bank $01 slot 1
  .section "vwf setup minigame explanation label 2" free
    setUpMinigameExplanationLabels:
      ; make up work
      call $063E
      
      doBankedCallNoParams setUpMinigameExplanationLabels_ext
      ret
  .ends

  .slot 2
  .section "vwf setup minigame explanation label 3" superfree
    
    intro_lunap_usa: .incbin "out/grp/intro_lunap_usa.bin"
    intro_lunap_chibiusa: .incbin "out/grp/intro_lunap_chibiusa.bin"
    intro_findtuxedo_usa: .incbin "out/grp/intro_findtuxedo_usa.bin"
    intro_findtuxedo_chibiusa: .incbin "out/grp/intro_findtuxedo_chibiusa.bin"
    intro_roulette_usa: .incbin "out/grp/intro_roulette_usa.bin"
    intro_roulette_chibiusa: .incbin "out/grp/intro_roulette_chibiusa.bin"
    intro_quiz_usa: .incbin "out/grp/intro_quiz_usa.bin"
    intro_quiz_chibiusa: .incbin "out/grp/intro_quiz_chibiusa.bin"
    intro_fortune_usa: .incbin "out/grp/intro_fortune.bin"
    intro_fortune_chibiusa: .incbin "out/grp/intro_fortune.bin"
    
    minigameMenuLabel: .incbin "out/grp/minigame_menu.bin"
    
    minigameExplanationLabelTable:
      .dw intro_lunap_usa
      .dw intro_lunap_chibiusa
      .dw intro_findtuxedo_usa
      .dw intro_findtuxedo_chibiusa
      .dw intro_roulette_usa
      .dw intro_roulette_chibiusa
      .dw intro_quiz_usa
      .dw intro_quiz_chibiusa
      .dw intro_fortune_usa
      .dw intro_fortune_chibiusa
    
    minigameLabelTilemap:
      ; dimensions
      .db $14,$02
      .rept $28 INDEX count
        .dw $0110+count
      .endr
  
    setUpMinigameExplanationLabels_ext:
      ; get player ID
      ld a,($C231)
      ld e,a
      
      ; get minigame ID
      ld a,($C22A)
      ; multiply by 2 for base offset
      add a,a
      ; add player ID (1 for chibiusa)
      add a,e
      
      ; index into table
      ld hl,minigameExplanationLabelTable
      read16BitTable_macro

      jp loadMinigameExplanationLabelGrp
  
    ; HL = graphic pointer
    loadMinigameExplanationLabelGrp:
      ; load new graphics
      ld b,$28
      ex de,hl
      ; target tile $110
      ld hl,$6200
      rawTilesToVdp_macro
      
      ; update tilemap
      ld hl,minigameLabelTilemap
      ld de,$010C
      jp loadSizedTilemap
  .ends

  ;=====
  ; handle RAM copy and stuff
  ;=====

  .bank 1 slot 1
  .org $26A6
  .section "minigame explanations 1" overwrite
    ; for "it's the bonus game" text
    call copyHashedStringToRam
    jp $66AF
  .ends

  .bank 1 slot 1
  .org $26C1
  .section "minigame explanations 2" overwrite
    ; for actual explanation text
    call copyHashedStringToRam
    ; add terminator
    xor a
    ld (de),a
    nop
    nop
;    jp $66C8
  .ends

  .bank 1 slot 1
  .section "string RAM copy" free
    ; DE = dst
    ; HL = orig pointer
    copyHashedStringToRam:
      ; get hash
      push de
        call getStringHash
      pop de
      
      ld a,(mapperSlot2Ctrl)
      push af
        ld a,c
        ld (mapperSlot2Ctrl),a
        
        ; copy
        -:
          ld a,(hl)
          ld (de),a
          or a
          jr z,@done
            inc hl
            inc de
            jr -
      
      @done:
      pop af
      ld (mapperSlot2Ctrl),a
      ret
  .ends

;========================================
; find tuxedo mask
;========================================

  ;=====
  ; set up vwf
  ;=====

/*  .bank $01 slot 1
  .org $0751
  .section "vwf setup find tuxedo mask 1" overwrite
    doBankedCall setUpVwf_findTuxedoMask
    nop
    nop
  .ends

  .slot 2
  .section "vwf setup find tuxedo mask 2" superfree
    setUpVwf_findTuxedoMask:
      ; make up work
      ld ($C022),de
      ld ($C02A),de
      ld ($C026),de
      ld ($C06A),de
      
      ld a,vwfTileSize_findTuxedoMask
      ld b,vwfScrollZeroFlag_findTuxedoMask
      ld c,vwfNametableHighMask_findTuxedoMask
      ld hl,vwfTileBase_findTuxedoMask
      doBankedCall setUpVwfTileAlloc
      
      ret
  .ends */

  .bank $01 slot 1
  .org $2FC7
  .section "vwf setup find tuxedo mask 1" overwrite
    doBankedCallNoParams setUpVwf_findTuxedoMask
  .ends

  .slot 2
  .section "vwf setup find tuxedo mask 2" superfree
    setUpVwf_findTuxedoMask:
      ld a,vwfTileSize_findTuxedoMask
      ld b,vwfScrollZeroFlag_findTuxedoMask
      ld c,vwfNametableHighMask_findTuxedoMask
      ld hl,vwfTileBase_findTuxedoMask
      doBankedCall setUpVwfTileAlloc
      
      ; make up work
      ld a,$0C
      ld ($C087),a
      ld hl,$0050
      ret
  .ends

  ;=====
  ; set up screen-local base message coordinates instead of quasi-absolute
  ;=====

  .bank $00 slot 0
  .org $34FC
  .section "find tuxedo mask y-coord 1" overwrite
    ld a,$0E
  .ends

  .bank $00 slot 0
  .org $35F9
  .section "find tuxedo mask y-coord 2" overwrite
    ld a,$0E
  .ends

  ;=====
  ; map strings
  ;=====

  .bank $00 slot 0
  .org $351D
  .section "find tuxedo mask hash strings 1" overwrite
    call findTuxedoMask_stringSetup
  .ends

  .bank $01 slot 1
  .section "find tuxedo mask hash strings 2" free
    findTuxedoMask_stringSetup:
      ; make up work
      ld (ix+60),$B4
      
      jp newStringPrintInit
;      call getStringHash
;      ret
  .ends

  ;=====
  ; hash the special hardcoded "you lose" and "you win" messages
  ;=====

  .bank $00 slot 0
  .org $361C
  .section "find tuxedo mask hash strings 3" overwrite
    call findTuxedoMask_winLoseStringSetup
  .ends

  .bank $01 slot 1
  .section "find tuxedo mask hash strings 4" free
    findTuxedoMask_winLoseStringSetup:
      ld ($C07D),hl
      
      ; due to stupidity, we must delay at
      ; least 4 frames before allowing printing to start or visual
      ; corruption will occur. due to our speedup hack, the printing
      ; speed here is now 2 frames per character, so this needs fixing.
      ; forcing the initial timer value to 4 will suffice.
      ld a,$04
      ld (oldPrintNextCharTimer),a
      
      jp newStringPrintInit
  .ends

  ;=====
  ; deallocate text before erasing
  ;=====

  .bank $00 slot 0
  .org $354A
  .section "find tuxedo mask dealloc 1" overwrite
    call findTuxedoMask_dealloc
  .ends

  .bank $01 slot 1
  .section "find tuxedo mask dealloc 2" free
    findTuxedoMask_dealloc:
      push hl
      push de
        doBankedCallNoParams findTuxedoMask_dealloc_ext
      pop de
      pop hl
      
      ; make up work
      jp $51BD
  .ends

  .slot 2
  .section "find tuxedo mask dealloc 3" superfree
    findTuxedoMask_dealloc_ext:
      ; target coordinates
      ld hl,$060E
      ; box size
      ld bc,$0C04
      doBankedCall deallocVwfTileArea
      ret
  .ends

;========================================
; quiz world
;========================================

/*  .bank $01 slot 1
  .org $3445
  .section "quiz world setup 1" overwrite
    call quizWorldSetup1
  .ends

  .bank $01 slot 1
  .section "quiz world setup 2" free
    quizWorldSetup1:
      ; THIS IS NOT PRINTED
      ld hl,$77E4
      ld (oldPrintSrcPtr),hl

      ; make up work
      ld a,$91
      jp $52D8
  .ends */

  ;=====
  ; set up vwf
  ;=====

  .bank $01 slot 1
  .org $3472
  .section "vwf setup quiz world 1" overwrite
    call setUpVwf_quizWorld
  .ends

  .bank $01 slot 1
  .section "vwf setup quiz world 2" free
    setUpVwf_quizWorld:
      ; make up work
      call $063E
      
      doBankedCallNoParams setUpVwf_quizWorld_ext
      ret
  .ends

  .slot 2
  .section "vwf setup quiz world 3" superfree
    newQuizWorldBg:
      .incbin "out/grp/quiz_bg.bin" FSIZE newQuizWorldBgSize
      .define numNewQuizWorldBgTiles newQuizWorldBgSize/bytesPerTile
  
    setUpVwf_quizWorld_ext:
      ld a,vwfTileSize_main
      ld b,vwfScrollZeroFlag_main
      ld c,vwfNametableHighMask_main
      ld hl,vwfTileBase_main
      doBankedCall setUpVwfTileAlloc
      
      ; load new graphics
      ld b,numNewQuizWorldBgTiles
      ld de,newQuizWorldBg
      ld hl,$5000
      rawTilesToVdp_macro
      
      ret
  .ends

  ;=====
  ; original game attempts to read from string pointer outside
  ; of normal print logic. handle this correctly
  ;=====

  .bank $01 slot 1
  .org $3489
  .section "quiz world hash strings 1" overwrite
    call quizWorld_stringSetup
    nop
  .ends

  .bank $01 slot 1
  .section "quiz world hash strings 2" free
    quizWorld_stringSetup:
    quizWorld_fetchStringByte:
      ld a,(mapperSlot2Ctrl)
      push af
        ld a,(curPrintSrcBank)
        ld (mapperSlot2Ctrl),a
        ld hl,($C07D)
        ld l,(hl)
      pop af
      ld (mapperSlot2Ctrl),a
      
      ld a,l
      ret
  .ends

  ;=====
  ; hash question pointers
  ;=====

  .bank $01 slot 1
  .org $3501
  .section "quiz world hash data pointers 3" overwrite
    call quizWorld_dataPointerHash
  .ends

  .bank $01 slot 1
  .section "quiz world hash data pointers 4" free
    quizWorld_dataPointerHash:
      push hl
        ; question y/x pos
        ld hl,$0403
        ld ($C077),hl
      pop hl
    stringInitFromHL:
      ld ($C07D),hl
      jp newStringPrintInit
  .ends

  ;=====
  ; unfortunately, the original game expects to be able to read back
  ; a table of pointers to answer strings at the location immediately
  ; following the question string.
  ; i've dealt with this by placing a pointer to the original answer
  ; table after every question string in the new script, which we
  ; can use instead.
  ;=====
  
  .define baseAnswerYPos $0A

  ;=====
  ; answer 1
  ;=====

  .bank $01 slot 1
  .org $3557
  .section "quiz world hash data pointers 5" overwrite
    call quizWorld_afterQuestion
    jp $7564
  .ends

  .bank $01 slot 1
  .section "quiz world hash data pointers 6" free
    quizWorld_afterQuestion:
    
      push af
        ; get pointer to answer table (bank 3)
        
        ld a,(mapperSlot2Ctrl)
        push af
          ld a,(curPrintSrcBank)
          ld (mapperSlot2Ctrl),a
          
          ld a,(hl)
          inc hl
          ld h,(hl)
          ld l,a
        pop af
        ld (mapperSlot2Ctrl),a
        
        ; write answer pointer table pointer to C403
        ld ($C403),hl
        
      ; ? answer index?
      pop af
      
      ; look up answer pointer
      orig_read16BitTable
    
      push hl
        ; set base y/x pos
        ld hl,((baseAnswerYPos+0)<<8)|$06
        ld ($C077),hl
      pop hl
      
;      ld ($C07D),hl
;      jp newStringPrintInit
      jp stringInitFromHL
  .ends

  .bank $01 slot 1
  .org $3546
  .section "answer 1: move number label up a line" overwrite
    ld de,$0394-$0040
  .ends 

  ;=====
  ; answer 2
  ;=====

  .bank $01 slot 1
  .org $3571
  .section "answer 2: move number label up a line" overwrite
    ld de,$0414-$0040
  .ends 

  .bank $01 slot 1
  .org $3583
  .section "quiz world hash data pointers 7" overwrite
    ; set base Y-pos
    ld a,baseAnswerYPos+2
    ld ($C078),a
    call stringInitFromHL
  .ends

  ;=====
  ; answer 3
  ;=====

  .bank $01 slot 1
  .org $3598
  .section "answer 3: move number label up a line" overwrite
    ld de,$0494-$0040
  .ends 

  .bank $01 slot 1
  .org $35AB
  .section "quiz world hash data pointers 8" overwrite
    ; set base Y-pos
    ld a,baseAnswerYPos+4
    ld ($C078),a
    call stringInitFromHL
  .ends

  ;=====
  ; cursor
  ;=====

  ; initial position
  .bank $01 slot 1
  .org $35C0
  .section "quiz world: move cursor up a line 1" overwrite
    ld de,$0392-$0040
  .ends

  ; blanking area
  .bank $01 slot 1
  .org $36B6
  .section "quiz world: move cursor up a line 2" overwrite
    ld de,$0392-$0040
  .ends
  
  ; update position table
  .bank $01 slot 1
  .org $381D
  .section "quiz world: move cursor up a line 3" overwrite
    .dw $0392-$0040
    .dw $0412-$0040
    .dw $0492-$0040
  .ends 

  ;=====
  ; reduce height by a line
  ;=====
  
  .bank $01 slot 1
  .org $37E7
  .section "quiz world: reduce box height" overwrite
    .db $0D-1
  .ends

;========================================
; roulette
;========================================

  ;=====
  ; set up vwf
  ;=====
  
  .macro readyRoulettePrintParams
    ; w/h
    ld bc,$0C01
    ; local x/y
    ld de,$0403
  .endm

  .bank $01 slot 1
  .org $30DC
  .section "vwf setup roulette 1" overwrite
    doBankedCallNoParams setUpVwf_roulette
    nop
    nop
  .ends

  .slot 2
  .section "vwf setup roulette 2" superfree
    setUpVwf_roulette:
      ld a,vwfTileSize_main
      ld b,vwfScrollZeroFlag_main
      ld c,vwfNametableHighMask_main
      ld hl,vwfTileBase_main
      doBankedCall setUpVwfTileAlloc
      
      ; print area setup
      readyRoulettePrintParams
      doBankedCall initVwfString
      
      ; make up work
      ld a,$01
      ld ($C00D),a
      ld a,$5F
      ld ($D380),a
      ret
  .ends

  ;=====
  ; box blanking
  ;=====

  .bank $01 slot 1
  .org $336B
  .section "roulette blank 1" overwrite
    doBankedCallNoParams roulette_blankBox
    nop
  .ends

  ;=====
  ; messages
  ;=====

  .slot 2
  .section "roulette messages" superfree
    roulette_perfect: .incbin "out/script/roulette_perfect.bin"
    roulette_right: .incbin "out/script/roulette_right.bin"
    roulette_wrong: .incbin "out/script/roulette_wrong.bin"
    roulette_timeup: .incbin "out/script/roulette_timeup.bin"
    
    roulette_blankBox:
      ld a,vwfBoxClearIndex
      doBankedCall newCharPrint
      ret
    
    roulette_showMsg_right:
      readyRoulettePrintParams
      ld a,:roulette_right
      ld hl,roulette_right
      doBankedCall startVwfString
      ret
    
    roulette_showMsg_wrong:
      readyRoulettePrintParams
      ld a,:roulette_wrong
      ld hl,roulette_wrong
      doBankedCall startVwfString
      ret
    
    roulette_showMsg_perfect:
      readyRoulettePrintParams
      ld a,:roulette_perfect
      ld hl,roulette_perfect
      doBankedCall startVwfString
      ret
    
    roulette_showMsg_timeup:
      readyRoulettePrintParams
      ld a,:roulette_timeup
      ld hl,roulette_timeup
      doBankedCall startVwfString
      ret
  .ends

  .bank $01 slot 1
  .org $334B
  .section "roulette perfect" overwrite
    doBankedCallNoParams roulette_showMsg_perfect
    nop
  .ends

  .bank $01 slot 1
  .org $333C
  .section "roulette right" overwrite
    doBankedCallNoParams roulette_showMsg_right
    nop
  .ends

  .bank $01 slot 1
  .org $335E
  .section "roulette wrong" overwrite
    doBankedCallNoParams roulette_showMsg_wrong
    nop
  .ends

  .bank $01 slot 1
  .org $3375
  .section "roulette time up" overwrite
    doBankedCallNoParams roulette_showMsg_timeup
    nop
  .ends

;========================================
; main menu
;========================================

  ;=====
  ; extra init
  ;=====

  .bank $01 slot 1
  .org $1677
  .section "set up main menu 1" overwrite
    call newMainMenuInit
  .ends

  .bank $01 slot 1
  .section "set up main menu 2" free
    newMainMenuInit:
      ; this starts the main menu music. for some reason, we have to
      ; do this now rather than after the init, or it won't play.
      call $52D8
      
      doBankedCallNoParams newMainMenuInit_ext
      
      ret
  .ends

  .slot 2
  .section "set up main menu 3" superfree
    mainMenuOptionsGrp: .incbin "out/grp/mainmenu_options.bin" FSIZE mainMenuOptionsGrpSize
    .define numMainMenuOptionsGrpTiles mainMenuOptionsGrpSize/bytesPerTile
    mainMenuOptionsTilemap:
      ; dimensions
      .db 11,9
      .incbin "out/maps/mainmenu_options.bin"
    
    mainMenuHelpString: .incbin "out/script/mainmenu_help.bin"
  
    newMainMenuInit_ext:
      ; do vwf init
      ld a,vwfTileSize_main
      ld b,vwfScrollZeroFlag_main
      ld c,vwfNametableHighMask_main
      ld hl,vwfTileBase_main
      doBankedCall setUpVwfTileAlloc
      
      ; load new graphics
      ld b,numMainMenuOptionsGrpTiles
      ld de,mainMenuOptionsGrp
      ; target tile $70
      ld hl,$4E00
      rawTilesToVdp_macro
      
      ; load new tilemap
      ld hl,mainMenuOptionsTilemap
      ld de,$0158 ; nametable dst = 3958 = (12,5)
      call loadSizedTilemap
      
      ; print help string
      ld bc,$0904
      ld de,$020D
      ld a,:mainMenuHelpString
      ld hl,mainMenuHelpString
      doBankedCall startVwfString
      
      ; make up work
      ret
  .ends

  ;=====
  ; patch out unwanted parts of main menu tilemap
  ;=====

  .bank $04 slot 2
  .org $007A
  .section "main menu no border diacritic" overwrite
    .dw $002D
  .ends

  .bank $04 slot 2
  .org $024E+($28*0)
  .section "main menu no initial help message 1" overwrite
    .rept 9
      .dw $003C
    .endr
  .ends

  .bank $04 slot 2
  .org $024E+($28*1)
  .section "main menu no initial help message 2" overwrite
    .rept 9
      .dw $003C
    .endr
  .ends

  .bank $04 slot 2
  .org $024E+($28*2)
  .section "main menu no initial help message 3" overwrite
    .rept 9
      .dw $003C
    .endr
  .ends

  .bank $04 slot 2
  .org $024E+($28*3)
  .section "main menu no initial help message 4" overwrite
    .rept 9
      .dw $003C
    .endr
  .ends

;========================================
; fortune teller
;========================================

  ;=====
  ; extra init
  ;=====

  .bank $01 slot 1
  .org $3852
  .section "set up fortune 1" overwrite
    call newFortuneInit
  .ends

  .bank $01 slot 1
  .section "set up fortune 2" free
    newFortuneInit:
      doBankedCallNoParams newFortuneInit_ext
      
      ; make up work
      ld hl,$AA72
      ret
  .ends

  .slot 2
  .section "set up fortune 3" superfree
    fortuneGrp: .incbin "out/grp/fortune.bin" FSIZE fortuneGrpSize
    .define numFortuneGrpTiles fortuneGrpSize/bytesPerTile
  
    newFortuneInit_ext:
      ; load new graphics
      ld b,numFortuneGrpTiles
      ld de,fortuneGrp
      ; target tile $112
      ld hl,$6240
      rawTilesToVdp_macro
      
      ret
  .ends

  ;=====
  ; new tilemaps
  ;=====

  .bank $1D slot 2
  .org $3BB5
  .section "fortune tilemap 1" overwrite
    .incbin "out/maps/fortune1.bin"
  .ends

  .bank $1C slot 2
  .org $34B4
  .section "fortune tilemap 2" overwrite
    .incbin "out/maps/fortune2.bin"
  .ends

;========================================
; ending
;========================================

  ;=====
  ; new init
  ;=====

/*  .bank $01 slot 1
  .org $3A2A
  .section "ending init 1" overwrite
    doBankedCallNoParams initEnding
  .ends

  .bank $01 slot 1
  .section "ending init 2" free
    initEnding:
      ; make up work
      call $63E
    
      doBankedCallNoParams initEnding_ext
      ret
  .ends */

  .bank $01 slot 1
  .org $39B9
  .section "ending init 1" overwrite
    doBankedCallNoParams initEnding_ext
    nop
  .ends

  .slot 2
  .section "ending init 2" superfree
    initEnding_ext:
      ; make up work
      call $06E2
      call $0950
      call $101E
    
      ; do vwf init
      ld a,vwfTileSize_main
      ld b,vwfScrollZeroFlag_main
      ld c,vwfNametableHighMask_main
      ld hl,vwfTileBase_main
      doBankedCall setUpVwfTileAlloc
      
      ret
  .ends

  ;=====
  ; check for terminator from new string bank
  ;=====

  .bank $01 slot 1
  .org $3A60
  .section "ending 1" overwrite
    call newEndingTerminatorCheck
    jp $7A67
  .ends

  .bank $01 slot 1
  .section "ending 2" free
    newEndingTerminatorCheck:
      ld a,(curPrintSrcBank)
      ld (mapperSlot2Ctrl),a
      ld hl,(oldPrintSrcPtr)
      ld a,(hl)
      ret
  .ends

;========================================
; credits
;========================================

; the original credits are done using a sprite overlay.
; this is limited to 8 sprites per line, which is simply not enough
; for the translation.
; fortunately, we can easily replace the sprite overlays with
; simple background-based text without impacting the presentation at all.
; why did they even use sprites to begin with? my best guess is that
; they were originally going to show the credits on top of the slow pan
; over your character's image, but decided not to for some reason.
; oh well, doesn't matter now

  ;=====
  ; new init
  ;=====

  .bank $01 slot 1
  .org $3B04
  .section "credits init 1" overwrite
    doBankedCallNoParams initCredits
    jp $7B10
  .ends

  .slot 2
  .section "credits init 2" superfree
    initCredits:
      ; do vwf init
      ld a,vwfTileSize_main
      ld b,vwfScrollZeroFlag_main
;      ld c,vwfNametableHighMask_main
      ld c,$09  ; sprite palette
      ld hl,vwfTileBase_main
      doBankedCall setUpVwfTileAlloc
      
      ; font bg is color F, fg is color C
      ; change sprite palette color F to match background
      ld hl,($D300)
      ld ($D33E),hl
      
      ret
  .ends

  ;=====
  ; new strings
  ;=====
    
;    roulette_blankBox:
;      ld a,vwfBoxClearIndex
;      doBankedCall newCharPrint
;      ret

  .define creditsPrintAreaW $0C
  .define creditsPrintAreaH $06
  .define creditsPrintBaseX $04
  .define creditsPrintBaseY $06

  .slot 2
  .section "credits strings" superfree
    creditsStringSizeAndTable: .incbin "out/script/credits.bin"
    ; first byte is count of entries
    
    initAndClearCreditsString:
      ; set up print area
      ; w/h
      ld bc,(creditsPrintAreaW<<8)|creditsPrintAreaH
      ; local x/y
;      ld de,$0406
      ld de,(creditsPrintBaseX<<8)|creditsPrintBaseY
      doBankedCall initVwfString
      
      ; clear existing content
      ld a,vwfBoxClearIndex
      doBankedCall newCharPrint
      
      ; clear nametable print buffer
      ld b,(nametableCompositionBufferEnd-nametableCompositionBuffer)/2
      ld hl,nametableCompositionBuffer
      -:
        ld a,$01
        ld (hl),a
        inc hl
        
        ld a,$09
        ld (hl),a
        inc hl
        
        djnz -
      
      ret
    
    printCreditsString:
      ; A = string index
      push af
        call initAndClearCreditsString
        startLocalPrint nametableCompositionBuffer creditsPrintAreaW creditsPrintAreaH 0 0
      pop af
      
          ; print next string
          ld hl,creditsStringSizeAndTable+1
  ;        read16BitTable_macro
          
          ; read offset table
          push hl
            read16BitTable_macro
          pop de
          add hl,de

        
          
          ld b,:creditsStringSizeAndTable
          doBankedCall printVwfString
        endLocalPrint
      
        ; send nametable
        
        ld bc,(creditsPrintAreaW<<8)|creditsPrintAreaH
        ld hl,(creditsPrintBaseX<<8)|creditsPrintBaseY
        ld de,nametableCompositionBuffer
        doBankedCall writeLocalTilemapToNametable
      
      ret
      
/*      ; return zero if credits done; otherwise, return next index
      inc a
      ld l,a
      ld a,(creditsStringSizeAndTable)
      cp l
      jr z,@done
      
      @notDone:
      ld a,l
      ret
      
      @done:
      xor a
      ret */
    
    ; returns A zero if credits index in A is the last
    checkCreditsDone:
      ; A = next string index
      ld l,a
      ld a,(creditsStringSizeAndTable)
      cp l
      jr z,@done
      
      @notDone:
      ld a,$FF
      ret
      
      @done:
      xor a
      ret
  .ends

  ;=====
  ; print where needed
  ;=====

  .bank $01 slot 1
  .org $0626
  .section "credits state 1 update" SIZE $30 overwrite
    creditsStage1Update:
      ; clear current credits text
      doBankedCallNoParams initAndClearCreditsString
    
      ; get current string index
      ld a,(ix+$3C)
      ; print string
;      doBankedCall printCreditsString
      doBankedCall checkCreditsDone
      ; routine returns A zero if done
      or a
      jr nz,@notDone
      
      @done:
        
    ; go to state 4 = END text
        ld (ix+$12),$04
        ld (ix+$3C),$00
        ld (ix+$3D),$00
        ret 
      
      @notDone:
        ; set next page num
;        ld (ix+$3C),a
        ; go to state 2
        inc (ix+$12)
        ret
  .ends

  .bank $01 slot 1
  .org $0687
  .section "credits state 2 update 1" overwrite
    ; increase B component of sprite color C
    ld hl,($D338)
    ld de,$0100
    add hl,de
    ld ($D338),hl
  .ends

  .bank $01 slot 1
  .org $069B
  .section "credits state 2 update 2" overwrite
    ; decrease B component of sprite color C
    ld hl,($D338)
    ld de,$0100
    or a
    sbc hl,de
    ld ($D338),hl
  .ends

  .bank $01 slot 1
  .org $067D
  .section "credits state 2 update 3a" overwrite
    jp creditsState2Setup
  .ends

  ; fuck
  .unbackground $7B53 $7B86
  
  .bank $01 slot 1
  .section "credits state 2 update 3b" free
    creditsState2Setup:
      ; print next string
      ld a,(ix+$3C)
      inc (ix+$3C)
      doBankedCall printCreditsString
      
      ; do color component increment
      jp $4687
  .ends

  ;=====
  ; eliminate some poorly-placed sparkles in chibiusa's credits
  ;=====

  .bank $18 slot 2
  .org $0392
  .section "chibiusa credits fix 1" overwrite
    .dw $0000,$0000
  .ends

  .bank $18 slot 2
  .org $03B6
  .section "chibiusa credits fix 2" overwrite
    .dw $0000,$0000
  .ends

  .bank $18 slot 2
  .org $03BC
  .section "chibiusa credits fix 3" overwrite
    .dw $0000,$0000
  .ends

  .bank $18 slot 2
  .org $03E0
  .section "chibiusa credits fix 4" overwrite
    .dw $0000,$0000
  .ends

  ; move some inconvenient bubbles down
  .bank $18 slot 2
  .org $01C4
  .section "chibiusa credits fix 5" overwrite
    .dw $0000,$007B,$008B,$0000,$001C,$003F,$004F,$0000,$0000
  .ends
  .bank $18 slot 2
  .org $01E8
  .section "chibiusa credits fix 6" overwrite
    .dw $0000,$007C,$008C,$00BD,$00CD,$005F,$006F,$0000,$0000
  .ends
  .bank $18 slot 2
  .org $020C
  .section "chibiusa credits fix 7" overwrite
    .dw $0000,$0000,$0000,$00BE,$00CE,$0070,$0080,$005B,$006B
  .ends
  .bank $18 slot 2
  .org $0230
  .section "chibiusa credits fix 8" overwrite
    .dw $0000,$0000,$0000,$00BF,$00CF,$004B,$0000,$005C,$006C
  .ends

;========================================
; title
;========================================
  
  ;=====
  ; load new graphics
  ;=====

  .bank $01 slot 1
  .org $14AA
  .section "title init 1" overwrite
    call initTitle
  .ends

  .bank $01 slot 1
  .section "title init 2" free
    initTitle:
      ; make up work
      call $063E
      doBankedCallNoParams initTitle_ext
      ret
  .ends

  .slot 2
  .section "title init 3" superfree
    titleSpriteGrp: .incbin "out/grp/title_sprites.bin" FSIZE titleSpriteGrpSize
   .define numTitleSpriteGrpTiles titleSpriteGrpSize/bytesPerTile
    titleBgGrp: .incbin "out/grp/title_bg.bin" FSIZE titleBgGrpSize
   .define numTitleBgGrpTiles titleBgGrpSize/bytesPerTile
    
  
    initTitle_ext:
      ; new sprite graphics
      ld de,titleSpriteGrp
      ld hl,$6000
      ld b,numTitleSpriteGrpTiles
      rawTilesToVdp_macro
      
      ; new title graphics
      ld de,titleBgGrp
      ld hl,$6800
      ld b,numTitleBgGrpTiles
      rawTilesToVdp_macro
      
      ret
  .ends
  
  ;=====
  ; title tilemap
  ;=====

  .bank $06 slot 2
  .org $34E7
  .section "title bg tilemap" overwrite
    .incbin "out/maps/title.bin"
  .ends
  
  ;=====
  ; y-position of "pretty soldier" overlay
  ;=====

  .bank $01 slot 1
  .org $155C
  .section "title overlay 1" overwrite
    ld hl,$001C-6
  .ends

;========================================
; password and score screens
;========================================
  
  ;=====
  ; load new graphics
  ;=====

  .bank $01 slot 1
  .org $2DE2
  .section "password init 1" overwrite
;    call initPassword
     doBankedCallNoParams initPassword_ext
     nop
  .ends

/*  .bank $01 slot 1
  .section "password init 2" free
    initPassword:
      ; make up work
;      call $063E
      doBankedCallNoParams initPassword_ext
      ret
  .ends */

  .slot 2
  .section "password init 3" superfree
    passwordGrp: .incbin "out/grp/passwordscore_bg.bin" FSIZE passwordGrpSize
   .define numPasswordGrpTiles passwordGrpSize/bytesPerTile
    
    initPassword_ext:
      ; new graphics
      ld de,passwordGrp
      ld hl,$4000
      ld b,numPasswordGrpTiles
      rawTilesToVdp_macro
      
      ret
  .ends
  
  ;=====
  ; in-place tilemap updates
  ;=====

  .bank $04 slot 2
  .org $15FD
  .section "password tilemaps 1" overwrite
     .incbin "out/maps/password1.bin"
  .ends

  .bank $04 slot 2
  .org $178F
  .section "password tilemaps 2" overwrite
     .incbin "out/maps/password2.bin"
  .ends
  
  ;=====
  ; resized tilemap updates
  ;=====
  
  .unbackground $13F00 $13FFF

  .bank $04 slot 2
  .section "password tilemaps 3" free
    passwordTilemap3:
      ; dimensions
      .db $0C,$02
      .incbin "out/maps/password3.bin"
    passwordTilemap4:
      ; dimensions
      .db $08,$02
      .incbin "out/maps/password4.bin"
  .ends

  .bank $01 slot 1
  .org $282E
  .section "password tilemaps 4" overwrite
     ld hl,passwordTilemap3
  .ends

  .bank $01 slot 1
  .org $2A63
  .section "password tilemaps 5" overwrite
     ld hl,passwordTilemap3
  .ends

  .bank $01 slot 1
  .org $2825
  .section "password tilemaps 6" overwrite
     ld hl,passwordTilemap4
  .ends

  .bank $01 slot 1
  .org $2998
  .section "password tilemaps 7" overwrite
     ld hl,passwordTilemap4
  .ends

;========================================
; sound test
;========================================

  ;=====
  ; init
  ;=====

  .bank $01 slot 1
  .org $2C4B
  .section "sound test 1" overwrite
    doBankedCallNoParams initSoundTest
  .ends

  .slot 2
  .section "sound test 2" superfree
    soundTestGrp: .incbin "out/grp/soundtest.bin" FSIZE soundTestGrpSize
   .define numSoundTestGrpTiles soundTestGrpSize/bytesPerTile
    
  
    initSoundTest:
      ; new graphics
      ld de,soundTestGrp
      ld hl,$4000
      ld b,numSoundTestGrpTiles
      rawTilesToVdp_macro
      
      ; make up work
      ld a,$01
      ld ($C00D),a
      jp $01C8
  .ends

  ;=====
  ; tilemap 
  ;=====

  .bank $1F slot 1
  .org $09E6
  .section "sound test 3" overwrite
    .incbin "out/maps/soundtest.bin"
  .ends

;========================================
; voice subtitles
;========================================

  ;=====
  ; load our new graphics in place of the old ones
  ;=====
  
  .define oldUsagiGrpBank $12
  .define oldUsagiGrp1Ptr $8000
  .define oldUsagiGrp2Ptr $97F4

  .bank $01 slot 1
  .org $1A67
  .section "voice 1" overwrite
    call checkVoiceGrpLoad
  .ends

  .bank $01 slot 1
  .section "voice 2" free
    checkVoiceGrpLoad:
      doBankedCall checkVoiceGrpLoad_ext
      
      ; if result of call is nonzero, we didn't remap and need to make up
      ; work
      or a
      ret z
      call $063E
      ret
  .ends

  .slot 2
  .section "voice 3" superfree
    checkVoiceGrpLoad_ext:
      ; check if bank matches
      cp oldUsagiGrpBank
      ret nz
      
      push af
        ld a,h
        cp >oldUsagiGrp1Ptr
        jr nz,@checkGrp2
        ld a,l
        cp <oldUsagiGrp1Ptr
        jr nz,@checkGrp2
        
        @grp1Match:
          pop af
          
          push bc
            ; this code is really dumb but who cares
            doBankedCallNoParams loadNewUsagiGrp1
          pop bc
          
          ; return zero in A to mark graphic as remapped
          xor a
          ret
      
      @checkGrp2:
      pop af
      push af
        ld a,h
        cp >oldUsagiGrp2Ptr
        jr nz,@noMatch
        ld a,l
        cp <oldUsagiGrp2Ptr
        jr nz,@noMatch
        
        @grp2Match:
          pop af
          
          push bc
            doBankedCallNoParams loadNewUsagiGrp2
          pop bc
          
          xor a
          ret
      
      @noMatch:
      pop af
      ; make up work
      ret
  .ends

  .slot 2
  .section "new usagi grp 1" superfree
    newUsagiGrp1: .incbin "out/grp/transform_usa-1.bin" FSIZE newUsagiGrp1Size
    .define numNewUsagiGrp1Tiles newUsagiGrp1Size/bytesPerTile
    
    loadNewUsagiGrp1:
      ; new graphics
      ld de,newUsagiGrp1
      ld hl,$4000
      ld bc,numNewUsagiGrp1Tiles
      rawTilesToVdp_big_macro
      ret
  .ends

  .slot 2
  .section "new usagi grp 2" superfree
    newUsagiGrp2: .incbin "out/grp/transform_usa-2.bin" FSIZE newUsagiGrp2Size
    .define numNewUsagiGrp2Tiles newUsagiGrp2Size/bytesPerTile
    
    loadNewUsagiGrp2:
      ; new graphics
      ld de,newUsagiGrp2
      ld hl,$4000
      ld bc,numNewUsagiGrp2Tiles
      rawTilesToVdp_big_macro
      ret
  .ends

  ;=====
  ; patch existing tilemaps
  ;=====

  .bank $12 slot 2
  .org $3506
  .section "voice old tilemaps 1" overwrite
    .incbin "out/maps/transform_usa-1.bin"
  .ends

  .bank $12 slot 2
  .org $3818
  .section "voice old tilemaps 2" overwrite
    .incbin "out/maps/transform_usa-2.bin"
  .ends

  .bank $12 slot 2
  .org $3AEA
  .section "voice old tilemaps 3" overwrite
    .incbin "out/maps/transform_usa-3.bin"
  .ends

  .bank $1F slot 2
  .org $0714
  .section "voice old tilemaps 4" overwrite
    .incbin "out/maps/transform_usa-4.bin"
  .ends

  ;=====
  ; intial transformation subtitles 1
  ;=====

  .slot 2
  .section "sub tilemaps" superfree
    ; intial scene
    subTilemap1:
      ; dimensions
      .db $14,$12
      .incbin "out/maps/transform_usa-1_sub.bin"
    ; sailor moon pose
    subTilemap2:
      ; dimensions
      .db $14,$12
      .incbin "out/maps/transform_usa-3_sub.bin"
    ; super sailor moon pose
    subTilemap3:
      ; dimensions
      .db $14,$12
      .incbin "out/maps/transform_usa-4_sub.bin"
  
  .ends

  .bank $01 slot 1
  .org $1981
  .section "use subs 1-1" overwrite
    call doVoiceSubs1
    nop
    nop
  .ends

  .bank $01 slot 1
  .section "use subs 1-2" free
    doVoiceSubs1:
      ; load tilemap
      ld b,:subTilemap1
      ld hl,subTilemap1
      call loadFarTilemap
      
      ; play voice
      ld a,$01
      call playVoice
      
      ; restore original tilemap
      ld b,$12
      ld hl,$B504
      jp loadFarTilemap
  .ends

  .bank $01 slot 1
  .section "use subs 1-3" free
    loadFarTilemap:
      ld a,(mapperSlot2Ctrl)
      push af
        ld a,b
        ld (mapperSlot2Ctrl),a
        
        ld de,$0000
        call loadSizedTilemap
      pop af
      ld (mapperSlot2Ctrl),a
      ret
  .ends

  .bank $01 slot 1
  .org $19FE
  .section "use subs 2-1" overwrite
    call doVoiceSubs2
    nop
    nop
  .ends

  .bank $01 slot 1
  .section "use subs 2-2" free
    doVoiceSubs2:
      ; load tilemap
      ld b,:subTilemap2
      ld hl,subTilemap2
      call loadFarTilemap
      
      ; play voice
      xor a
      call playVoice
      
      ; restore original tilemap
      ld b,$12
      ld hl,$BAE8
      jp loadFarTilemap
  .ends

  .bank $01 slot 1
  .org $1AA6
  .section "use subs 3-1" overwrite
    call doVoiceSubs3
    nop
    nop
  .ends

  .bank $01 slot 1
  .section "use subs 3-2" free
    doVoiceSubs3:
      ; load tilemap
      ld b,:subTilemap3
      ld hl,subTilemap3
      call loadFarTilemap
      
      ; play voice
      xor a
      call playVoice
      
      ; restore original tilemap
      ld b,$1F
      ld hl,$8712
      jp loadFarTilemap
  .ends

  ;=====
  ; fully protect data writes in loadSizedTilemap
  ; (original routine only protected the address write, resulting in
  ; corruption when the subtitle map was applied and probably elsewhere
  ; throughout the game)
  ;=====

  .bank $00 slot 0
  .org $06A4
  .section "loadSizedTilemap" SIZE $21 overwrite
    ld a,(hl)
    sla a
    ld c,a
    inc hl
    ld a,(hl)
    ld b,a
    inc hl
    di 
    -:
    ; DO NOT DO THIS
;      di 
      ld a,e
      out ($BF),a
      ld a,d
      add a,$78
      out ($BF),a
    ; DO NOT DO THIS
;      ei 
      push bc
      ld b,c
      ld c,$BE
      otir 
      ex de,hl
      ld c,$40
      add hl,bc
      ex de,hl
      pop bc
      djnz -
    ei 
    ret 
  .ends
  


;========================================
; luna-p
;========================================

  ;=====
  ; set up vwf
  ;=====
  
  .define oldLunaPBank $19
  .define oldLunaPPtr $95E5

  .bank $01 slot 1
  .org $077A
  .section "luna-p 1" overwrite
    call checkLunaP
  .ends

  .bank $01 slot 1
  .section "luna-p 2" free
    checkLunaP:
      doBankedCall checkLunaP_ext
      
      ; if result of call is nonzero, we didn't remap and need to make up
      ; work
      or a
      ret z
      call $063E
      ret
  .ends
  
  ; this is technically the sprite palette for the sega screen.
  ; it's not used and we need the space
  ; edit: no this breaks the fucking credits. fuck.
;  .unbackground $53DC $53FB
  
  .slot 2
  .section "luna-p 3" superfree
    newLunaPGrp: .incbin "out/grp/lunap_game_bg.bin" FSIZE newLunaPGrpSize
    .define numNewLunaPGrpTiles newLunaPGrpSize/bytesPerTile
    
    checkLunaP_ext:
      ; check if bank matches
      cp oldLunaPBank
      ret nz
      
      push af
        ld a,h
        cp >oldLunaPPtr
        jr nz,@noMatch
        ld a,l
        cp <oldLunaPPtr
        jr nz,@noMatch
        
        @grpMatch:
          pop af
          
          push bc
            ; new graphics
            ld de,newLunaPGrp
            ld hl,$4000
            ld bc,numNewLunaPGrpTiles
            rawTilesToVdp_big_macro
          pop bc
          
          xor a
          ret
      
      @noMatch:
      pop af
      ; make up work
      ret
  .ends

;========================================
; fix obscure bug in fortune teller
; intro text.
;
; flag C221 is set when the main game
; is being played. the minigame intros
; check it to determine if they need
; to display the "here's the bonus
; game" intro message.
; this flag is cleared when the
; minigame menu is opened, but _not_
; when the fortune teller option is
; selected!
; this means that getting a game over
; or beating the game, then selecting
; the fortune teller will cause it to
; try to append the bonus game text,
; which is actually a dummy pointer
; to the regular intro text (since
; the fortune teller has no bonus
; game intro). this results in the
; intro text getting copied twice.
; 
; this issue occurs even in the
; original game!
; good catch cccmar!
;========================================

.bank $01 slot 1
.org $1758
.section "fortune teller bugfix 1" overwrite
  doBankedCallNoParams fortuneTellerFlagFix
  nop
  nop
.ends

.slot 2
.section "fortune teller bugfix 2" superfree
  fortuneTellerFlagFix:
    ; clear the "playing main game" flag
    xor a
    ld ($C221),a
    
    ; make up work
    ld a,$04
    ld ($C22A),a
    ld a,$06
    ld ($C002),a
    ret
.ends

