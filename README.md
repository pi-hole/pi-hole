# Raspberry Pi Ad Blocker 
**A black hole for ads, hence Pi-hole**

![Pi-hole](http://i.imgur.com/wd5ltCU.png)

The Pi-hole is a DNS/Web server that will **block ads for any device on your network**.

## Coverage
Featured on [MakeUseOf](http://www.makeuseof.com/tag/adblock-everywhere-raspberry-pi-hole-way/) and [Lifehacker](http://lifehacker.com/turn-a-raspberry-pi-into-an-ad-blocker-with-a-single-co-1686093533)!

## Automated Install
### Make sure to set a **static** IP address before running this!!
On a clean installation of Raspbian, you can run this command to **auto-install the Pi-hole**.  Once installed, configure any device to use the Raspberry Pi as your DNS server and the ads will be blocked.

```curl -s "https://raw.githubusercontent.com/jacobsalmela/pi-hole/master/automated%20install/basic-install.sh" | bash```

## Gravity
The [gravity.sh](https://github.com/jacobsalmela/pi-hole/blob/master/gravity.sh) does most of the magic.  The script pulls in ad domains from many sources and compiles them into a single list of [over 900,000 entries](http://jacobsalmela.com/block-millions-ads-network-wide-with-a-raspberry-pi-hole-2-0).

## Whitelist and blacklist
You can add a `whitelist.txt` or `blacklist.txt` in `/etc/pihole/` and the script will apply those files automatically.

### How It Works
A technical and detailed description can be found [here](http://jacobsalmela.com/block-millions-ads-network-wide-with-a-raspberry-pi-hole-2-0)!

## Other Operating Systems
This script will work for other UNIX-like systems with some slight **modifications**.  As long as you can install `dnsmasq` and a Webserver, it should work OK.  The automated install only works for a clean install of Raspiban right now since that is how the project originated.