# Raspberry Pi Ad Blocker 
**A black hole for ads, hence Pi-hole**

![Pi-hole](http://www.hdwallpapersimages.com/wp-content/uploads/2014/03/Black-Hole-Images-540x303.jpg)

The Pi-hole is a DNS/Web server that will **block ads for any device**.

## Coverage
Featured on [MakeUseOf](http://www.makeuseof.com/tag/adblock-everywhere-raspberry-pi-hole-way/) and [Lifehacker](http://lifehacker.com/turn-a-raspberry-pi-into-an-ad-blocker-with-a-single-co-1686093533)!

## Automated Install
On a clean installation of Raspbian, you can run this command to **auto-install the Pi-hole**.  Once installed, configure any device to use the Raspberry Pi as your DNS server and the ads will be blocked.

```curl -s "https://raw.githubusercontent.com/jacobsalmela/pi-hole/master/automated%20install/basic-install.sh" | bash```

## Gravity
The [gravity-adv.sh](https://github.com/jacobsalmela/pi-hole/blob/master/gravity-adv.sh) does most of the magic.  The script pulls in ad domains from many sources and compiles them into a single list of [over 120,000 entries](http://jacobsalmela.com/blocking-ads-from-120000-domains/).

## Whitelist and blacklist
You can add a whitelist or blacklist in ```/etc/pihole/``` and the script will apply those files automatically.

## Other Operating Systems
This script will work for other UNIX-like systems with some slight **modifications**.  As long as you can install dnsmasq and a Webserver, it should work OK.  The automated install only works for a clean install of Raspiban right now since that is how the project originated.

## Optimizations
I am working on some great optimizations to allow the script to run much faster.  I also have a bunch of new sources for ad domains but I still need to see if the lists are OK.
