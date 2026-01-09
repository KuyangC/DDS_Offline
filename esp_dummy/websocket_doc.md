Data WebSocket untuk Postman (Singkat)

URL Connection

ws://172.29.64.76:81

Data yang DITERIMA (Auto dari ESP)

{
"timestamp": 12543,
"data": "NORMAL <STX>01 <STX>02 <ETX>|FB:OK|TS:12543|MODE:Hybrid",
"clients": 1,
"freeHeap": 254412
}

Data yang DIKIRIM (Command ke ESP)

{"command":"mode","value":"offline"}
{"command":"mode","value":"online"}
{"command":"mode","value":"hybrid"}
{"command":"status"}

Penjelasan Field

| Field     | Keterangan                                            |
  |-----------|-------------------------------------------------------|
| timestamp | Waktu dalam milidetik sejak boot                      |
| data      | Data dari Serial2 (Master DDS) + info Firebase + Mode |
| clients   | Jumlah client yang terhubung                          |
| freeHeap  | Memory available ESP                                  |

Format Data Serial

- NORMAL = Semua zone aman
- FIRE = Ada zone yang terdeteksi fire
- 01 02 = Nomor zone yang aktif
-  = Akhir paket data