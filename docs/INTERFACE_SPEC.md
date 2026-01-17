# HOCS Hardware Interface Specification (ICD)
**Version:** 1.2.0  
**Last Updated:** January 2026  
**Protocol:** AXI4-Stream / PCIe Layout  

---

## 1. Data Representation
The HOCS Optical Core operates in the analog domain. Therefore, the Host Logic must perform quantization before data transmission.

* **Host Format:** Float32 (IEEE 754)
* **Hardware Format:** Int16 (Fixed Point Q4.12)
    * *Bit 15:* Sign bit
    * *Bit 14-12:* Integer part
    * *Bit 11-0:* Fractional part (Matches 12-bit DAC resolution)
* **Endianness:** Little Endian (LSB First)
* **Alignment:** 64-bit word aligned (Padding added if row < 64 bits)

---

## 2. DMA Packet Structure
Data is transferred via AXI Stream in "Job Packets". Every transfer must follow this envelope structure to ensure data integrity.

| Byte Offset | Field | Size | Description |
| :--- | :--- | :--- | :--- |
| **HEADER** | | | |
| 0x00 | `MAGIC_VAL` | 4B | Constant `0xH0C5` (Identifies HOCS Packet) |
| 0x04 | `OPCODE` | 4B | `0x1`=WRITE, `0x2`=READ, `0x3`=CONFIG |
| 0x08 | `PAYLOAD_LEN`| 4B | Size of the Matrix Data in Bytes |
| 0x0C | `TILE_ID` | 4B | Sequence ID for large matrix tiling |
| **PAYLOAD** | | | |
| 0x10 | `DATA[]` | N | Quantized Int16 Matrix Data (Row-Major) |
| **FOOTER** | | | |
| N+0x10 | `CRC32` | 4B | Checksum for error detection |

**Max Payload Size:** 4 MB per transaction (HugePage Limit).  
**Ideal Tile Size:** 128x128 elements (32 KB) to fit standard L1 Caches.

---

## 3. Register Map (Memory Mapped IO)
Control and Status Registers (CSR) are mapped to BAR0 at offset `0x4000_0000`.

| Offset | Name | R/W | Description |
| :--- | :--- | :--- | :--- |
| `0x00` | **CONTROL** | R/W | `Bit 0`: Start, `Bit 1`: Abort, `Bit 2`: Soft Reset |
| `0x04` | **STATUS** | RO | `Bit 0`: Idle, `Bit 1`: Busy, `Bit 2`: Data Ready |
| `0x08` | **ERROR** | RO | `Bit 0`: None, `Bit 1`: DMA Timeout, `Bit 2`: Thermal Shutdown |
| `0x0C` | **VERSION** | RO | Returns Hardware Version (e.g., `0x020400` for v2.4.0) |
| `0x10` | **TEMP** | RO | FPGA Core Temperature (Raw Value) |

---

## 4. Timing & Latency Expectations
* **Optical Propagation:** ~50 ps (Speed of light in waveguide)
* **ADC/DAC Latency:** ~2 µs (Conversion time)
* **DMA Overhead:** ~15 µs (Driver kernel calls)
* **Target Round-Trip Time:** < 50 µs per Tile.
* **Timeout Threshold:** If hardware does not assert `DONE` within **100 ms**, the Driver triggers a "Watchdog Reset".

## 5. Error Handling & Reset
1.  **Soft Reset:** Driver writes `0x4` to `CONTROL` register. Clears FIFO buffers and resets State Machine to IDLE.
2.  **Hard Abort:** If `ERROR` register reads `0xDEAD` (Thermal Critical), the driver must sever the PCIe link immediately.
3.  **Versioning:** Driver checks `VERSION` register on startup. If `HW_VER != SW_VER`, connection is refused.
4.  
