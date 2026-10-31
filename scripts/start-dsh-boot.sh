#!/data/data/com.termux/files/usr/bin/sh
H=/data/data/com.termux/files/home
echo "boot $(date +%T) FOREGROUND_HOLD" >> $H/boot_dsh.log
exec sh $H/supervise.sh >> $H/supervise.log 2>&1
