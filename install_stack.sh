#!/bin/bash

# ===========================================
# Web Server Stack Installer Script
# ===========================================
# Deskripsi: Script untuk menginstal dan mengkonfigurasi LEMP/LAMP stack
# Mendukung: Ubuntu/Debian
# Fitur:
# - Instalasi LEMP/LAMP Stack
# - Multiple PHP versions (7.4, 8.0, 8.1, 8.2, 8.3)
# - MySQL Server dengan konfigurasi aman
# - phpMyAdmin
# - Redis, Memcached, RabbitMQ
# - Supervisor
# - Let's Encrypt SSL
# - Monitoring Tools
# - Backup Otomatis
# ===========================================

set -e  # Hentikan skrip jika ada perintah yang gagal

# Memeriksa apakah script dijalankan sebagai root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "Script ini memerlukan akses root. Silakan jalankan dengan sudo."
        exit 1
    fi
}

# Memeriksa sistem operasi
check_os() {
    if [ ! -f /etc/debian_version ]; then
        echo "Script ini hanya mendukung sistem berbasis Debian/Ubuntu."
        exit 1
    fi
}

# Fungsi untuk menginstal dependensi umum
install_common_deps() {
    echo "Menginstal dependensi umum..."
    apt-get update
    apt-get install -y software-properties-common curl wget git unzip
}

# Fungsi untuk menambahkan repository PHP
add_php_repo() {
    echo "Menambahkan repository PHP..."
    add-apt-repository -y ppa:ondrej/php
    apt update
}

# Fungsi untuk menginstal multiple versi PHP
install_php_versions() {
    echo "Menginstal multiple versi PHP..."
    
    # Array versi PHP yang akan diinstal
    php_versions=("7.4" "8.0" "8.1" "8.2" "8.3")
    
    for version in "${php_versions[@]}"; do
        echo "Menginstal PHP $version..."
        # Tambahkan pengecekan apakah versi PHP sudah terinstal
        if dpkg -l | grep -q "php${version}-fpm"; then
            echo "PHP $version sudah terinstal"
            continue
        fi
        
        # Tambahkan penanganan error yang lebih baik
        if ! DEBIAN_FRONTEND=noninteractive apt install -y php${version}-fpm php${version}-cli php${version}-common \
            php${version}-curl php${version}-mbstring php${version}-mysql php${version}-xml \
            php${version}-zip php${version}-gd php${version}-intl php${version}-bcmath; then
            echo "Gagal menginstal PHP $version"
            return 1
        fi
        
        # Konfigurasi timezone dengan pengecekan file yang lebih aman
        for ini_file in "/etc/php/${version}/fpm/php.ini" "/etc/php/${version}/cli/php.ini"; do
            if [[ -f "$ini_file" ]]; then
                # Backup file konfigurasi sebelum modifikasi
                cp "$ini_file" "${ini_file}.bak"
                # Gunakan sed yang lebih aman
                sed -i.bak "s|;date.timezone =|date.timezone = Asia/Jakarta|" "$ini_file"
                if ! grep -q "date.timezone = Asia/Jakarta" "$ini_file"; then
                    echo "date.timezone = Asia/Jakarta" >> "$ini_file"
                fi
            fi
        done
    done
}

# Fungsi untuk mengkonfigurasi PHP
configure_php() {
    echo "Mengkonfigurasi PHP..."
    add_php_repo
    install_php_versions
}

# Fungsi untuk mengkonfigurasi MySQL
configure_mysql() {
    echo "Mengkonfigurasi MySQL..."
    
    # Tambahkan timeout untuk instalasi MySQL
    if ! timeout 300 apt install -y mysql-server; then
        echo "Timeout saat menginstal MySQL"
        return 1
    fi

    # Generate password yang lebih aman
    ROOT_PASS=$(openssl rand -base64 32)
    
    # Pastikan MySQL berjalan sebelum melakukan konfigurasi
    systemctl start mysql || {
        echo "Gagal menjalankan MySQL"
        return 1
    }
    
    # Tunggu MySQL siap
    for i in {1..30}; do
        if mysqladmin ping &>/dev/null; then
            break
        fi
        sleep 1
    done
    
    # Konfigurasi MySQL dengan penanganan error yang lebih baik
    if ! mysql --user=root <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${ROOT_PASS}';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF
    then
        echo "Gagal mengkonfigurasi MySQL"
        return 1
    fi

    # Simpan kredensial dengan permission yang lebih aman
    install -m 600 /dev/null /root/.my.cnf
    cat > /root/.my.cnf <<EOF
[client]
user=root
password=${ROOT_PASS}
EOF

    # Validasi input user MySQL
    while true; do
        read -p "Masukkan username MySQL baru: " mysql_user
        if [[ $mysql_user =~ ^[a-zA-Z0-9_]+$ ]]; then
            break
        else
            echo "Username tidak valid. Gunakan hanya huruf, angka, dan underscore."
        fi
    done

    # Validasi password MySQL
    while true; do
        read -s -p "Masukkan password MySQL baru (minimal 8 karakter): " mysql_pass
        echo
        if [[ ${#mysql_pass} -ge 8 ]]; then
            break
        else
            echo "Password terlalu pendek. Minimal 8 karakter."
        fi
    done
    
    # Buat user baru dengan penanganan error
    mysql -e "CREATE USER '${mysql_user}'@'localhost' IDENTIFIED BY '${mysql_pass}';" || {
        echo "Gagal membuat user MySQL baru"
        return 1
    }
    mysql -e "GRANT ALL PRIVILEGES ON *.* TO '${mysql_user}'@'localhost' WITH GRANT OPTION;" || {
        echo "Gagal memberikan privileges ke user MySQL"
        return 1
    }
    mysql -e "FLUSH PRIVILEGES;"
    
    echo "Password root MySQL: ${ROOT_PASS}"
    echo "Silakan catat password root MySQL di atas!"
    
    # Simpan informasi kredensial ke file terpisah dengan permission yang aman
    cat > /root/mysql_credentials.txt <<EOF
Root Username: root
Root Password: ${ROOT_PASS}
User Username: ${mysql_user}
User Password: ${mysql_pass}
EOF
    chmod 600 /root/mysql_credentials.txt
}

# Tambahkan definisi fungsi log_progress di bagian atas skrip
log_progress() {
    local step=$1
    local total=$2
    local message=$3
    echo -ne "\r[${step}/${total}] ${message}"
    logger -t install_stack "[PROGRESS] ${message}"
}

# Fungsi untuk menginstal LEMP
install_lemp() {
    local total_steps=4
    echo "Menginstal LEMP Stack..."
    
    # Konfirmasi sebelum instalasi
    read -p "Apakah Anda yakin ingin menginstal LEMP Stack? (y/n): " confirm
    if [[ $confirm != "y" ]]; then
        echo "Instalasi LEMP Stack dibatalkan."
        return 1
    fi
    
    # Menginstal Nginx
    log_progress 1 $total_steps "Menginstal Nginx..."
    if ! apt install -y nginx; then
        log_error "Gagal menginstal Nginx"
        return 1
    fi
    systemctl enable nginx
    systemctl start nginx
    
    # Menginstal dan mengkonfigurasi PHP-FPM
    log_progress 2 $total_steps "Menginstal PHP-FPM..."
    if ! apt install -y php8.3-fpm; then
        log_error "Gagal menginstal PHP-FPM"
        return 1
    fi
    systemctl enable php8.3-fpm
    systemctl start php8.3-fpm
    
    # Konfigurasi PHP dan MySQL
    log_progress 3 $total_steps "Mengkonfigurasi PHP..."
    configure_php || return 1
    
    log_progress 4 $total_steps "Mengkonfigurasi MySQL..."
    configure_mysql || return 1
    
    # Mengkonfigurasi Nginx dengan PHP 8.3
    cat > /etc/nginx/sites-available/default << 'EOL'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    root /var/www/html;
    index index.php index.html index.htm;
    server_name _;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.3-fpm.sock;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOL

    systemctl restart nginx
    
    # Set PHP 8.3 sebagai default
    update-alternatives --set php /usr/bin/php8.3
    
    echo "LEMP Stack telah berhasil diinstal dengan PHP 8.3 sebagai default!"
}

# Fungsi untuk menginstal LAMP
install_lamp() {
    echo "Menginstal LAMP Stack..."
    
    # Menginstal Apache
    apt install -y apache2
    systemctl enable apache2
    systemctl start apache2
    
    # Mengaktifkan mod_rewrite
    a2enmod rewrite
    
    configure_php
    configure_mysql
    
    # Mengkonfigurasi Apache dengan PHP 8.3
    cat > /etc/apache2/sites-available/000-default.conf << 'EOL'
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot /var/www/html
    
    <Directory /var/www/html>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    
    ErrorLog ${APACHE_LOG_DIR}/error.log
    CustomLog ${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
EOL

    # Set PHP 8.3 sebagai default untuk Apache
    a2dismod php7.4 php8.0 php8.1 php8.2 2>/dev/null || true
    a2enmod php8.3
    
    systemctl restart apache2
    
    # Set PHP 8.3 sebagai default
    update-alternatives --set php /usr/bin/php8.3
    
    echo "LAMP Stack telah berhasil diinstal dengan PHP 8.3 sebagai default!"
}

# Fungsi untuk menginstal phpMyAdmin
install_phpmyadmin() {
    echo "Menginstal phpMyAdmin..."
    
    # Definisikan versi phpMyAdmin
    PHPMYADMIN_VERSION="5.2.1"
    
    # Tambahkan pengecekan koneksi internet
    if ! ping -c 1 files.phpmyadmin.net &>/dev/null; then
        echo "Tidak dapat mengakses files.phpmyadmin.net"
        return 1
    fi
    
    # Buat direktori temporary yang aman
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR" || exit 1
    
    # Download dengan penanganan error
    if ! wget --timeout=30 "https://files.phpmyadmin.net/phpMyAdmin/${PHPMYADMIN_VERSION}/phpMyAdmin-${PHPMYADMIN_VERSION}-all-languages.zip"; then
        echo "Gagal mengunduh phpMyAdmin"
        rm -rf "$TEMP_DIR"
        return 1
    fi
    
    # Pindahkan ke direktori web
    rm -rf /usr/share/phpmyadmin
    mv "phpMyAdmin-${PHPMYADMIN_VERSION}-all-languages" /usr/share/phpmyadmin
    mkdir -p /usr/share/phpmyadmin/tmp
    chown -R www-data:www-data /usr/share/phpmyadmin
    chmod 777 /usr/share/phpmyadmin/tmp
    
    # Buat konfigurasi phpMyAdmin
    cp /usr/share/phpmyadmin/config.sample.inc.php /usr/share/phpmyadmin/config.inc.php
    
    # Generate random blowfish secret
    BLOWFISH_SECRET=$(openssl rand -base64 32)
    sed -i "s/\$cfg\['blowfish_secret'\] = '';/\$cfg\['blowfish_secret'\] = '$BLOWFISH_SECRET';/" /usr/share/phpmyadmin/config.inc.php
    
    # Konfigurasi untuk Apache
    if [ -d "/etc/apache2" ]; then
        cat > /etc/apache2/conf-available/phpmyadmin.conf <<EOF
Alias /phpmyadmin /usr/share/phpmyadmin
<Directory /usr/share/phpmyadmin>
    Options SymLinksIfOwnerMatch
    DirectoryIndex index.php
    AllowOverride All
    Require all granted
</Directory>
EOF
        a2enconf phpmyadmin
        systemctl reload apache2
    fi

    # Konfigurasi untuk Nginx
    if [ -d "/etc/nginx" ]; then
        cat > /etc/nginx/conf.d/phpmyadmin.conf <<EOF
location /phpmyadmin {
    root /usr/share/;
    index index.php index.html index.htm;
    location ~ ^/phpmyadmin/(.+\.php)$ {
        try_files \$uri =404;
        root /usr/share/;
        fastcgi_pass unix:/var/run/php/php8.1-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }
    location ~* ^/phpmyadmin/(.+\.(jpg|jpeg|gif|css|png|js|ico|html|xml|txt))$ {
        root /usr/share/;
    }
}
EOF
        systemctl reload nginx
    fi
    
    echo "phpMyAdmin telah berhasil diinstal!"
    
    # Bersihkan direktori temporary
    cd /
    rm -rf "$TEMP_DIR"
}

# Fungsi untuk menampilkan spinner loading
show_spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# Fungsi untuk menampilkan progress bar
show_progress() {
    local duration=$1
    local prefix=$2
    local width=50
    local fill="█"
    local empty="░"
    
    for ((i = 0; i <= width; i++)); do
        local progress=$((i * 100 / width))
        local completed=$((i * width / width))
        printf "\r%s [" "$prefix"
        printf "%${completed}s" | tr ' ' "$fill"
        printf "%$((width - completed))s" | tr ' ' "$empty"
        printf "] %d%%" $progress
        sleep $(bc <<< "scale=3; $duration/$width")
    done
    echo
}

# Fungsi untuk menampilkan menu yang lebih modern
show_modern_menu() {
    clear
    echo -e "\e[1;36m╔══════════════════════════════════════╗\e[0m"
    echo -e "\e[1;36m║      \e[1;33mINSTALLER STACK WEB SERVER\e[1;36m      ║\e[0m"
    echo -e "\e[1;36m╠══════════════════════════════════════╣\e[0m"
    echo -e "\e[1;36m║\e[0m 1. 🚀 Instal LEMP Stack                  \e[1;36m║\e[0m"
    echo -e "\e[1;36m║\e[0m 2. 🌟 Instal LAMP Stack                  \e[1;36m║\e[0m"
    echo -e "\e[1;36m║\e[0m 3. 🔧 Instal phpMyAdmin                  \e[1;36m║\e[0m"
    echo -e "\e[1;36m║\e[0m 4. 📁 Buat Proyek Baru                   \e[1;36m║\e[0m"
    echo -e "\e[1;36m║\e[0m 5. 📊 Lihat Status Layanan               \e[1;36m║\e[0m"
    echo -e "\e[1;36m║\e[0m 6. 📦 Instal Redis                       \e[1;36m║\e[0m"
    echo -e "\e[1;36m║\e[0m 7. 👥 Instal Supervisor                  \e[1;36m║\e[0m"
    echo -e "\e[1;36m║\e[0m 8.  Instal Memcached                   \e[1;36m║\e[0m"
    echo -e "\e[1;36m║\e[0m 9. 🔒 Instal Let's Encrypt              \e[1;36m║\e[0m"
    echo -e "\e[1;36m║\e[0m 10. 🐰 Instal RabbitMQ                   \e[1;36m║\e[0m"
    echo -e "\e[1;36m║\e[0m 11. 📈 Instal Tools Monitoring           \e[1;36m║\e[0m"
    echo -e "\e[1;36m║\e[0m 12. 💽 Setup Backup Otomatis             \e[1;36m║\e[0m"
    echo -e "\e[1;36m║\e[0m 13. ❌ Keluar                            \e[1;36m║\e[0m"
    echo -e "\e[1;36m╚═════════════════════════════════════╝\e[0m"
}

# Fungsi untuk menampilkan status layanan yang lebih modern
show_modern_status() {
    clear
    echo -e "\e[1;33m📊 Status Layanan:\e[0m"
    echo -e "\e[1;36m══════════════════\e[0m"
    
    services=("nginx" "mysql" "apache2" "php8.1-fpm" "redis-server" "rabbitmq-server")
    
    for service in "${services[@]}"; do
        if systemctl is-active "$service" >/dev/null 2>&1; then
            echo -e "🟢 $service: \e[1;32mAktif\e[0m"
        else
            echo -e "🔴 $service: \e[1;31mTidak Aktif\e[0m"
        fi
    done
}

# Fungsi untuk membuat proyek baru yang lebih interaktif
create_modern_project() {
    clear
    echo -e "\e[1;33m📁 Membuat Proyek Baru\e[0m"
    echo -e "\e[1;36m══════════════════════\e[0m"
    
    read -p "📝 Masukkan nama proyek: " project_name
    echo -e "\n Pilih jenis proyek:"
    echo "1) PHP Native"
    echo "2) Laravel"
    echo "3) WordPress"
    read -p "Pilihan Anda (1-3): " project_type
    
    mkdir -p /var/www/${project_name}
    
    case $project_type in
        1)
            echo "<?php phpinfo(); ?>" > /var/www/${project_name}/index.php
            ;;
        2)
            composer create-project laravel/laravel /var/www/${project_name}
            ;;
        3)
            wget https://wordpress.org/latest.tar.gz
            tar xf latest.tar.gz -C /var/www/${project_name} --strip-components=1
            rm latest.tar.gz
            ;;
    esac
    
    chown -R www-data:www-data /var/www/${project_name}
    show_progress 2 "Membuat proyek..."
    echo -e "\e[1;32m✅ Proyek ${project_name} berhasil dibuat!\e[0m"
}

# Tambahkan fungsi untuk logging error
log_error() {
    echo -e "\e[1;31m[ERROR] $1\e[0m"
    logger -t install_stack "[ERROR] $1"
}

# Tambahkan trap untuk penanganan error
trap 'log_error "Script mengalami kegagalan pada baris $LINENO"' ERR

# Fungsi untuk setup logging
setup_logging() {
    # Buat direktori log
    mkdir -p /var/log/stack-installer
    
    # Konfigurasi log rotation
    cat > /etc/logrotate.d/stack-installer <<EOF
/var/log/stack-installer/*.log {
    weekly
    rotate 4
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
}
EOF
    
    # Mulai logging
    exec 1> >(tee -a "/var/log/stack-installer/install_$(date +%Y%m%d_%H%M%S).log")
    exec 2>&1
}

# Fungsi untuk memeriksa spesifikasi sistem
verify_system() {
    echo "Memeriksa spesifikasi sistem..."
    
    # Cek RAM
    total_ram=$(free -m | awk '/^Mem:/{print $2}')
    if [ $total_ram -lt 1024 ]; then
        echo "⚠️ Peringatan: RAM kurang dari 1GB. Performa mungkin tidak optimal."
    fi
    
    # Cek disk space
    free_space=$(df -h / | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ $(echo "$free_space < 10" | bc) -eq 1 ]; then
        echo "⚠️ Peringatan: Ruang disk kurang dari 10GB."
    fi
    
    # Cek koneksi internet
    if ! ping -c 1 google.com >/dev/null 2>&1; then
        echo "❌ Error: Tidak ada koneksi internet."
        exit 1
    fi
}

# Main program
main() {
    setup_logging
    check_root
    check_os
    verify_system
    install_common_deps
    
    while true; do
        show_modern_menu
        read -p "💫 Masukkan pilihan Anda (1-13): " choice
        
        case $choice in
            1)
                install_lemp
                ;;
            2)
                install_lamp
                ;;
            3)
                install_phpmyadmin
                ;;
            4)
                create_modern_project
                ;;
            5)
                show_modern_status
                ;;
            6)
                install_redis
                ;;
            7)
                install_supervisor
                ;;
            8)
                install_memcached
                ;;
            9)
                install_letsencrypt
                ;;
            10)
                install_rabbitmq
                ;;
            11)
                install_monitoring
                ;;
            12)
                setup_auto_backup
                ;;
            13)
                echo -e "\e[1;32m👋 Terima kasih telah menggunakan installer ini!\e[0m"
                exit 0
                ;;
            *)
                echo -e "\e[1;31m❌ Pilihan tidak valid. Silakan coba lagi.\e[0m"
                ;;
        esac
        
        read -p "Tekan Enter untuk melanjutkan..."
    done
}

# Fungsi untuk menginstal Node.js dan npm
install_nodejs() {
    echo "Menginstal Node.js dan npm..."
    curl -fsSL https://deb.nodesource.com/setup_16.x | bash -
    apt-get install -y nodejs
}

# Fungsi untuk menginstal Composer
install_composer() {
    echo "Menginstal Composer..."
    curl -sS https://getcomposer.org/installer | php
    mv composer.phar /usr/local/bin/composer
    chmod +x /usr/local/bin/composer
}

# Fungsi untuk menginstal dependensi tambahan untuk Laravel
install_laravel_deps() {
    echo "Menginstal dependensi tambahan untuk Laravel..."
    apt install -y php-xml php-mbstring php-zip php-bcmath
}

# Fungsi untuk menginstal semua dependensi tambahan
install_additional_deps() {
    install_nodejs
    install_composer
    install_laravel_deps
}

# Menambahkan fungsi untuk menginstal Redis
install_redis() {
    echo "Menginstal Redis..."
    apt-get install -y redis-server php-redis
    systemctl enable redis-server
    systemctl start redis-server
    
    # Konfigurasi Redis untuk production
    sed -i 's/supervised no/supervised systemd/' /etc/redis/redis.conf
    sed -i 's/# maxmemory-policy noeviction/maxmemory-policy allkeys-lru/' /etc/redis/redis.conf
    
    systemctl restart redis-server
    echo "Redis telah berhasil diinstal!"
}

# Menambahkan fungsi untuk menginstal Supervisor
install_supervisor() {
    echo "Menginstal Supervisor..."
    apt install -y supervisor
    systemctl enable supervisor
    systemctl start supervisor
    echo "Supervisor telah berhasil diinstal!"
}

# Fungsi untuk menginstal Memcached
install_memcached() {
    echo "Menginstal Memcached..."
    apt install -y memcached php-memcached
    systemctl enable memcached
    systemctl start memcached
    
    # Konfigurasi dasar Memcached
    sed -i 's/-m 64/-m 128/' /etc/memcached.conf
    sed -i 's/-p 11211/-p 11211/' /etc/memcached.conf
    
    systemctl restart memcached
    echo "Memcached telah berhasil diinstal!"
}

# Fungsi untuk menginstal Let's Encrypt
install_letsencrypt() {
    echo "Menginstal Let's Encrypt..."
    apt install -y certbot
    
    if [ -d "/etc/nginx" ]; then
        apt install -y python3-certbot-nginx
    fi
    
    if [ -d "/etc/apache2" ]; then
        apt install -y python3-certbot-apache
    fi
    
    echo "Let's Encrypt telah berhasil diinstal!"
}

# Fungsi untuk menginstal RabbitMQ
install_rabbitmq() {
    echo "Menginstal RabbitMQ..."
    apt install -y rabbitmq-server
    systemctl enable rabbitmq-server
    systemctl start rabbitmq-server
    
    # Mengaktifkan plugin management
    rabbitmq-plugins enable rabbitmq_management
    
    # Membuat user admin
    rabbitmqctl add_user admin admin123
    rabbitmqctl set_user_tags admin administrator
    rabbitmqctl set_permissions -p / admin ".*" ".*" ".*"
    
    echo "RabbitMQ telah berhasil diinstal!"
}

# Fungsi untuk menginstal monitoring tools
install_monitoring() {
    echo "Menginstal monitoring tools..."
    apt install -y htop iotop iftop nethogs nmon
    
    # Menginstal netdata
    bash <(curl -Ss https://my-netdata.io/kickstart.sh) --non-interactive
    
    echo "Tools monitoring telah berhasil diinstal!"
}

# Fungsi untuk mengatur backup otomatis
setup_auto_backup() {
    echo "Mengatur backup otomatis..."
    
    # Membuat direktori backup
    mkdir -p /var/backups/mysql
    mkdir -p /var/backups/www
    
    # Membuat script backup
    cat > /usr/local/bin/backup.sh <<'EOL'
#!/bin/bash
DATE=$(date +%Y-%m-%d)
# Backup MySQL
mysqldump --all-databases > /var/backups/mysql/all-db-$DATE.sql
# Backup www
tar -czf /var/backups/www/www-$DATE.tar.gz /var/www/
# Hapus backup lebih dari 7 hari
find /var/backups/mysql/ -type f -mtime +7 -delete
find /var/backups/www/ -type f -mtime +7 -delete
EOL
    
    chmod +x /usr/local/bin/backup.sh
    
    # Menambahkan ke crontab
    (crontab -l 2>/dev/null; echo "0 2 * * * /usr/local/bin/backup.sh") | crontab -
    
    echo "Backup otomatis telah diatur!"
}

# Sebelum memodifikasi file konfigurasi
backup_config() {
    local file=$1
    if [ -f "$file" ]; then
        cp "$file" "${file}.bak.$(date +%Y%m%d_%H%M%S)"
    fi
}

# Gunakan sebelum memodifikasi file
backup_config /etc/php/8.1/fpm/php.ini

# Main program
main

# Tambahkan fungsi untuk memeriksa versi software yang terinstal
check_versions() {
    echo "Memeriksa versi software yang terinstal..."
    php --version || log_error "PHP tidak terinstal dengan benar"
    nginx -v || log_error "Nginx tidak terinstal dengan benar"
    mysql --version || log_error "MySQL tidak terinstal dengan benar"
}

# Tambahkan di akhir instalasi LEMP/LAMP
check_versions

cleanup() {
    echo "Membersihkan file temporary..."
    rm -rf /tmp/phpMyAdmin*
    apt clean
    apt autoremove -y
}

# Tambahkan di akhir instalasi
trap cleanup EXIT

security_hardening() {
    echo "Menerapkan konfigurasi keamanan dasar..."
    
    # Konfigurasi SSH
    sed -i 's/#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
    
    # Konfigurasi firewall dasar
    apt install -y ufw
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow ssh
    ufw allow http
    ufw allow https
    echo "y" | ufw enable
    
    # Menginstal fail2ban
    apt install -y fail2ban
    systemctl enable fail2ban
    systemctl start fail2ban
}

generate_readme() {
    echo "Membuat dokumentasi instalasi..."
    
    cat > /root/INSTALLATION.md <<EOF
# Informasi Instalasi Web Server

## Layanan yang Terinstal
$(systemctl list-units --type=service --state=active | grep -E 'nginx|apache|mysql|php|redis|rabbitmq|memcached' | awk '{print "- " $1}')

## Versi PHP yang Terinstal
$(php -v | head -n 1)

## Kredensial MySQL
- Root Password tersimpan di: /root/.my.cnf
- User Database: $mysql_user

## URL Akses
- phpMyAdmin: http://your-ip/phpmyadmin
- Web Root: /var/www/html

## Lokasi File Konfigurasi Penting
- Nginx: /etc/nginx/sites-available/default
- PHP-FPM: /etc/php/*/fpm/php.ini
- MySQL: /etc/mysql/mysql.conf.d/mysqld.cnf

## Backup
- Lokasi backup: /var/backups/
- Schedule: Setiap hari jam 2 pagi
- Retensi: 7 hari

## Monitoring
- Netdata: http://your-ip:19999

## Keamanan
- UFW Firewall aktif
- Fail2ban terinstal
- SSH root login dinonaktifkan
EOF
}

# Tambahkan fungsi untuk penanganan error yang lebih detail
handle_error() {
    local line=$1
    local command=$2
    local error_code=$3
    echo "Error pada baris ${line}: Command '${command}' gagal dengan kode ${error_code}"
    logger -t install_stack "[FATAL] Error pada baris ${line}: ${command} (${error_code})"
    exit 1
}

trap 'handle_error ${LINENO} "$BASH_COMMAND" "$?"' ERR

validate_domain() {
    local domain=$1
    if [[ ! $domain =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9]\.[a-zA-Z]{2,}$ ]]; then
        echo "Domain tidak valid"
        return 1
    fi
    return 0
}

# Gunakan dalam fungsi yang memerlukan domain
read -p "Masukkan domain: " domain
while ! validate_domain "$domain"; do
    read -p "Masukkan domain yang valid: " domain
done

# Tambahkan fungsi progress yang lebih detail
log_progress() {
    local step=$1
    local total=$2
    local message=$3
    echo -ne "\r[${step}/${total}] ${message}"
    logger -t install_stack "[PROGRESS] ${message}"
}

# Contoh penggunaan:
install_lemp() {
    local total_steps=4
    log_progress 1 $total_steps "Menginstal Nginx..."
    apt install -y nginx
    
    log_progress 2 $total_steps "Menginstal PHP-FPM..."
    apt install -y php8.3-fpm
    
    # dst...
}

backup_system() {
    local backup_dir="/var/backups/system_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    # Backup konfigurasi
    tar -czf "$backup_dir/etc.tar.gz" /etc/nginx /etc/php /etc/mysql
    
    # Backup database
    mysqldump --all-databases > "$backup_dir/all_databases.sql"
    
    # Backup website
    tar -czf "$backup_dir/www.tar.gz" /var/www
    
    echo "Backup tersimpan di: $backup_dir"
}

check_system_health() {
    echo "Memeriksa kesehatan sistem..."
    
    # Cek penggunaan CPU
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}')
    
    # Cek penggunaan RAM
    local ram_usage=$(free | grep Mem | awk '{print $3/$2 * 100.0}')
    
    # Cek disk usage
    local disk_usage=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
    
    # Cek status layanan
    local services=("nginx" "mysql" "php8.1-fpm" "redis-server")
    for service in "${services[@]}"; do
        systemctl is-active --quiet "$service" || echo "Peringatan: $service tidak berjalan"
    done
}

setup_auto_update() {
    cat > /etc/cron.daily/stack-update <<'EOF'
#!/bin/bash
apt update
apt upgrade -y
apt autoremove -y
apt clean

# Update composer packages
find /var/www -name composer.json -execdir composer update \;

# Restart layanan jika diperlukan
systemctl restart php8.1-fpm nginx mysql
EOF
    chmod +x /etc/cron.daily/stack-update
}

# Pastikan `openssl` terinstal sebelum digunakan
check_openssl() {
    if ! command -v openssl &> /dev/null; then
        echo "OpenSSL tidak ditemukan, menginstal..."
        apt-get install -y openssl
    fi
}

# Panggil fungsi ini di awal skrip
check_openssl

# Validasi input password MySQL
read -s -p "Masukkan password MySQL baru: " mysql_pass
while [[ -z "$mysql_pass" ]]; do
    echo "Password tidak boleh kosong."
    read -s -p "Masukkan password MySQL baru: " mysql_pass
done
echo

# Pastikan `bc` terinstal sebelum digunakan
check_bc() {
    if ! command -v bc &> /dev/null; then
        echo "BC tidak ditemukan, menginstal..."
        apt-get install -y bc
    fi
}

# Panggil fungsi ini di awal skrip
check_bc

# Pastikan `logger` terinstal sebelum digunakan
check_logger() {
    if ! command -v logger &> /dev/null; then
        echo "Logger tidak ditemukan, menginstal..."
        apt-get install -y bsdutils
    fi
}

# Panggil fungsi ini di awal skrip
check_logger

# Jalankan fungsi main jika script dijalankan langsung (bukan di-source)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi