; ==============================================================================
;  FILE: hocs_interrupts.s
;  ARCHITECTURE: HOCS V1 (Hybrid Optical Architecture) - ARM64/FPGA Hybrid
;  AUTHOR: CodeTheEagle Team (Yusuf & Mikail)
;  DATE: February 2026
;  LICENSE: Proprietary / Trade Secret
;
;  DESCRIPTION:
;  This is the HEART of the HOCS Micro-Kernel. It handles:
;   1. Vector Table (IVT) relocation and management.
;   2. Context Switching (Preemptive Multitasking logic).
;   3. Critical Hardware Faults (Thermal Runaway, Optical Misalignment).
;   4. Atomic Semaphore handling for Shared Memory (FPGA <-> CPU).
;
;  NOTE TO REVIEWERS:
;  This code runs in EL1 (Exception Level 1) Supervisor Mode.
;  Do NOT attempt to modify Stack Pointer (SP) offsets without updating the ABI.
; ==============================================================================

.include "hocs_defs.inc"

.section .text
.global _vector_table_base
.global _irq_router
.global _kernel_panic

; ------------------------------------------------------------------------------
; [1] ADVANCED VECTOR TABLE (AArch64 Compatible)
; ------------------------------------------------------------------------------
; This table aligns to 2048 bytes (0x800) as per ARMv8 specification.
; It handles exceptions from Current EL with SP_EL0 and SP_ELx.

.align 11
_vector_table_base:
    ; --- Current EL with SP0 ---
    B   _handler_sync_sp0       ; Synchronous (Instruction Abort, Data Abort)
    .align 7
    B   _handler_irq_sp0        ; IRQ (Hardware Interrupt)
    .align 7
    B   _handler_fiq_sp0        ; FIQ (Fast Interrupt - Optical DMA)
    .align 7
    B   _handler_serror_sp0     ; SError (System Error)
    .align 7

    ; --- Current EL with SPx ---
    B   _handler_sync_spx
    .align 7
    B   _handler_irq_spx
    .align 7
    B   _handler_fiq_spx
    .align 7
    B   _handler_serror_spx
    .align 7

    ; --- Lower EL using AArch64 ---
    B   _handler_sync_a64
    .align 7
    B   _handler_irq_a64
    .align 7
    B   _handler_fiq_a64
    .align 7
    B   _handler_serror_a64
    .align 7

; ------------------------------------------------------------------------------
; [2] CONTEXT SWITCHING MACROS (The "Magic" Part)
; ------------------------------------------------------------------------------
; This saves the entire CPU state (32 Registers + Flags) to the stack.
; Essential for multitasking.

.macro SAVE_CONTEXT
    SUB     sp, sp, #256             ; Allocate stack frame
    STP     x0, x1, [sp, #16 * 0]    ; Save X0, X1
    STP     x2, x3, [sp, #16 * 1]    ; Save X2, X3
    STP     x4, x5, [sp, #16 * 2]
    STP     x6, x7, [sp, #16 * 3]
    STP     x8, x9, [sp, #16 * 4]
    STP     x10, x11, [sp, #16 * 5]
    STP     x12, x13, [sp, #16 * 6]
    STP     x14, x15, [sp, #16 * 7]
    STP     x16, x17, [sp, #16 * 8]
    STP     x18, x19, [sp, #16 * 9]
    STP     x20, x21, [sp, #16 * 10]
    STP     x22, x23, [sp, #16 * 11]
    STP     x24, x25, [sp, #16 * 12]
    STP     x26, x27, [sp, #16 * 13]
    STP     x28, x29, [sp, #16 * 14] ; Save Frame Pointer
    MRS     x21, elr_el1             ; Save Exception Link Register
    MRS     x22, spsr_el1            ; Save Program Status Register
    STP     x30, x21, [sp, #16 * 15] ; Save LR and ELR
    STR     x22, [sp, #256 - 8]      ; Save SPSR
    
    ; Save Floating Point / SIMD Registers (Critical for Optical Math)
    STP     q0, q1, [sp, #-32]!
    STP     q2, q3, [sp, #-32]!
.endm

.macro RESTORE_CONTEXT
    ; Restore SIMD Registers
    LDP     q2, q3, [sp], #32
    LDP     q0, q1, [sp], #32

    ; Restore General Registers
    LDR     x22, [sp, #256 - 8]
    MSR     spsr_el1, x22
    LDP     x30, x21, [sp, #16 * 15]
    MSR     elr_el1, x21
    LDP     x28, x29, [sp, #16 * 14]
    LDP     x26, x27, [sp, #16 * 13]
    LDP     x24, x25, [sp, #16 * 12]
    LDP     x22, x23, [sp, #16 * 11]
    LDP     x20, x21, [sp, #16 * 10]
    LDP     x18, x19, [sp, #16 * 9]
    LDP     x16, x17, [sp, #16 * 8]
    LDP     x14, x15, [sp, #16 * 7]
    LDP     x12, x13, [sp, #16 * 6]
    LDP     x10, x11, [sp, #16 * 5]
    LDP     x8, x9, [sp, #16 * 4]
    LDP     x6, x7, [sp, #16 * 3]
    LDP     x4, x5, [sp, #16 * 2]
    LDP     x2, x3, [sp, #16 * 1]
    LDP     x0, x1, [sp, #16 * 0]
    ADD     sp, sp, #256
    ERET                             ; Return from Exception
.endm

; ------------------------------------------------------------------------------
; [3] INTERRUPT SERVICE ROUTINES (ISR) - The "Brain" Logic
; ------------------------------------------------------------------------------

_handler_irq_spx:
    SAVE_CONTEXT            ; 1. Freeze time (Save state)
    
    ; 2. Read Interrupt Controller (GIC) to see WHO called
    LDR     x0, =GIC_IAR_REG ; Interrupt Acknowledge Register
    LDR     w1, [x0]         ; Get Interrupt ID (IAR)
    AND     w1, w1, #0x3FF   ; Mask ID bits

    ; 3. Check for OPTICAL CORE completion (ID #42)
    CMP     w1, #42
    BEQ     _isr_optical_done

    ; 4. Check for DLP SYNC (ID #43)
    CMP     w1, #43
    BEQ     _isr_dlp_sync

    ; 5. Check for THERMAL ALARM (ID #99)
    CMP     w1, #99
    BEQ     _isr_thermal_critical

    ; Default: Unknown Interrupt
    B       _isr_exit

_isr_optical_done:
    ; Logic: The Optical Core finished a Matrix Multiplication.
    ; We need to signal the Userspace Application.
    LDR     x2, =HOCS_STATUS_REG
    MOV     w3, #STS_IDLE    ; Set status to IDLE
    STR     w3, [x2]
    
    ; Trigger Callback
    BL      scheduler_tick   ; Check if other tasks are waiting
    B       _isr_exit

_isr_thermal_critical:
    ; EMERGENCY SHUTDOWN PROCEDURE
    ; This code must run in < 1 microsecond to save the hardware.
    
    LDR     x2, =LASER_PWR_REG
    MOV     w3, #0
    STR     w3, [x2]         ; HARD CUT Laser Power

    LDR     x0, =0xDEADBEEF  ; Error Code
    BL      _kernel_panic    ; Halt System
    
_isr_exit:
    ; Acknowledge Interrupt (EOI)
    LDR     x0, =GIC_EOI_REG
    STR     w1, [x0]
    
    RESTORE_CONTEXT         ; Unfreeze time (Resume task)

; ------------------------------------------------------------------------------
; [4] PROCESS SCHEDULER (Round Robin)
; ------------------------------------------------------------------------------
scheduler_tick:
    ; This simple scheduler rotates between Optical Jobs.
    ; Real OSs use Red-Black Trees, we use a circular buffer for speed.
    
    LDR     x0, =TASK_LIST_PTR
    LDR     x1, [x0]         ; Load current task
    
    CMP     x1, #0           ; Is task list empty?
    BEQ     _sched_return

    ; ... (Context switch logic would go here) ...

_sched_return:
    RET

; ------------------------------------------------------------------------------
; [5] KERNEL PANIC HANDLER (The "Blue Screen" of HOCS)
; ------------------------------------------------------------------------------
_kernel_panic:
    ; If we are here, something catastrophic happened.
    ; We blink the LED in an SOS pattern.
    
    LDR     x1, =GPIO_LED_ADDR
    MOV     w2, #1           ; LED ON
    
_panic_loop:
    STR     w2, [x1]
    MOV     x3, #100000      ; Delay
_delay1:
    SUBS    x3, x3, #1
    BNE     _delay1
    
    MVN     w2, w2           ; Toggle LED
    B       _panic_loop      ; Hang forever.

; ------------------------------------------------------------------------------
; [6] ATOMIC LOCKS (For Multicore Safety)
; ------------------------------------------------------------------------------
; Since Kria K26 has 4 Cores, we need locking to prevent data corruption.

_acquire_lock:
    MOV     w2, #1
    LDXR    w1, [x0]         ; Load Exclusive
    CBNZ    w1, _acquire_lock ; If locked, retry (Spinlock)
    STXR    w3, w2, [x0]     ; Store Exclusive
    CBNZ    w3, _acquire_lock ; If store failed, retry
    DMB     ish              ; Data Memory Barrier
    RET

_release_lock:
    DMB     ish
    MOV     w1, #0
    STR     w1, [x0]
    RET

; ==============================================================================
; END OF INTERRUPT HANDLER
; ==============================================================================

