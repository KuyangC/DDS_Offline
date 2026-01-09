#!/usr/bin/env python3
"""
Dummy WebSocket Server untuk Testing Fire Alarm Monitoring System
Simulasi data dari 3 device ESP32 dengan format JSON

Run dengan: python3 dummy_websocket_server.py

IP WiFi otomatis didetect dari network interface

Format Data JSON:
{
    "timestamp": 7,
    "data": "41DF0370<STX>010000<STX>020400<STX>030000",
    "clients": 1,
    "freeHeap": 252412
}
"""

import asyncio
import websockets
import socket
import json
import threading
import sys
from datetime import datetime

# Konfigurasi
PORT = 81

# 3 Device dengan 5 zona each
DEVICES = [
    {'address': '01', 'name': 'Device 01 - Lantai 1', 'zones': ['Zona 1', 'Zona 2', 'Zona 3', 'Zona 4', 'Zona 5']},
    {'address': '02', 'name': 'Device 02 - Lantai 2', 'zones': ['Zona 6', 'Zona 7', 'Zona 8', 'Zona 9', 'Zona 10']},
    {'address': '03', 'name': 'Device 03 - Lantai 3', 'zones': ['Zona 11', 'Zona 12', 'Zona 13', 'Zona 14', 'Zona 15']},
]

clients = set()
current_scenario = 0
uptime_counter = 0
scenario_changed = True


def get_wifi_ip():
    """Auto detect WiFi IP address"""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return 'localhost'


def calculate_checksum(data):
    """Calculate SUM-based checksum"""
    total = sum(ord(c) for c in data)
    return format(total, 'X').zfill(4)


# Scenario definitions
# (device_index, zone_index, alarm_bit, trouble_bit, description)
# zone_index: 0-4 (5 zones per device), None = all normal
# alarm_bit: hex value for the zone alarm bit
# trouble_bit: hex value for the zone trouble bit
SCENARIOS = [
    # Normal - all devices normal
    [
        {'address': '01', 'alarm': '00', 'trouble': '00'},
        {'address': '02', 'alarm': '00', 'trouble': '00'},
        {'address': '03', 'alarm': '00', 'trouble': '00'},
    ],
    # Device 1 - Zone 1 Alarm (bit 0 = 0x01)
    [
        {'address': '01', 'alarm': '01', 'trouble': '00'},  # Zone 1 Alarm
        {'address': '02', 'alarm': '00', 'trouble': '00'},
        {'address': '03', 'alarm': '00', 'trouble': '00'},
    ],
    # Device 1 - Zone 2 Alarm (bit 1 = 0x02)
    [
        {'address': '01', 'alarm': '02', 'trouble': '00'},  # Zone 2 Alarm
        {'address': '02', 'alarm': '00', 'trouble': '00'},
        {'address': '03', 'alarm': '00', 'trouble': '00'},
    ],
    # Device 1 - Zone 3 Alarm (bit 2 = 0x04)
    [
        {'address': '01', 'alarm': '04', 'trouble': '00'},  # Zone 3 Alarm
        {'address': '02', 'alarm': '00', 'trouble': '00'},
        {'address': '03', 'alarm': '00', 'trouble': '00'},
    ],
    # Device 1 - Zone 4 Alarm (bit 3 = 0x08)
    [
        {'address': '01', 'alarm': '08', 'trouble': '00'},  # Zone 4 Alarm
        {'address': '02', 'alarm': '00', 'trouble': '00'},
        {'address': '03', 'alarm': '00', 'trouble': '00'},
    ],
    # Device 1 - Zone 5 Alarm (bit 4 = 0x10)
    [
        {'address': '01', 'alarm': '10', 'trouble': '00'},  # Zone 5 Alarm
        {'address': '02', 'alarm': '00', 'trouble': '00'},
        {'address': '03', 'alarm': '00', 'trouble': '00'},
    ],
    # Device 2 - Zone 1 Alarm
    [
        {'address': '01', 'alarm': '00', 'trouble': '00'},
        {'address': '02', 'alarm': '01', 'trouble': '00'},  # Zone 6 Alarm
        {'address': '03', 'alarm': '00', 'trouble': '00'},
    ],
    # Device 2 - Zone 2 Alarm
    [
        {'address': '01', 'alarm': '00', 'trouble': '00'},
        {'address': '02', 'alarm': '02', 'trouble': '00'},  # Zone 7 Alarm
        {'address': '03', 'alarm': '00', 'trouble': '00'},
    ],
    # Device 3 - Zone 1 Alarm
    [
        {'address': '01', 'alarm': '00', 'trouble': '00'},
        {'address': '02', 'alarm': '00', 'trouble': '00'},
        {'address': '03', 'alarm': '01', 'trouble': '00'},  # Zone 11 Alarm
    ],
    # Device 1 - Zone 1 Trouble (bit 0 = 0x01)
    [
        {'address': '01', 'alarm': '00', 'trouble': '01'},  # Zone 1 Trouble
        {'address': '02', 'alarm': '00', 'trouble': '00'},
        {'address': '03', 'alarm': '00', 'trouble': '00'},
    ],
    # Device 2 - Zone 3 Trouble (bit 2 = 0x04)
    [
        {'address': '01', 'alarm': '00', 'trouble': '00'},
        {'address': '02', 'alarm': '00', 'trouble': '04'},  # Zone 8 Trouble
        {'address': '03', 'alarm': '00', 'trouble': '00'},
    ],
]


def get_scenario_name(index):
    """Get scenario description"""
    names = [
        "0: NORMAL - Semua zona OK",
        "1: ALARM - Device 1, Zona 1 (Lantai 1)",
        "2: ALARM - Device 1, Zona 2 (Lantai 1)",
        "3: ALARM - Device 1, Zona 3 (Lantai 1)",
        "4: ALARM - Device 1, Zona 4 (Lantai 1)",
        "5: ALARM - Device 1, Zona 5 (Lantai 1)",
        "6: ALARM - Device 2, Zona 1 (Lantai 2)",
        "7: ALARM - Device 2, Zona 2 (Lantai 2)",
        "8: ALARM - Device 3, Zona 1 (Lantai 3)",
        "9: TROUBLE - Device 1, Zona 1",
        "10: TROUBLE - Device 2, Zona 3",
    ]
    return names[index] if index < len(names) else f"Scenario {index}"


def generate_zone_data(scenario_index):
    """Generate zone data sesuai format ESP32"""
    STX = '<STX>'

    scenario = SCENARIOS[scenario_index]

    # Build device data
    device_data = ''
    for i, device in enumerate(scenario):
        address = device['address']
        alarm = device['alarm']
        trouble = device['trouble']
        device_data += f'{STX}{address}{trouble}{alarm}'

    # Calculate checksum
    checksum = calculate_checksum(device_data)

    # Full packet
    zone_packet = f'41DF{checksum}{device_data}'
    return zone_packet


def generate_json_message(scenario_index, uptime):
    """Generate JSON message"""
    zone_data = generate_zone_data(scenario_index)

    message = {
        "timestamp": uptime,
        "data": zone_data,
        "clients": len(clients),
        "freeHeap": 254412 - (scenario_index * 100)
    }

    return json.dumps(message)


def print_menu():
    """Print interactive menu"""
    print('\n' + '=' * 60)
    print('                    PILIH SCENARIO')
    print('=' * 60)
    for i in range(len(SCENARIOS)):
        print(f'  {get_scenario_name(i)}')
    print('=' * 60)
    print('  Ketik angka scenario lalu ENTER')
    print('  Ketik "q" atau "x" untuk keluar')
    print('=' * 60)


def input_thread():
    """Thread for handling user input"""
    global current_scenario, scenario_changed

    while True:
        print_menu()
        try:
            choice = input('\nPilihan Anda: ').strip().lower()

            if choice in ['q', 'x', 'quit', 'exit']:
                print("\nShutting down server...")
                sys.exit(0)

            try:
                choice_int = int(choice)
                if 0 <= choice_int < len(SCENARIOS):
                    current_scenario = choice_int
                    scenario_changed = True
                    print(f"\n✅ Scenario diubah ke: {get_scenario_name(choice_int)}")
                else:
                    print(f"\n❌ Pilihan tidak valid! Masukkan angka 0-{len(SCENARIOS)-1}")
            except ValueError:
                print("\n❌ Input tidak valid! Masukkan angka.")

        except EOFError:
            break
        except KeyboardInterrupt:
            break


async def handle_client(websocket):
    """Handle client connection"""
    client_addr = websocket.remote_address
    print(f"\n[{datetime.now().strftime('%H:%M:%S')}] Client connected: {client_addr[0]}")
    clients.add(websocket)

    try:
        async for message in websocket:
            pass
    except Exception:
        pass
    finally:
        clients.discard(websocket)
        print(f"\n[{datetime.now().strftime('%H:%M:%S')}] Client disconnected")


async def broadcast_data():
    """Broadcast data setiap 2 detik"""
    global current_scenario, uptime_counter, scenario_changed

    last_scenario = -1

    while True:
        if clients:
            uptime_counter += 1

            # Only print when scenario changes
            if current_scenario != last_scenario:
                print(f"\n[{datetime.now().strftime('%H:%M:%S')}] Mengirim: {get_scenario_name(current_scenario)}")
                last_scenario = current_scenario

            json_message = generate_json_message(current_scenario, uptime_counter)

            for client in list(clients):
                try:
                    await client.send(json_message)
                except:
                    clients.remove(client)

        await asyncio.sleep(2)


async def main():
    global current_scenario

    wifi_ip = get_wifi_ip()

    print('\n' + '=' * 60)
    print('          Dummy WebSocket Server - Interactive')
    print('=' * 60)
    print(f'  WiFi IP   : {wifi_ip}')
    print(f'  Port      : {PORT}')
    print(f'  WS URL    : ws://{wifi_ip}:{PORT}')
    print(f'  Devices   : {len(DEVICES)} (Address: 01, 02, 03)')
    print('=' * 60)
    print(f'\n  Server berjalan. Menunggu koneksi client...')
    print(f'  Gunakan aplikasi atau Postman untuk connect ke WebSocket\n')

    # Start input thread in background
    threading.Thread(target=input_thread, daemon=True).start()

    async with websockets.serve(handle_client, "0.0.0.0", PORT):
        await broadcast_data()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nShutting down...")
