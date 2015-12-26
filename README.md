# Automated Install 
#### Designed For Raspberry Pi B, B+, 2,
##### and Zero (with an Ethernet adapter)

1. Install Raspbian 
2. Run the command below

### ```curl -L install.pi-hole.net | bash```

![Pi-hole automated installation](http://i.imgur.com/Un7lBlj.png)

Once installed, **configure any device to use the Raspberry Pi as its DNS server and the ads will be blocked**.  You can also configure your router's DHCP options to assign the Pi as clients DNS server so they do not need to do it manually.  

[![Donate](https://www.paypalobjects.com/en_US/i/btn/btn_donateCC_LG.gif "AdminLTE Presentation")](https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=3J2L3Z4DHW9UY "Donate")

# How Does It Work?
**Watch the 60-second video below to get a quick overview**

[![Pi-hole exlplained](http://i.imgur.com/wd5ltCU.png)](https://vimeo.com/135965232)

## Video Coverage

### TekThing

Pi-hole is mentioned at the two minute mark

[![Pi-hole on TekThing](http://img.youtube.com/vi/8Co59HU2gY0/0.jpg)](https://youtu.be/8Co59HU2gY0?t=2m)

### Security Now! Podcast
Pi-hole is mentioned at 100 minutes and 26 seconds (the link brings you right there)
[![Pi-hole on Security Now!](http://img.youtube.com/vi/p7-osq_y8i8/0.jpg)](http://www.youtube.com/watch?v=p7-osq_y8i8&t=100m26s)

### Tech Blogs

Pi-hole has been written about on:

- [Medium](https://medium.com/@robleathern/block-ads-on-all-home-devices-for-53-18-a5f1ec139693#.gj1xpgr5d)
- [MakeUseOf](http://www.makeuseof.com/tag/adblock-everywhere-raspberry-pi-hole-way/)
- [Lifehacker](http://lifehacker.com/turn-a-raspberry-pi-into-an-ad-blocker-with-a-single-co-1686093533)!

## Partnering With Optimal.com

Pi-hole will be teaming up with [Rob Leathern's subscription service to avoid ads](https://medium.com/@robleathern/block-ads-on-all-home-devices-for-53-18-a5f1ec139693#.gj1xpgr5d).  This service is unique and will help content-creators and publishers [still make money from visitors who are using an ad ablocker](http://techcrunch.com/2015/12/17/the-new-optimal/).


## Technical Details

A more detailed explanation of the installation can be found [here](http://jacobsalmela.com/block-millions-ads-network-wide-with-a-raspberry-pi-hole-2-0).

## Gravity
The [gravity.sh](https://github.com/jacobsalmela/pi-hole/blob/master/gravity.sh) does most of the magic.  The script pulls in ad domains from many sources and compiles them into a single list of [over 1.6 million entries](http://jacobsalmela.com/block-millions-ads-network-wide-with-a-raspberry-pi-hole-2-0).

## Whitelist and blacklist
You can add a `whitelist.txt` or `blacklist.txt` in `/etc/pihole/` and the script will apply those files automatically.

## Web Interface
The [Web interface](https://github.com/jacobsalmela/AdminLTE#pi-hole-admin-dashboard) will be installed automatically so you can view stats and change settings.  You can find it at:

`http://192.168.1.x/admin/index.php`

![Web](http://i.imgur.com/m114SCn.png)

##  Custom Config File
If you want to use your own variables for the gravity script (i.e. storing the files in a different location) and don't want to have to change them every time there is an update to the script, create a file called `/etc/pihole/pihole.conf`. In it, you should add your own variables in a similar fashion as shown below:

```
piholeDir=/var/run/pihole
adList=/etc/dnsmasq.d/adList
```

See the [Wiki](https://github.com/jacobsalmela/pi-hole/wiki/Customization) entry for more details.

### How It Works
A technical and detailed description can be found [here](http://jacobsalmela.com/block-millions-ads-network-wide-with-a-raspberry-pi-hole-2-0)!

## Other Operating Systems
This script will work for other UNIX-like systems with some slight **modifications**.  As long as you can install `dnsmasq` and a Webserver, it should work OK.  The automated install only works for a clean install of Raspiban right now since that is how the project originated.

### Examples Of The Pi-hole On Other Operating Systems
- [Sky-Hole](http://dlaa.me/blog/post/skyhole)
- [Pi-hole in the Cloud!](http://blog.codybunch.com/2015/07/28/Pi-Hole-in-the-cloud/)

[![Donate](https://www.paypalobjects.com/en_US/i/btn/btn_donateCC_LG.gif "AdminLTE Presentation")](https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=3J2L3Z4DHW9UY "Donate")
