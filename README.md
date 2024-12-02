# Installer Stack Web Server

Script otomatis untuk menginstal dan mengkonfigurasi LEMP/LAMP stack pada sistem Ubuntu/Debian. Skrip ini mendukung instalasi berbagai layanan dan alat yang diperlukan untuk menjalankan server web yang aman dan efisien.

## 🚀 Fitur Utama

- Instalasi LEMP Stack (Nginx, MySQL, PHP)
- Instalasi LAMP Stack (Apache, MySQL, PHP)
- Multiple versi PHP (7.4, 8.0, 8.1, 8.2, 8.3)
- Konfigurasi MySQL yang aman
- Instalasi phpMyAdmin
- Instalasi Redis
- Instalasi Supervisor
- Instalasi Memcached
- Instalasi Let's Encrypt SSL
- Instalasi RabbitMQ
- Tools Monitoring (Netdata, Htop, Iotop, Iftop, Nethogs, Nmon)
- Backup Otomatis
- Keamanan Dasar (Firewall UFW, Fail2ban, SSH root login dinonaktifkan)

## 📋 Persyaratan Sistem

- Ubuntu/Debian OS
- Minimal 1GB RAM
- Minimal 10GB ruang disk
- Koneksi internet
- Akses root/sudo

## 🛠️ Cara Penggunaan

1. Download script:
   ```bash
   wget https://raw.githubusercontent.com/dedesyahrul/stack-web-server/main/install_stack.sh
   ```

2. Berikan izin eksekusi:
   ```bash
   chmod +x install_stack.sh
   ```

3. Jalankan script:
   ```bash
   sudo ./install_stack.sh
   ```

## 📚 Menu Utama

1. 🚀 Instal LEMP Stack
2. 🌟 Instal LAMP Stack
3. 🔧 Instal phpMyAdmin
4. 📁 Buat Proyek Baru
5. 📊 Lihat Status Layanan
6. 📦 Instal Redis
7. 👥 Instal Supervisor
8. 💾 Instal Memcached
9. 🔒 Instal Let's Encrypt
10. 🐰 Instal RabbitMQ
11. 📈 Instal Tools Monitoring
12. 💽 Setup Backup Otomatis
13. ❌ Keluar

## 📂 Struktur Direktori

- Web Root: `/var/www/html`
- Konfigurasi Nginx: `/etc/nginx/sites-available/`
- Konfigurasi PHP: `/etc/php/*/fpm/`
- Konfigurasi MySQL: `/etc/mysql/`
- Backup: `/var/backups/`
- Log: `/var/log/stack-installer/`

## 🔒 Fitur Keamanan

- Firewall UFW aktif
- Fail2ban terinstal
- SSH root login dinonaktifkan
- Password MySQL yang aman
- Konfigurasi keamanan dasar

## 🔄 Backup Otomatis

- Backup database harian
- Backup file web
- Rotasi backup 7 hari
- Jadwal: 2 AM setiap hari

## 📊 Monitoring

- Netdata dashboard
- Htop
- Iotop
- Iftop
- Nethogs
- Nmon

## 📝 Log

- Log instalasi: `/var/log/stack-installer/`
- Log rotasi otomatis
- Pesan error terdetail

## ⚠️ Peringatan

- Backup data penting sebelum instalasi
- Pastikan sistem memenuhi persyaratan minimal
- Jalankan script dengan akses root
- Catat semua password yang digenerate

## 🤝 Kontribusi

Silakan berkontribusi dengan membuat pull request atau melaporkan issue.

## 📜 Lisensi

MIT License

## 📞 Dukungan

Jika mengalami masalah, silakan buat issue di repository ini.