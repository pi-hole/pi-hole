# Automated Install 
##### Designed For Raspberry Pi B, B+, 2, and Zero (with an Ethernet adapter)

1. Install Raspbian 
2. Run the command below

### ```curl -L install.pi-hole.net | bash```

Once installed, [configure your router to have **DHCP clients use the Pi as their DNS server**](http://pi-hole.net/faq/can-i-set-the-pi-hole-to-be-the-dns-server-at-my-router-so-i-dont-have-to-change-settings-for-my-devices/) and then any device that connects to your network will have ads blocked without any further configuration.  Alternatively, you can manually set each device to [use the Raspberry Pi as its DNS server](http://pi-hole.net/faq/how-do-i-use-the-pi-hole-as-my-dns-server/).

## Pi-hole Is Free, But Powered By Your Donations
[![Donate](https://www.paypalobjects.com/en_US/i/btn/btn_donateCC_LG.gif "Free, but powered by donations")](https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=3J2L3Z4DHW9UY "Donate")

## How Does It Work?
**Watch the 60-second video below to get a quick overview**

[![Pi-hole exlplained](http://i.imgur.com/qNybJDX.png)](https://vimeo.com/135965232)

## Pi-hole Projects
- [Sky-Hole](http://dlaa.me/blog/post/skyhole)
- [Pi-hole in the Cloud!](http://blog.codybunch.com/2015/07/28/Pi-Hole-in-the-cloud/)
- [unRaid-hole](https://github.com/spants/unraidtemplates/blob/master/Spants/unRaid-hole.xml#L13)--[Repo and more info](http://lime-technology.com/forum/index.php?PHPSESSID=c0eae3e5ef7e521f7866034a3336489d&topic=38486.0)
- [Pi-hole on/off button](http://thetimmy.silvernight.org/pages/endisbutton/)

## Coverage
- [Medium: Block All Ads For $53](https://medium.com/@robleathern/block-ads-on-all-home-devices-for-53-18-a5f1ec139693#.gj1xpgr5d)
- [MakeUseOf: Adblock Everywhere, The Pi-hole Way](http://www.makeuseof.com/tag/adblock-everywhere-raspberry-pi-hole-way/)
- [Lifehacker: Turn Your Pi Into An Ad Blocker With A Single Command](http://lifehacker.com/turn-a-raspberry-pi-into-an-ad-blocker-with-a-single-co-1686093533)!
- [Pi-hole on TekThing](https://youtu.be/8Co59HU2gY0?t=2m)
- [Pi-hole on Security Now! Podcast](http://www.youtube.com/watch?v=p7-osq_y8i8&t=100m26s)

## Partnering With Optimal.com

Pi-hole will be teaming up with [Rob Leathern's subscription service to avoid ads](https://medium.com/@robleathern/block-ads-on-all-home-devices-for-53-18-a5f1ec139693#.gj1xpgr5d).  This service is unique and will help content-creators and publishers [still make money from visitors who are using an ad ablocker](http://techcrunch.com/2015/12/17/the-new-optimal/).

## Technical Details

The Pi-hole is an **advertising-aware DNS/Web server**.  If an ad domain is queried, a small Web page or GIF is delivered in place of the advertisement.

A more detailed explanation of the installation can be found [here](http://jacobsalmela.com/block-millions-ads-network-wide-with-a-raspberry-pi-hole-2-0).

## Gravity
The [gravity.sh](https://github.com/jacobsalmela/pi-hole/blob/master/gravity.sh) does most of the magic.  The script pulls in ad domains from many sources and compiles them into a single list of [over 1.6 million entries](http://jacobsalmela.com/block-millions-ads-network-wide-with-a-raspberry-pi-hole-2-0) (if you decide to use the [mahakala list](https://github.com/jacobsalmela/pi-hole/commit/963eacfe0537a7abddf30441c754c67ca1e40965)).

## Whitelist and blacklist
You can add a `whitelist.txt` or `blacklist.txt` in `/etc/pihole/` and the script will apply those files automatically.  Put one domain per line.

## Web Interface
The [Web interface](https://github.com/jacobsalmela/AdminLTE#pi-hole-admin-dashboard) will be installed automatically so you can view stats and change settings.  You can find it at:

`http://192.168.1.x/admin/index.php`

![Web](http://i.imgur.com/m114SCn.png)

## Help
- See the [Wiki](https://github.com/jacobsalmela/pi-hole/wiki/Customization) entry for more details
- There is also an [FAQ section on pi-hole.net](http://pi-hole.net)

## Other Operating Systems
This script will work for other UNIX-like systems with some slight **modifications**.  As long as you can install `dnsmasq` and a Webserver, it should work OK.  The automated install only works for a clean install of Raspiban right now since that is how the project originated.
