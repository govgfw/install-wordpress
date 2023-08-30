#!/bin/bash

#### 请事先准备好你的域名、邮箱、设置好域名解析到本服务器
printf "===============================================\n"
printf "|                                             |\n"
printf "|           Ubuntu搭建Wordpress脚本           |\n"
printf "|                                             |\n"
printf "===============================================\n"

read -p "请输入你的域名（例如globeranker.com）：" domain < /dev/tty
read -p "请输入你的邮箱（用于生成SSL，绑定lets encrypt）：" email < /dev/tty
printf "是否创建SSL（如果需要，则请确认你已经配置好了域名解析至本服务器）：\n"
read -p "输入y/Y创建SSL，其它为不创建" needSsl < /dev/tty

echo "domain: ${domain}"
echo "email: ${email}"

install_dir="/var/www/html"
access_log_dir="/var/log/apache2/wp-access.log"
error_log_dir="/var/log/apache2/wp-error.log"

#### 随机生成WordPress数据库用户名和密码
db_name="wp`date +%s`"
db_user=$db_name
db_password=`date |md5sum |cut -c '1-12'`
sleep 1
mysqlrootpass=`date |md5sum |cut -c '1-12'`
sleep 1


#### 安装http和mysql
apt -y update
apt -y upgrade
apt -y install apache2
apt -y install mysql-server


#### 启动http服务
rm $install_dir/index.html
systemctl enable apache2
systemctl start apache2

#### 启动mysql服务，并设置root用户密码
systemctl enable mysql
systemctl start mysql

/usr/bin/mysql -e "USE mysql;"
/usr/bin/mysql -e "UPDATE user SET Password=PASSWORD($mysqlrootpass) WHERE user='root';"
/usr/bin/mysql -e "FLUSH PRIVILEGES;"
touch /root/.my.cnf
chmod 640 /root/.my.cnf
echo "[client]">>/root/.my.cnf
echo "user=root">>/root/.my.cnf
echo "password="$mysqlrootpass>>/root/.my.cnf

#### 安装PHP
apt -y install php php-bz2 php-mysqli php-curl php-gd php-intl php-common php-mbstring php-xml

#### 重启http服务
systemctl restart apache2

#### 从WordPress官网下载最新安装包
if test -f /tmp/latest.tar.gz
then
echo "WP is already downloaded."
else
echo "Downloading WordPress"
cd /tmp/ && wget "http://wordpress.org/latest.tar.gz";
fi

/bin/tar -C $install_dir -zxf /tmp/latest.tar.gz --strip-components=1
chown www-data: $install_dir -R

#### 创建WordPress配置文件，并配置数据库用户名和密码
/bin/mv $install_dir/wp-config-sample.php $install_dir/wp-config.php

/bin/sed -i "s/database_name_here/$db_name/g" $install_dir/wp-config.php
/bin/sed -i "s/username_here/$db_user/g" $install_dir/wp-config.php
/bin/sed -i "s/password_here/$db_password/g" $install_dir/wp-config.php

cat << EOF >> $install_dir/wp-config.php
define('FS_METHOD', 'direct');
EOF


chown www-data: $install_dir -R

##### 设置WordPress官方提供的随机秘钥
grep -A50 'table_prefix' $install_dir/wp-config.php > /tmp/wp-tmp-config
/bin/sed -i '/**#@/,/$p/d' $install_dir/wp-config.php
curl https://api.wordpress.org/secret-key/1.1/salt/ >> $install_dir/wp-config.php
/bin/cat /tmp/wp-tmp-config >> $install_dir/wp-config.php && rm /tmp/wp-tmp-config -f
/usr/bin/mysql -u root -e "CREATE DATABASE $db_name"
/usr/bin/mysql -u root -e "CREATE USER '$db_name'@'localhost' IDENTIFIED WITH mysql_native_password BY '$db_password';"
/usr/bin/mysql -u root -e "GRANT ALL PRIVILEGES ON $db_name.* TO '$db_user'@'localhost';"


##### 配置http服务
echo "<VirtualHost *:80>
    ServerName ${domain}
    ServerAlias www.${domain}
    ServerAdmin webmaster@localhost
    DocumentRoot ${install_dir}
    ErrorLog ${error_log_dir}
    CustomLog ${access_log_dir} combined
    <Directory ${install_dir}>
	    AllowOverride All
    </Directory>
</VirtualHost>" > "/etc/apache2/sites-available/$domain.conf"

sudo a2ensite $domain
sudo a2dissite 000-default && sudo a2enmod rewrite && sudo a2enmod rewrite && sudo apache2ctl configtest && sudo systemctl restart apache2

##### 申请SSL证书
sudo apt install certbot python3-certbot-apache -y
sudo ufw allow 'Apache Full' && sudo ufw delete allow 'Apache'
if  [[ $needSsl == "y" ]] || [[ $needSsl == "Y" ]] ;
then
        sudo certbot --apache --non-interactive --no-eff-email --agree-tos --redirect -m $email --domain $domain --domain "www.$domain"
fi

#### 配置php.ini
echo "Start to replace necessary config from php.ini"
upload_max_filesize=240M
post_max_size=240M
memory_limit=1024M
max_execution_time=600
max_input_time=600
max_input_vars=5000
for i in $(find /etc/ -name php.ini); do # Not recommended, will break on whitespace
    echo "found $i"
    for key in upload_max_filesize post_max_size max_execution_time max_input_time memory_limit max_input_vars
    do
     sed -i "s/^\($key\).*/\1 $(eval echo = \${$key})/" $i
    done
done

#### 重启http服务
sudo systemctl restart apache2

#### WordPress网站关键信息（包含用户名和密码）请妥善保存
if  [[ $needSsl == "y" ]] || [[ $needSsl == "Y" ]] ;
then
        echo "你的网站: " "https://${domain}"
else
        echo "你的网站: " "http://${domain}"
fi

echo "你的SSL绑定邮箱: " $email
echo "数据库名称 Db: " $db_name
echo "数据库用户名 User: " $db_user
echo "数据库密码 Password: " $db_password
echo "Mysql管理员密码 Root Password: " $mysqlrootpass
echo "你的服务器访问记录Apache access log: " $access_log_dir
echo "你的服务器报错记录Apache error log: " $error_log_dir
