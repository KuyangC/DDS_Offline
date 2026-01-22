#!/usr/bin/env python3
"""
"""

import asyncio
import websockets
import json
import socket
import sys
import threading
from datetime import datetime

PORT = 81

DEVICES = [
    {'address': '01', 'name': 'Device 01 - Lantai 1', 'zones': ['Zona 1', 'Zona 2', 'Zona 3', 'Zona 4', 'Zona 5']},
    {'address': '02', 'name': 'Device 02 - Lantai 2', 'zones': ['Zona 6', 'Zona 7', 'Zona 8', 'Zona 9', 'Zona 10']},
    {'address': '03', 'name': 'Device 03 - Lantai 3', 'zones': ['Zona 11', 'Zona 12', 'Zona 13', 'Zona 14', 'Zona 15']},
]

clients = set()
current_scenario = 0
uptime_counter = 0
scenario_changed = True
trouble_rotation_index = 0
last_trouble_rotation_time = 0
trouble_rotation_active = False


def get_wifi_ip():
    """Auto detect WiFi IP address"""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except:
        return "127.0.0.1"


def calculate_checksum(data):
    """Calculate checksum sederhana (SUM-based)"""
    total = sum(ord(c) for c in data)
    return format(total, 'X').zfill(4)


# Trouble rotation scenarios (untuk Mode 2 - auto rotate setiap 30 detik)
TROUBLE_SCENARIOS = [
    # Trouble di Device 1 - Zone 1
    [
        {'address': '01', 'alarm': '00', 'trouble': '01'},  # Zone 1 Trouble
        {'address': '02', 'alarm': '00', 'trouble': '00'},
        {'address': '03', 'alarm': '00', 'trouble': '00'},
    ],
    # Trouble di Device 1 - Zone 2 & 3
    [
        {'address': '01', 'alarm': '00', 'trouble': '06'},  # Zone 2 & 3 Trouble (0x02 + 0x04 = 0x06)
        {'address': '02', 'alarm': '00', 'trouble': '00'},
        {'address': '03', 'alarm': '00', 'trouble': '00'},
    ],
    # Trouble di Device 2 - Zone 1 & 2
    [
        {'address': '01', 'alarm': '00', 'trouble': '00'},
        {'address': '02', 'alarm': '00', 'trouble': '03'},  # Zone 1 & 2 Trouble (0x01 + 0x02 = 0x03)
        {'address': '03', 'alarm': '00', 'trouble': '00'},
    ],
    # Trouble di Device 2 - Zone 4 & 5
    [
        {'address': '01', 'alarm': '00', 'trouble': '00'},
        {'address': '02', 'alarm': '00', 'trouble': '18'},  # Zone 4 & 5 Trouble (0x08 + 0x10 = 0x18)
        {'address': '03', 'alarm': '00', 'trouble': '00'},
    ],
    # Trouble di Device 3 - Zone 2 & 4
    [
        {'address': '01', 'alarm': '00', 'trouble': '00'},
        {'address': '02', 'alarm': '00', 'trouble': '00'},
        {'address': '03', 'alarm': '00', 'trouble': '0A'},  # Zone 2 & 4 Trouble (0x02 + 0x08 = 0x0A)
    ],
]

# Alarm scenarios (untuk Mode 3)
ALARM_SCENARIOS = [
    # Device 1 - Zone 1 Alarm
    [
        {'address': '01', 'alarm': '01', 'trouble': '00'},
        {'address': '02', 'alarm': '00', 'trouble': '00'},
        {'address': '03', 'alarm': '00', 'trouble': '00'},
    ],
    # Device 1 - Zone 3 & 5 Alarm
    [
        {'address': '01', 'alarm': '14', 'trouble': '00'},  # Zone 3 & 5 Alarm (0x04 + 0x10 = 0x14)
        {'address': '02', 'alarm': '00', 'trouble': '00'},
        {'address': '03', 'alarm': '00', 'trouble': '00'},
    ],
    # Device 2 - Zone 2 & 3 Alarm
    [
        {'address': '01', 'alarm': '00', 'trouble': '00'},
        {'address': '02', 'alarm': '06', 'trouble': '00'},  # Zone 2 & 3 Alarm (0x02 + 0x04 = 0x06)
        {'address': '03', 'alarm': '00', 'trouble': '00'},
    ],
    # Device 3 - Zone 1 & 5 Alarm
    [
        {'address': '01', 'alarm': '00', 'trouble': '00'},
        {'address': '02', 'alarm': '00', 'trouble': '00'},
        {'address': '03', 'alarm': '11', 'trouble': '00'},  # Zone 1 & 5 Alarm (0x01 + 0x10 = 0x11)
    ],
    # Multi-device Alarm
    [
        {'address': '01', 'alarm': '05', 'trouble': '00'},  # Zone 1 & 3 Alarm
        {'address': '02', 'alarm': '02', 'trouble': '00'},  # Zone 2 Alarm
        {'address': '03', 'alarm': '00', 'trouble': '00'},
    ],
]

# Mode 4: Pre-Alarm scenarios
PRE_ALARM_SCENARIOS = [
    # Device 1 - Zone 3 Pre-Alarm
    [
        {'address': '01', 'alarm': '04', 'trouble': '00'},
        {'address': '02', 'alarm': '00', 'trouble': '00'},
        {'address': '03', 'alarm': '00', 'trouble': '00'},
    ],
    # Device 2 - Zone 5 Pre-Alarm
    [
        {'address': '01', 'alarm': '00', 'trouble': '00'},
        {'address': '02', 'alarm': '10', 'trouble': '00'},
        {'address': '03', 'alarm': '00', 'trouble': '00'},
    ],
]

# Mode 5: Alarm with Bell ON scenarios
ALARM_WITH_BELL_SCENARIOS = [
    # Device 1 - Zone 1 Alarm with Bell
    [
        {'address': '01', 'alarm': '21', 'trouble': '00'}, # 0x20 (bell) + 0x01 (zone 1)
        {'address': '02', 'alarm': '00', 'trouble': '00'},
        {'address': '03', 'alarm': '00', 'trouble': '00'},
    ],
    # Device 3 - Zone 4 Alarm with Bell
    [
        {'address': '01', 'alarm': '00', 'trouble': '00'},
        {'address': '02', 'alarm': '00', 'trouble': '00'},
        {'address': '03', 'alarm': '28', 'trouble': '00'}, # 0x20 (bell) + 0x08 (zone 4)
    ],
]

# Mode 6: Alarm Silenced scenarios
ALARM_SILENCED_SCENARIOS = [
    # Device 1 - Zone 1 Alarm, but silenced
    [
        {'address': '01', 'alarm': '01', 'trouble': '00'}, # No 0x20 bit
        {'address': '02', 'alarm': '00', 'trouble': '00'},
        {'address': '03', 'alarm': '00', 'trouble': '00'},
    ],
]


# Mode 1: Normal - semua devices OK
MODE_NORMAL = [
    {'address': '01', 'alarm': '00', 'trouble': '00'},
    {'address': '02', 'alarm': '00', 'trouble': '00'},
    {'address': '03', 'alarm': '00', 'trouble': '00'},
]


def get_scenario_name(index):
    """Get scenario description"""
    names = [
        "1: ONLINE/NORMAL - Semua devices OK",            # index 0
        "2: TROUBLE - Auto rotate zone trouble setiap 30 detik", # index 1
        "3: ALARM - Auto rotate zona alarm (tanpa bell)", # index 2
        "4: NO DATA/DISCONNECT - WebSocket berhenti mengirim data", # index 3 (moved from 6)
        "5: PRE-ALARM - Satu zona pre-alarm (tanpa bell)", # index 4 (moved from 3)
        "6: ALARM + BELL ON - Zona alarm DENGAN bell (0x20) dan konfirmasi $85", # index 5 (moved from 4)
        "7: ALARM SILENCED - Zona alarm aktif TAPI bell silent (dengan konfirmasi $84)", # index 6 (moved from 5)
    ]
    return names[index] if index < len(names) else f"Mode {index + 1}"


def generate_zone_data(mode_index):
    """Generate zone data sesuai format ESP32"""
    STX = '<STX>'
    scenario = None

    # Mode 4: No Data
    if mode_index == 3:
        return ''

    # Select the correct scenario based on mode
    if mode_index == 0:     # Mode 1: Normal
        scenario = MODE_NORMAL
    elif mode_index == 1:   # Mode 2: Trouble
        scenario = TROUBLE_SCENARIOS[trouble_rotation_index % len(TROUBLE_SCENARIOS)]
    elif mode_index == 2:   # Mode 3: Alarm (no bell)
        scenario = ALARM_SCENARIOS[trouble_rotation_index % len(ALARM_SCENARIOS)]
    elif mode_index == 4:   # Mode 5: Pre-Alarm
        scenario = PRE_ALARM_SCENARIOS[trouble_rotation_index % len(PRE_ALARM_SCENARIOS)]
    elif mode_index == 5:   # Mode 6: Alarm with Bell
        scenario = ALARM_WITH_BELL_SCENARIOS[trouble_rotation_index % len(ALARM_WITH_BELL_SCENARIOS)]
    elif mode_index == 6:   # Mode 7: Alarm Silenced
        scenario = ALARM_SILENCED_SCENARIOS[trouble_rotation_index % len(ALARM_SILENCED_SCENARIOS)]
    else:
        scenario = MODE_NORMAL

    # Build device data string by iterating through the scenario
    device_data = ''
    for device in scenario:
        address = device['address']
        alarm = device['alarm']
        trouble = device['trouble']

        # Append the core device data
        device_data += f'{STX}{address}{trouble}{alarm}'

        # NEW LOGIC: Append confirmation code immediately after the triggering device
        # Check if this device is the one with the alarm condition
        if alarm != '00':
            if mode_index == 5:  # Mode 6: ALARM + BELL ON
                device_data += f'{STX}$85'
            elif mode_index == 6:  # Mode 7: ALARM SILENCED
                device_data += f'{STX}$84'

    # Calculate checksum on the final, complete data string
    checksum = calculate_checksum(device_data)

    # Full packet
    zone_packet = f'41DF{checksum}{device_data}'
    return zone_packet


def generate_json_message(mode_index, uptime):
    """Generate JSON message"""
    zone_data = generate_zone_data(mode_index)

    # Mode 4: No Data - return None
    if mode_index == 3 or not zone_data: # Now index 3
        return None

    message = {
        "timestamp": uptime,
        "data": zone_data,
        "clients": len(clients),
        "freeHeap": 254412 - (mode_index * 100)
    }

    return json.dumps(message)


def print_menu():
    """Print interactive menu"""
    print('\n' + '=' * 70)
    print('                        PILIH MODE')
    print('=' * 70)
    for i in range(7):
        print(f'  {get_scenario_name(i)}')
    print('=' * 70)
    print('  Ketik angka mode (1-7) lalu ENTER')
    print('  Ketik "q" atau "x" untuk keluar')
    print('=' * 70)


def input_thread():
    """Thread for handling user input"""
    global current_scenario, scenario_changed, trouble_rotation_index

    while True:
        print_menu()
        try:
            choice = input('\nPilihan Anda: ').strip().lower()

            if choice in ['q', 'x', 'quit', 'exit']:
                print("\nShutting down server...")
                sys.exit(0)

            try:
                choice_int = int(choice)
                if 1 <= choice_int <= 7:
                    current_scenario = choice_int - 1  # Convert to 0-based index
                    scenario_changed = True
                    trouble_rotation_index = 0  # Reset rotation when mode changes
                    print(f"\nMode diubah ke: {get_scenario_name(choice_int - 1)}")
                else:
                    print(f"\nPilihan tidak valid! Masukkan angka 1-7")
            except ValueError:
                print("\nInput tidak valid! Masukkan angka.")

        except EOFError:
            break
        except KeyboardInterrupt:
            break


async def handle_client(websocket):
    """Handle client connection"""
    print(f"\n[{datetime.now().strftime('%H:%M:%S')}] New client connected from {websocket.remote_address}")
    clients.add(websocket)

    try:
        async for message in websocket:
            # Handle incoming messages if needed
            pass
    except websockets.exceptions.ConnectionClosed:
        pass
    finally:
        clients.discard(websocket)
        print(f"\n[{datetime.now().strftime('%H:%M:%S')}] Client disconnected")


async def broadcast_data():
    """Broadcast data setiap 2 detik"""
    global current_scenario, uptime_counter, scenario_changed
    global trouble_rotation_index, last_trouble_rotation_time, trouble_rotation_active

    last_scenario = -1
    broadcast_count = 0

    while True:
        if clients:
            uptime_counter += 1
            broadcast_count += 1

            # Auto-rotate untuk Mode 2 (Trouble) dan Mode 3 (Alarm) setiap 30 detik
            # 30 detik / 2 detik per broadcast = 15 broadcasts
            if current_scenario in [1, 2]:  # Mode 2 atau 3
                if broadcast_count % 15 == 0:  # Setiap 30 detik
                    trouble_rotation_index += 1
                    scenario_changed = True
                    rotation_info = ""

                    if current_scenario == 1:  # Trouble mode
                        trouble_scenario = TROUBLE_SCENARIOS[trouble_rotation_index % len(TROUBLE_SCENARIOS)]
                        rotation_info = f"Trouble rotation #{trouble_rotation_index + 1}"
                    else:  # Alarm mode
                        alarm_scenario = ALARM_SCENARIOS[trouble_rotation_index % len(ALARM_SCENARIOS)]
                        rotation_info = f"Alarm rotation #{trouble_rotation_index + 1}"

                    print(f"\n[{datetime.now().strftime('%H:%M:%S')}] 🔄 {rotation_info}")

            # Only print when scenario changes atau pada rotasi
            if current_scenario != last_scenario or scenario_changed:
                mode_desc = get_scenario_name(current_scenario)
                if current_scenario in [1, 2] and trouble_rotation_index > 0:
                    mode_desc += f" (Rotation #{trouble_rotation_index + 1})"
                print(f"\n[{datetime.now().strftime('%H:%M:%S')}] Mengirim: {mode_desc}")
                last_scenario = current_scenario
                scenario_changed = False

            # Mode 4: No Data - skip sending
            if current_scenario == 3:
                print(f"\n[{datetime.now().strftime('%H:%M:%S')}] ⚠️  NO DATA MODE - Tidak mengirim data (testing auto-reconnect)")
            else:
                json_message = generate_json_message(current_scenario, uptime_counter)

                if json_message:  # Only send if not None
                    for client in list(clients):
                        try:
                            await client.send(json_message)
                        except:
                            clients.remove(client)

        await asyncio.sleep(2)


async def main():
    global current_scenario

    wifi_ip = get_wifi_ip()

    print('\n' + '=' * 70)
    print('        Dummy WebSocket Server - Fire Alarm Monitoring System')
    print('=' * 70)
    print(f'  WiFi IP   : {wifi_ip}')
    print(f'  Port      : {PORT}')
    print(f'  WS URL    : ws://{wifi_ip}:{PORT}')
    print(f'  Devices   : {len(DEVICES)} (Address: 01, 02, 03)')
    print(f'  Zones     : 15 zones (5 zones per device)')
    print('=' * 70)
    print(f'\n  Server berjalan. Menunggu koneksi client...')
    print(f'  Gunakan aplikasi Flutter atau Postman untuk connect ke WebSocket')
    print(f'  Pilih mode 1-4 untuk simulasi berbagai skenario\n')

    # Start input thread in background
    threading.Thread(target=input_thread, daemon=True).start()

    async with websockets.serve(handle_client, "0.0.0.0", PORT):
        await broadcast_data()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\n\nServer stopped.")
