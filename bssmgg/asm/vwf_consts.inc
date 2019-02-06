 
;=====
; vwf settings
;=====

; maximum number of digits that can be printed
.define maxPrintingDigits 5

.define vwfWindowRBorderIndex $1A
;  .define controlCodeStartIndex $F0
.define controlCodeStartIndex $F0
.define controlCodeLimitIndex $FF
.define vwfTileBrIndex $F0
.define opNumIndex $F8
.define opNameIndex $F9
.define opInlineNumIndex $FA
.define vwfBoxClearIndex $FD
.define vwfWaitIndex $FE
.define vwfBrIndex $FF
.define terminatorIndex $00

.define maxVwfTiles $80

.define vwfDigitStartOffset $07
.define vwfDigitSpaceOffset $1F

;=====
; misc
;=====

;  .define screenVisibleW 20
;  .define screenVisibleH 18
;  .define screenVisibleX 3
;  .define screenVisibleY 2
.define screenVisibleW 20
.define screenVisibleH 18
.define screenVisibleX 6
.define screenVisibleY 3

.define ramBankIdentifier $FE
.define noBankIdentifier $FF
.define newStringSentinel $80


