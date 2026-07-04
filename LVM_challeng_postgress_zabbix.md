
# LVM , postgres and Zabbix server installation and my challengs.
## In this sampel we are going to explore some exciting commands! First we must add a new storage to our virtual machine. I'm using UTM and ubuntu 24.04 so I added the new space with UTM.
## After that, they asked us ( respecdetly :D ) to create a Logical voloum using LVM. Next we are going to install postgress and run a Zabbix server. Here I h've had installed Ngingx as Web Server already.
### First setep , Fdisk and LVM 

## Exploring present storage system using lsblk

```bash
lsblk
```

### This command show you your current storage architecure : 

```text
NAME            MAJ:MIN RM  SIZE RO TYPE MOUNTPOINTS
vda             253:0    0   40G  0 disk
├─vda1          253:1    0    1G  0 part /boot
├─vda2          253:2    0    2G  0 part
│ └─ubuntu-vg-root
│               252:0    0   37G  0 lvm /
vdb             253:16   0   20G  0 disk
```
## Reformating the partion using fdisk

```bash
sudo fdisk /dev/vdb
```

```
n
p
1

<Enter>

<Enter>

t
8e

w
```
- `n` → new partition
- `p` → primary partition
- `1` → partition number
- Enter → first available sector
- Enter → last available sector (use whole disk)
- `t` → change partition type
- `8e` → Linux LVM (on MBR partition tables)
- `w` → write changes and exit

### Now we are going to check the new partion 


## Verify the partition

```bash
lsblk
```

Output:

```text
vdb
└── vdb1
```

---

### So everything is fine! let's 
### Let's use LVM and create our physical volume first 

```bash
sudo pvcreate /dev/vdb1
```

Output:

```text
Physical volume "/dev/vdb1" successfully created.
```
## Create a Volume Group


```bash
sudo vgcreate data-vg /dev/vdb1
```

Output:

```text
Volume group "data-vg" successfully created
```

## Verify:

```bash
sudo vgs
```

Output:

```text
VG       #PV #LV #SN Attr   VSize  VFree
data-vg    1   0   0 wz--n- 20.00g 20.00g
```

---


## Create a Logical Volume

Use the entire VG:

```bash
sudo lvcreate -l 100%FREE -n data-lv data-vg
```

Output:

```text
Logical volume "data-lv" created.
```

Verify:

```bash
sudo lvs
```

Output:

```text
LV      VG      Attr       LSize
data-lv data-vg -wi-a----- 20.00g
```

---
## Last command to make it mountable 

```bash
sudo mkfs.ext4 /dev/data-vg/data-lv
```

## So now we have a voulum which is mountable for out data directory. Next , I installed postgresql and after that I assign the generated partion for it's data. 

```bash
sudo apt install postgresql postgresql-contrib
```
## After installing postgresql , First I stop the dataBase with systemCtl and made it ready for migration. 

```bash
systemctl status postgresql
systemctl disable --now postgresql

```
## The next code will show you postgres data directory which was used when it was active.

```bash

sudo -u postgres psql -c "SHOW data_directory;"

```

## Now we are going to moung our new partion and change postgres data direcoty.
## So we use rsync to copy evething inside postgres prevois data directory and also keep a backup.

```bash
mkdir /mnt/tem_new_pg
mount /dev/data-vg/data-lv /mnt/tem_new_pg/
rsync -aHAX /var/lib/postgresql/ /mnt/tem_new_pg/
mv /var/lib/postgresql /var/lib/postgresql.bk
mkdir /var/lib/postgresql
umount /mnt/tem_new_pg 
mount /dev/dat-vg/data-lv /var/lib/postgres

```

## No we are going to make our postgres ready 

```bash

chown -R postgres:postgres /var/lib/postgresql
systemctl status postgresql
systemctl enable postgresql

```
## To check everything is fine , we can use df to check our disk health. also with blkid we are going to get the UUID of our storage. We are going to add it's UUID to fstab which will mount automatically our storage space in next reboot.

# Installing Zabbix sever 

### In next part I installed the zabbix server for nginx. I had to first get the deb with wget

```bash

wget https://repo.zabbix.com/zabbix/7.0/ubuntu-arm64/pool/main/z/zabbix-release/zabbix-release_latest_7.0+ubuntu24.04_all.deb
dpkg -i zabbix-release_latest_7.0+ubuntu24.04_all.deb 

```

### Tips : make sure to download the compatible version with yout ubuntu and your CPU architecure.

### After build the installer , we are going to install Zabbix 
### I'm going to install the server compatible with my nginx.

```bash
sudo dpkg -i zabbix-release_latest_7.0+ubuntu24.04_all.deb
sudo apt install zabbix-server-pgsql
zabbix-frontend-php
zabbix-nginx-conf
zabbix-sql-scripts
zabbix-agent2

```

```bash

zcat /usr/share/zabbix-sql-scripts/postgresql/server.sql.gz | psql -U zabbix -d zabbix

```

```bash
/etc/zabbix/zabbix_server.conf

```
## Set 
```bash
DBHost=localhost
DBName=zabbix
DBUser=zabbix
DBPassword=StrongPasswordHere
```

## After that , we are going to add our Zabbix and connect to our postgres 

```bash
eSQL:

CREATE USER zabbix WITH PASSWORD 'YourStrongPassword';
CREATE DATABASE zabbix OWNER zabbix;
\q

```


## Fist challnge : 
## I wanted to see Zabbix dashboard on my localhost/Zabbix address. for make it work with nginx , first I disabled the Zabbix.conf and added a new location inside mu nginx config
## The code is : 

```bash
sudo mv /etc/nginx/conf.d/zabbix.conf /etc/nginx/conf.d/zabbix.conf.disabled

```
## Adding new config with vim in nginx.conf

```bash

location /zabbix {
    alias /usr/share/zabbix;
    index index.php;

    location ~ ^/zabbix/(.+\.php)$ {
        alias /usr/share/zabbix/$1;

        fastcgi_pass unix:/var/run/php/zabbix.sock;
        fastcgi_index index.php;
        include fastcgi_params;

        fastcgi_param SCRIPT_FILENAME /usr/share/zabbix/$1;
        fastcgi_param DOCUMENT_ROOT /usr/share/zabbix;
    }

    location ~ ^/zabbix/(.+\.(css|js|png|jpg|gif|svg|ico))$ {
        alias /usr/share/zabbix/$1;
    }

    try_files $uri $uri/ /zabbix/index.php;
}

```

## nginx -t to test new config and after that , enable all services using systemctl and restart them

## Boom! now we can see our dashboard installation in /localhost/Zabbix

## Second challenge in installing dashboard : 
## In my installation I had issue with connecting to my database. After some reasearch and asking from Gpt , the final values for host and port was this :

Database host: 127.0.0.1
Port: 5432

<img width="1510" height="850" alt="Screenshot 2026-07-04 at 4 05 19 PM" src="https://github.com/user-attachments/assets/9a66975b-5996-4fd9-b3b9-34e69d28927a" />





## Question : Why using LVM ? 

With LVM

LVM adds a layer of abstraction.

Physical Disk
      │
      ▼
Physical Volume (PV)
      │
      ▼
Volume Group (VG)
      │
      ├───────────────┐
      ▼               ▼
Logical Volume     Logical Volume
      │               │
      ▼               ▼
Filesystem       Filesystem

Instead of partitions owning fixed sizes, all storage goes into a pool (the Volume Group), and Logical Volumes are created from that pool.
