5.4.23-1-MANJARO 

1. download linux-5.4.23 and cp /lib/modules/5.4.23-MANJARO/build
 * vermagic diff
 * modprobe --force-vermagic, not work

kernel header : https://gitlab.manjaro.org/packages/core/linux54/-/tree/7f2067fdfa11b911e07432357b206a2f4a3736f7
 - not clone, download only
 makepkg

1. https://github.com/abperiasamy/rtl8812AU_8821AU_linux
=>panic, not load
2. https://github.com/gnab/rtl8812au.git
make
sudo make install
ip link => interface good
