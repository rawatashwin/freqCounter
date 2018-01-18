#include "p12f675.inc"

; CONFIG
; __config 0xF1D4
 __CONFIG _FOSC_INTRCIO & _WDTE_OFF & _PWRTE_OFF & _MCLRE_OFF & _BOREN_ON & _CP_OFF & _CPD_OFF

; Input
#define     freqInput   GPIO, 5

; Lcd using 74hc595
#define     lcdData     GPIO, 0
#define     lcdClk      GPIO, 1
#define     lcdEn       GPIO, 2
 
    cblock	    0x20
	w_tmp
	status_tmp
	tmr1_counter
	counting_flag
	range_err_flag
	
	; Pulses per 62.5 ms
	freqBy16_2
	freqBy16_1
	freqBy16_0
	; Frequency in binary
	freqh3
	freqh2
	freqh1
	freqh0
	; Frequency in bcd
	freqd9
	freqd8
	freqd7
	freqd6
	freqd5
	freqd4
	freqd3
	freqd2
	freqd1
	freqd0
	bitcnt	
	digcnt
    endc

; Bank Switching macros
bank0	macro
	bcf STATUS, 5
	endm
	
bank1	macro
	bsf STATUS, 5
	endm
	
; Reset Vector
    org	    0x00
    goto    start
    org	    0x04
    goto    isr
    
; Start
start:
    call    init
    call    repeat

; Loop
repeat:
    ; Skip if still counting
    btfss   counting_flag, 0
    call    startCounting
    ; FreqBy16 to Freqh
    call    getFreq
    ; Get Freq in BCD from Freqh
    call    freqToBCD
    ; Display on lcd
    goto    repeat
    
init:
    ; Setup GPIO
    ; ANSEL
    bank1
    clrf    ANSEL
    
    ; TRISIO
    movlw   b'00101111'
    bank1
    movwf   TRISIO
    
    ; Setup timer1 as counter to count pulses on pin 2
    movlw   b'00110110'	; Async counter with 1/8 prescaler
    bank0
    movwf   T1CON
    
    ; Setup timer0 
    movlw   b'00000111' ; Count system clock with prescler 256
    bank0  
    movwf   OPTION_REG
    
    ; Setup LCD
    return
    
startCounting:
    ; Get number of pulses in 62.5ms and multiply by 16 (62.5ms * 16 = 1s) to get freq in Hz
    ; Setup Interrupts
    bank1
    ; Timer1 Int enable
    bsf	    PIE1, 0 
    bank0
    ; Clear tmr1_counter
    clrf    tmr1_counter
    ; Set Counting Flag
    bsf	    counting_flag, 0
    ; Peripheral Int enable
    bsf	    INTCON, 6 
    ; Tmr0 Int enable
    bsf	    INTCON, 5 
    ; Setup timer0 for 62.5ms
    movlw   0x0c   
    movwf   TMR0
    ; Start timer1
    bsf	    T1CON, 0
    ; Enable Int
    bsf	    INTCON, 7
    return
    
stopCounting:
    ; Stop timer0 Int
    bcf	    INTCON, 5
    ; Stop timer1
    bcf	    T1CON, 0
    ; Reset T0IF
    bcf	    INTCON, 2
    ; Reset TMR1IF
    bcf	    PIR1, 0
    ; Reset counting flag
    bcf	    counting_flag, 0
    ; Put TMR1 into freqBy16
    movf    TMR1L, w
    movwf   freqBy16_0
    movf    TMR1H, w
    movwf   freqBy16_1
    movf    tmr1_counter
    movwf   freqBy16_2
    return
    
incTmr1Cntr:
    incfsz  tmr1_counter
    return
    bsf	    range_err_flag, 0
    return
    
getFreq:
    clrf    freqh0
    clrf    freqh1
    clrf    freqh2
    clrf    freqh3
    
    ; Multiply Freq by 2*2*2*2
    call    times2
    call    times2
    call    times2
    call    times2
    return    
times2:
    rlf	    freqBy16_0, w
    movwf   freqh0
    rlf	    freqBy16_1, w
    movwf   freqh1
    rlf	    freqBy16_2, w
    movwf   freqh2
    rlf	    freqh3
    return
    
; Convert freqh into bcd and store it in freqd
; Taken from http://www.piclist.com/techref/member/BB-LTL-/index.htm
freqToBCD:
    clrf    freqd9	; Clear previous value
    clrf    freqd8
    clrf    freqd7
    clrf    freqd6
    clrf    freqd5
    clrf    freqd4
    clrf    freqd3
    clrf    freqd2
    clrf    freqd1
    clrf    freqd0
    ; Outer loop bit counter
    movlw   D'32'	
    movwf   bitcnt	
b2bcd1:
    ; Shift 32bit bin acc left to put ms bit into carry
    rlf	    freqh0, f	
    rlf	    freqh1, f	   
    rlf	    freqh2, f	   
    rlf	    freqh3, f	
    ; Point to address of ls bcd digit
    movlw   freqd0	
    movwf   FSR		
    ; Inner loop digit coutner
    movlw   D'10'
    movwf   digcnt
b2bcd2:
    ; Shift carry into bcd digit
    rlf	    INDF, f
    ; Substract 10 from digit then check and adjust for decimal overflow
    movlw   D'10'
    subwf   INDF, w
    ; If carry = 1 (result >= 0) adjust for decimal overflow
    btfsc   STATUS, C
    movwf   INDF
    ; Point to next BCD digit
    decf    FSR, f
    ; Decrement digcnt, loop if > 0
    decfsz  digcnt, f
    goto    b2bcd2
    ; Decrement bitcnt, loop if > 0
    decfsz  bitcnt, f
    goto    b2bcd1
    retlw   0   

; Interrupt Service Routine    
isr:
    bank0
    ; Disable Int
    bcf	    INTCON, 7 
    ; Context Save    
    movwf   w_tmp
    swapf   STATUS, w
    movwf   status_tmp
    ; end Context Save
    
    ; ISR
    ; Check if tmr0 overflowed
    btfsc   INTCON, 2
    call    stopCounting
    btfsc   PIR1, 0
    call    incTmr1Cntr
    
    ; Context Retrive
    swapf   status_tmp, w
    movwf   STATUS
    swapf   w_tmp, f
    swapf   w_tmp, w
    ; Return    
    retfie
    
    end