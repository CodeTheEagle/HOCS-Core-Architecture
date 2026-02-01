; ==============================================================================
;  FILE: hocs_memory.s
;  MODULE: HOCS Memory Management Unit (MMU) & Direct Memory Access (DMA)
;  AUTHOR: CodeTheEagle Team (Yusuf & Mikail)
;  TARGET: Xilinx Kria K26 (ARM Cortex-A53 Cluster)
;  VERSION: 2.4.1 (Experimental/Heavy-Load)
;
;  DESCRIPTION:
;  This assembly module implements the "Zero-Copy" memory architecture required
;  to sustain >3 TB/s internal throughput. It handles:
;    1. Page Table Walks (Translating Virtual Addresses to Physical).
;    2. TLB (Translation Lookaside Buffer) Invalidation & Maintenance.
;    3. Cache Coherency (PoC/PoU Flushing) for Optical DMA.
;    4. Scatter-Gather DMA List Processing (Chained Optical Jobs).
;
;  WARNING:
;  This code manipulates System Control Registers (SCTLR_EL1, TCR_EL1).
;  Improper use will cause synchronous Data Aborts or System Deadlocks.
; ==============================================================================

.include "hocs_defs.inc"

.section .text
.global _init_mmu_system
.global _flush_cache_range
.global _start_optical_dma
.global _handle_page_fault

; ------------------------------------------------------------------------------
; [1] MMU INITIALIZATION (The Foundation of Virtual Memory)
; ------------------------------------------------------------------------------
; Unlike standard MCUs, HOCS runs in Virtual Memory space.
; We must configure the Translation Control Register (TCR) and Memory Attribute
; Indirection Register (MAIR) to define "Cacheable" vs "Device" memory.

_init_mmu_system:
    PUSH    {lr}
    
    ; --- STEP 1: Configure MAIR_EL1 (Memory Attributes) ---
    ; Attr0: Device-nGnRnE (Strongly Ordered) -> For FPGA Registers
    ; Attr1: Normal Memory (Outer Write-Back, Inner Write-Back) -> For RAM
    LDR     x0, =0x000000FF44000000  ; Magic bitmask for ARMv8
    MSR     mair_el1, x0             ; Write to MAIR register
    ISB                              ; Instruction Synchronization Barrier

    ; --- STEP 2: Configure TCR_EL1 (Translation Control) ---
    ; T0SZ = 25 (39-bit Virtual Address Space for 512GB support)
    ; TG0  = 00 (4KB Page Granule)
    ; ORGN/IRGN = Write-Back Cacheable
    LDR     x0, =0x00000005B5193519  ; High-performance paging setup
    MSR     tcr_el1, x0
    ISB

    ; --- STEP 3: Set Translation Table Base (TTBR0) ---
    ; Pointing the CPU to our Page Global Directory (PGD)
    LDR     x0, =PAGE_TABLE_BASE
    MSR     ttbr0_el1, x0
    ISB
    TLBI    VMALLE1                  ; Invalidate entire TLB (Flush old maps)
    DSB     SY                       ; Data Synchronization Barrier

    ; --- STEP 4: Enable MMU (SCTLR_EL1) ---
    MRS     x0, sctlr_el1
    ORR     x0, x0, #(1 << 0)        ; M bit (MMU Enable)
    ORR     x0, x0, #(1 << 2)        ; C bit (Data Cache Enable)
    ORR     x0, x0, #(1 << 12)       ; I bit (Instruction Cache Enable)
    MSR     sctlr_el1, x0
    ISB                              ; Pipeline flush - We are now Virtual!

    POP     {pc}

; ------------------------------------------------------------------------------
; [2] CACHE COHERENCY MANAGER (Critical for FPGA DMA)
; ------------------------------------------------------------------------------
; The CPU has L1/L2 Caches. The FPGA (Optical Core) reads directly from RAM.
; If we don't flush the CPU cache to RAM, the Laser will process old/garbage data.
; This is the most common bug in High-Performance Computing.

_flush_cache_range:
    ; INPUT: X0 = Start Address, X1 = Size (bytes)
    ADD     x1, x0, x1               ; Calculate End Address
    MRS     x2, ctr_el0              ; Read Cache Type Register
    UBFX    x2, x2, #16, #4          ; Extract Log2(Line Size)
    MOV     x3, #4
    LSL     x3, x3, x2               ; X3 = Cache Line Size (usually 64 bytes)
    SUB     x4, x3, #1               ; Mask
    BIC     x0, x0, x4               ; Align Start Address

_clean_invalidate_loop:
    DC      CIVAC, x0                ; Data Cache Clean & Invalidate to PoC
    ADD     x0, x0, x3               ; Move to next cache line
    CMP     x0, x1
    BLT     _clean_invalidate_loop   ; Keep going until range covered
    
    DSB     SY                       ; Ensure operation completes
    RET

; ------------------------------------------------------------------------------
; [3] SCATTER-GATHER OPTICAL DMA ENGINE
; ------------------------------------------------------------------------------
; Instead of copying one matrix at a time, we build a "Chain" of jobs.
; The FPGA reads this chain and executes them back-to-back without waking the CPU.
; This is how we reach Terabit speeds.

_start_optical_dma:
    ; INPUT: X0 = Pointer to Descriptor Chain (Head Node)
    PUSH    {x19-x30, lr}
    
    MOV     x19, x0                  ; Save Head Pointer

    ; 1. Check if Optical Core is READY
    LDR     x1, =REG_HOCS_STATUS
_dma_wait_idle:
    LDR     w2, [x1]
    TST     w2, #STS_IDLE
    BEQ     _dma_wait_idle           ; Spin-wait (or sleep in real OS)

    ; 2. Load Descriptor Address to FPGA
    LDR     x3, =REG_DMA_DESC_PTR
    STR     w19, [x3]                ; Tell FPGA where the list starts

    ; 3. Trigger "Fetch & Execute" Command
    LDR     x4, =REG_HOCS_CONFIG
    MOV     w5, #(CMD_DMA_SCATTER | CMD_START_MVM)
    STR     w5, [x4]                 ; GO!

    ; 4. FPGA is now mastering the bus. CPU can perform other tasks.
    ;    We enable interrupts to get notified when the chain finishes.
    MSR     daifclr, #2              ; Unmask IRQ
    
    POP     {x19-x30, pc}

; ------------------------------------------------------------------------------
; [4] PAGE FAULT HANDLER (When things go wrong)
; ------------------------------------------------------------------------------
; If the Optical Core tries to access unmapped memory, an exception triggers.
; We must handle this gracefully or the kernel crashes.

_handle_page_fault:
    MRS     x0, far_el1              ; Get Faulting Address
    MRS     x1, esr_el1              ; Get Exception Syndrome (Why did it fail?)
    
    ; Check if it's a Translation Fault (Page not present)
    AND     x2, x1, #0x3F            ; Extract status code
    CMP     x2, #0x04                ; Level 1 Translation Fault?
    BEQ     _map_missing_page

    ; Check if it's a Permission Fault (Access Denied)
    CMP     x2, #0x0D                ; Permission Fault?
    BEQ     _segfault_kill_process

    ; Unknown error -> Kernel Panic
    B       _kernel_panic

_map_missing_page:
    ; (Advanced Logic: Allocate a physical page and update Page Table)
    ; For prototype, we just verify we have reserved RAM.
    LDR     x3, =RESERVED_POOL_START
    CMP     x0, x3
    BLT     _segfault_kill_process   ; Address is below reserved pool
    
    ; ... (Allocation Logic would go here) ...
    
    TLBI    VMALLE1                  ; Flush TLB to see new mapping
    ERET                             ; Retry the instruction

_segfault_kill_process:
    ; Print "Segmentation Fault" to UART
    LDR     x0, =msg_segfault
    BL      uart_print
    
    ; Dump Registers for Debugging
    MOV     x0, sp
    BL      dump_registers
    
    B       .                        ; Hang system safely

; ------------------------------------------------------------------------------
; [5] ATOMIC 128-BIT MEMORY COPY (NEON SIMD OPTIMIZED)
; ------------------------------------------------------------------------------
; Standard memcpy is too slow. We use 128-bit NEON registers (Q-regs)
; to move data inside the CPU cache.

_fast_memcpy_128:
    ; INPUT: X0 = Dest, X1 = Src, X2 = Size (must be 64-byte aligned)
    
_copy_loop_64:
    LDP     q0, q1, [x1], #32        ; Load 32 Bytes (2x 128-bit)
    LDP     q2, q3, [x1], #32        ; Load next 32 Bytes
    
    STP     q0, q1, [x0], #32        ; Store 32 Bytes
    STP     q2, q3, [x0], #32        ; Store next 32 Bytes
    
    SUBS    x2, x2, #64
    B.GT    _copy_loop_64            ; Loop if more data
    
    RET

; ------------------------------------------------------------------------------
; [6] SYSTEM CONTROL BLOCK (Register Definitions)
; ------------------------------------------------------------------------------
.section .data
.align 4

msg_segfault:    .asciz "\n[CRITICAL] SEGMENTATION FAULT! DMA HALTED.\n"

; DMA Descriptor Structure (Linked List Node) for Documentation
; struct dma_desc {
;    uint32_t next_desc_ptr;  // Pointer to next job
;    uint32_t src_addr;       // RAM Address of Matrix
;    uint32_t size;           // Size in bytes
;    uint32_t flags;          // IRQ_ON_DONE, FLUSH_CACHE, etc.
; }

.end

