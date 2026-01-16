# WebSocket Data Format for DDS Monitoring System

This document outlines the WebSocket data formats used by the ESP32 (simulated by `dummy_websocket_server.py`) and the commands the client (Flutter app) can send.

## 1. Connection URL

`ws://[ESP32_IP_ADDRESS]:81`

Example: `ws://172.29.64.76:81` (The IP address will vary based on your network.)

## 2. Data Received (ESP32 to Client)

The ESP32 sends a JSON object containing system status and parsed zone data.

### JSON Structure

```json
{
  "timestamp": 12543,
  "data": "41DF40DF<STX>010000<STX>020A00<STX>$85",
  "clients": 1,
  "freeHeap": 254412
}
```

### Field Explanations

| Field     | Type    | Description                                                                                                                                                                                                                                           |
|-----------|---------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `timestamp` | `Integer` | Uptime of the ESP32 in milliseconds since boot.                                                                                                                                                                                                       |
| `data`      | `String`  | **Crucial field.** This string contains the raw data from the Master DDS (Fire Alarm Panel) and can include confirmation codes. It needs to be parsed further. Detailed format explained below.                                                       |
| `clients`   | `Integer` | Number of clients currently connected to the ESP32 WebSocket server.                                                                                                                                                                                  |
| `freeHeap`  | `Integer` | Available free memory (RAM) on the ESP32 in bytes. Useful for monitoring ESP32 performance.                                                                                                                                                           |

### Detailed `data` String Format

The `data` field is a concatenated string with specific markers and hexadecimal values.

```
┌──────────┬──────────┬────────────┬────────────┬───────────┬──────────┬───────────┬──────────┐
│ Prefix   │ Checksum │   <STX>    │  Device 1  │  <STX>    │ Device 2 │  <STX>    │  Confirm │
│ (4 hex)  │ (4 hex)  │  Marker    │  (6 hex)   │  Marker   │ (6 hex)  │  Marker   │ (3-4 char) │
├──────────┼──────────┼────────────┼────────────┼───────────┼──────────┼───────────┼──────────┤
│   41DF   │   40DF   │    <STX>   │   010000   │   <STX>   │  020A00  │   <STX>   │   $85    │
└──────────┴──────────┴────────────┴────────────┴───────────┴──────────┴───────────┴──────────┘
```
**Notes:**
*   `<STX>` is the literal string `<STX>`.
*   The `Confirm` segment (`$85` or `$84`) is optional and depends on the specific event. It is always preceded by `<STX>`.

#### Single Device Module Format (6 hex characters: `AABBCC`)

Each device module's status is represented by 6 hexadecimal characters.

```
┌────────────────────────────────────────────────────────────┐
│                    DEVICE MODULE (6 chars)                 │
├─────────────────────┬──────────────────┬───────────────────┤
│     Address         │    Trouble       │     Alarm         │
│     (2 hex)         │    (2 hex)       │     (2 hex)       │
├─────────────────────┼──────────────────┼───────────────────┤
│        01           │       0A         │       00          │
│  Device 1 (hex)     │  10 (decimal)    │  00 (decimal)     │
│                     │  0000 1010 (bin) │  0000 0000 (bin)  │
└─────────────────────┴──────────────────┴───────────────────┘

Breakdown Example (010A00):
  - Address "01" = Device number 1
  - Trouble "0A" = Zones 2 and 4 have trouble (binary 0000 1010)
  - Alarm   "00" = No alarms (binary 0000 0000)
```

#### Bitwise Zone Mapping

The `Trouble` and `Alarm` bytes use bit flags to indicate active zones (bits 0-4) and Bell status (bit 5 in the Alarm byte).

```
Trouble Byte Bit Map:  (Example: 0x0A = 0000 1010)
                          │  │  │  │  │
                          │  │  │  │  └── Bit 0: Zone 1 Status
                          │  │  │  └──── Bit 1: Zone 2 Status
                          │  │  └─────── Bit 2: Zone 3 Status
                          │  └────────── Bit 3: Zone 4 Status
                          └───────────── Bit 4: Zone 5 Status
                          (Higher bits unused for zone status)


Alarm Byte Bit Map:    (Example: 0x20 = 0010 0000)
                          │  │  │  │  │  │
                          │  │  │  │  │  └── Bit 0: Zone 1 Status
                          │  │  │  │  └──── Bit 1: Zone 2 Status
                          │  │  │  └─────── Bit 2: Zone 3 Status
                          │  │  └────────── Bit 3: Zone 4 Status
                          │  └───────────── Bit 4: Zone 5 Status
                          └───────────────── Bit 5: Bell ACTIVE Flag (0x20)
                          (Higher bits unused)
```

#### Bell Status Detection Logic

Bell status in the UI **MUST** be detected from **bit 5 (0x20)** of the `Alarm` byte in each device module. The `$85`/`$84` codes are confirmations from the slave MCU and **SHOULD NOT** be used to determine the UI's bell active state directly.

*   If `(Alarm_Byte & 0x20)` is `true` (bit 5 is `1`), the Bell is considered **ACTIVE** for that device.
*   If `(Alarm_Byte & 0x20)` is `false` (bit 5 is `0`), the Bell is considered **INACTIVE** for that device.

#### Zone Status Examples

| Data String Segment | Address | Trouble Byte | Alarm Byte | Zone 1 | Zone 2 | Zone 3 | Zone 4 | Zone 5 | Bell Active (from 0x20) | Confirm Code | Description                                          |
|---------------------|---------|--------------|------------|--------|--------|--------|--------|--------|-------------------------|--------------|------------------------------------------------------|
| `010000`            | 01      | 00           | 00         | Normal | Normal | Normal | Normal | Normal | Off                     | N/A          | Device 1: All Zones Normal                           |
| `020A00`            | 02      | 0A           | 00         | Normal | Trouble| Normal | Trouble| Normal | Off                     | N/A          | Device 2: Zones 2 & 4 have Trouble                   |
| `030020`            | 03      | 00           | 20         | Normal | Normal | Normal | Normal | Normal | **On**                  | N/A          | Device 3: No Zone Alarms, but Bell Active (0x20 set) |
| `040001`            | 04      | 00           | 01         | Alarm  | Normal | Normal | Normal | Normal | Off                     | N/A          | Device 4: Zone 1 Pre-Alarm (No Bell)                 |
| `050021`            | 05      | 00           | 21         | Alarm  | Normal | Normal | Normal | Normal | **On**                  | `$85`        | Device 5: Zone 1 Alarm, Bell Active (0x20 & 0x01 set), MCU confirms Bell ON |
| `060001`            | 06      | 00           | 01         | Alarm  | Normal | Normal | Normal | Normal | Off                     | `$84`        | Device 6: Zone 1 Alarm, Bell Silenced (0x20 not set), MCU confirms Bell OFF |

## 3. Data Sent (Client to ESP32)

The client (Flutter app) can send JSON commands to the ESP32 to change its operating mode or request status.

### JSON Command Examples

*   `{"command":"mode","value":"offline"}`: Set ESP32 to offline mode.
*   `{"command":"mode","value":"online"}`: Set ESP32 to online mode.
*   `{"command":"mode","value":"hybrid"}`: Set ESP32 to hybrid (offline/online) mode.
*   `{"command":"status"}`: Request current status from ESP32.
