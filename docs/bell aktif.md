kondisi bell :
bell aktif : AABB(CC + 20) = 20 adalah kode bell aktif
$85 adalah data jawaban dari slave , bahwa bell telah diaktifkan (dan zona yang alarm masih terdeteksi) (kita tidak akan memproses ini)
$84 adalah data jawaban dari slave, bahwa bell tidak diaktifkan (tapi zona yang alarm masih terdeteksi)


jadi seharusnya untuk ui bell dideteksi dengan kode 20 pada tiap slave, bukan $85 ataupun $84. tapi tolong pertimbangkan juga kondisi ini :
jika suatu zona terjadi fire, lalu bell aktif maka data yang akan diterima adalah <STX>AABB(CC+20)<STX>$85<STX> . bentuk data tersebut akan dihasilkan selama fire masih terdeteksi di zona tersebut. jika fire hilang maka bentuk data akan menjadi <STX>AABB(CC+20)<STX>  (data $85 hilang) . tapi dengan keadaan seperti ini bell tetap aktif karena kode data CC+20 juga masih ada.



kondisi yang harus diperhatikan :
flow bell aktif : 
1. sistem mendapatkan data AABBCC , dimana CC menunjukan zona yang mengalami fire
2. sistem mendapatkan data AABB(CC+ 0x20) , tapi saat ini bell belum diaktifkan. (0x20 adalah perintah untuk menyalakan bell)
3. Slave mengkonfirmasi bahwa bell sudah diaktifkan dengan kode $85. maka sistem akan mendapatkan bentuk data : <STX>AABB(CC+20)<STX>$85<STX> (BELL SUDAH BENAR AKTIF)
4. jika kondisi tersbut sudah tercapai, lalu fire tidak terdeteksi lagi dari zona. maka data akan berubah bentuk lagi menjadi :  <STX>AABB20<STX> , dimana (CC zona yang mengalami fire sudah tidak terdeteksi ,tapi hanya tersisa 0x20 yang menandakan bell masih aktif) , dan $85 juga hilang karena zona CC yang mengalami fire juga sudah hilang.
5. bell benar-benar off saat tidak ada kode 0x20 pada data slave. <STX>AABBCC<STX> maka bell sudah off.


kode (CC + 0x20) = bell aktif dengan input zona mengalami fire masih aktif
kode 0x20 = bell masih aktif (tapi input zona fire sudah hilang) = ui bell masih harus aktif (merah) pertahankan status bell aktif sampai 0x20 hilang juga.
