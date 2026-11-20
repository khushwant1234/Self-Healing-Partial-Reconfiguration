# PYNQ-Z2 board setup (first time)

## 1. SD card
If the board came with a card, try it first (step 3 tells us the version).
Otherwise: pynq.io → Boards → PYNQ-Z2 → download the **v2.7** image (matches
Vivado 2020.2), flash it with balenaEtcher onto an SD card of 8 GB or more.

## 2. Jumpers and cables
* JP1 (boot, near the SD slot): **SD**
* J9 (power source): **USB** for micro-USB power, **REG** for a 12 V adapter
* Micro-USB to the Mac (power and serial console)
* Ethernet: to your router (easiest), or straight to the Mac via a USB-C
  Ethernet adapter

Power on. The red DONE LED lights within about a minute. When Linux is up, the
4 green LEDs flash and turn off.

## 3. Connect
**Serial (no network needed):**
```
ls /dev/tty.usbserial*          # expect ...A and ...B
screen /dev/tty.usbserial-*B 115200
```
Press Enter. Log in as `xilinx` / `xilinx`. Run `ip addr show eth0` to get the
IP. Exit screen with Ctrl-A, K, Y.

**Network:**
* Router: use that IP, or try `ping pynq.local`.
* Direct cable: the board defaults to 192.168.2.99. On the Mac, set the
  Ethernet adapter to Manual with IP 192.168.2.1 and mask 255.255.255.0.

Then `ssh xilinx@<ip>`. Jupyter is at `http://<ip>:9090` (password `xilinx`).

## 4. Identify the image: paste all output back
```
cat /etc/os-release; uname -r; cat /sys/class/fpga_manager/fpga0/state; ls /sys/class/fpga_manager/fpga0/ /lib/firmware
```
```
sudo bash -c 'source /etc/profile.d/pynq_venv.sh 2>/dev/null; python3 -c "import pynq, inspect, sys; print(\"pynq\", pynq.__version__, \"| python\", sys.version.split()[0]); print(inspect.signature(pynq.Bitstream.__init__)); print(inspect.signature(pynq.Overlay.__init__)); print(hasattr(pynq.Overlay, \"pr_download\"))"; python3 -m pip list 2>/dev/null | grep -iE "pynq|numpy|ipywidgets|scipy"'
```
```
df -h /; free -m
```

## 5. Getting the repo onto the board
Easiest: `git clone` the private repo on the board (needs a GitHub token or
deploy key on the board). Alternative from the Mac:
```
scp -r bitstreams/m0 pynq/ xilinx@<ip>:~/selfheal/
```
