# Automated Install 
##### Designed For Raspberry Pi A+, B, B+, 2, and Zero (with an Ethernet/Wi-Fi adapter)

[![Join the chat at https://gitter.im/pi-hole/pi-hole](https://badges.gitter.im/pi-hole/pi-hole.svg)](https://gitter.im/pi-hole/pi-hole?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge)

1. Install Raspbian 
2. Run the command below

### ```curl -L https://install.pi-hole.net | bash```

#### Alternative Semi-Automated install ####
```
wget -O basic-install.sh https://install.pi-hole.net
chmod +x basic-install.sh
./basic-install.sh
```

Once installed, [configure your router to have **DHCP clients use the Pi as their DNS server**](http://pi-hole.net/faq/can-i-set-the-pi-hole-to-be-the-dns-server-at-my-router-so-i-dont-have-to-change-settings-for-my-devices/) and then any device that connects to your network will have ads blocked without any further configuration.  Alternatively, you can manually set each device to [use the Raspberry Pi as its DNS server](http://pi-hole.net/faq/how-do-i-use-the-pi-hole-as-my-dns-server/).

## Pi-hole Is Free, But Powered By Your Donations
[![Donate](https://www.paypalobjects.com/en_US/i/btn/btn_donateCC_LG.gif "Free, but powered by donations")](https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=3J2L3Z4DHW9UY "Donate")

## Catch us out on the net:
Twitter: [@The_Pi_Hole](https://twitter.com/The_Pi_Hole)

reddit: [/r/pihole](https://www.reddit.com/r/pihole/)

## How Does It Work?
**Watch the 60-second video below to get a quick overview**

[![Pi-hole exlplained](http://i.imgur.com/qNybJDX.png)](https://vimeo.com/135965232)

## Pi-hole Projects
- [Get LED alerts for each blocked ad](http://www.stinebaugh.info/get-led-alerts-for-each-blocked-ad-using-pi-hole/)
- [Pi-hole on Ubuntu 14.04 on VirtualBox](http://hbalagtas.blogspot.com/2016/02/adblocking-with-pi-hole-and-ubuntu-1404.html)
- [x86 Docker container that runs Pi-hole](https://hub.docker.com/r/diginc/pi-hole/)
- [Splunk: Pi-hole Visualizser](https://splunkbase.splunk.com/app/3023/)
- [Pi-hole Chrome extension](https://chrome.google.com/webstore/detail/pi-hole-list-editor/hlnoeoejkllgkjbnnnhfolapllcnaglh) ([open source](https://github.com/packtloss/pihole-extension))
- [Go Bananas for CHiP-hole ad blocking](https://www.hackster.io/jacobsalmela/chip-hole-network-wide-ad-blocker-98e037)
- [Sky-Hole](http://dlaa.me/blog/post/skyhole)
- [Pi-hole in the Cloud!](http://blog.codybunch.com/2015/07/28/Pi-Hole-in-the-cloud/)
- [unRaid-hole](https://github.com/spants/unraidtemplates/blob/master/Spants/unRaid-hole.xml#L13)--[Repo and more info](http://lime-technology.com/forum/index.php?PHPSESSID=c0eae3e5ef7e521f7866034a3336489d&topic=38486.0)
- [Pi-hole on/off button](http://thetimmy.silvernight.org/pages/endisbutton/)
- [Minibian Pi-hole](http://munkjensen.net/wiki/index.php/See_my_Pi-Hole#Minibian_Pi-hole)

## Coverage
- [TekThing: 5 fun, easy projects for a Raspberry Pi](https://youtu.be/QwrKlyC2kdM?t=1m42s)
- [Pi-hole on Adafruit's blog](https://blog.adafruit.com/2016/03/04/pi-hole-is-a-black-hole-for-internet-ads-piday-raspberrypi-raspberry_pi/)
- [The Defrag Show - MSDN/Channel 9](https://channel9.msdn.com/Shows/The-Defrag-Show/Defrag-Endoscope-USB-Camera-The-Final-HoloLens-Vote-Adblock-Pi-and-more?WT.mc_id=dlvr_twitter_ch9#time=20m39s)
- [MacObserver Podcast 585](http://www.macobserver.com/tmo/podcast/macgeekgab-585)
- [Medium: Block All Ads For $53](https://medium.com/@robleathern/block-ads-on-all-home-devices-for-53-18-a5f1ec139693#.gj1xpgr5d)
- [MakeUseOf: Adblock Everywhere, The Pi-hole Way](http://www.makeuseof.com/tag/adblock-everywhere-raspberry-pi-hole-way/)
- [Lifehacker: Turn Your Pi Into An Ad Blocker With A Single Command](http://lifehacker.com/turn-a-raspberry-pi-into-an-ad-blocker-with-a-single-co-1686093533)!
- [Pi-hole on TekThing](https://youtu.be/8Co59HU2gY0?t=2m)
- [Pi-hole on Security Now! Podcast](http://www.youtube.com/watch?v=p7-osq_y8i8&t=100m26s)
- [Foolish Tech Show](https://youtu.be/bYyena0I9yc?t=2m4s)
- [Pi-hole on Ubuntu](http://www.boyter.org/2015/12/pi-hole-ubuntu-14-04/)
- [Catchpoint: iOS 9 Ad Blocking](http://blog.catchpoint.com/2015/09/14/ad-blocking-apple/)

## Partnering With Optimal.com

Pi-hole will be teaming up with [Rob Leathern's subscription service to avoid ads](https://medium.com/@robleathern/block-ads-on-all-home-devices-for-53-18-a5f1ec139693#.gj1xpgr5d).  This service is unique and will help content-creators and publishers [still make money from visitors who are using an ad ablocker](http://techcrunch.com/2015/12/17/the-new-optimal/).

## Technical Details

The Pi-hole is an **advertising-aware DNS/Web server**.  If an ad domain is queried, a small Web page or GIF is delivered in place of the advertisement.  You can also [replace ads with any image you want](http://pi-hole.net/faq/is-it-possible-to-change-the-blank-page-that-takes-place-of-the-ads-to-something-else/) since it is just a simple Webpage taking place of the ads.

A more detailed explanation of the installation can be found [here](http://jacobsalmela.com/block-millions-ads-network-wide-with-a-raspberry-pi-hole-2-0).

## Gravity
The [gravity.sh](https://github.com/pi-hole/pi-hole/blob/master/gravity.sh) does most of the magic.  The script pulls in ad domains from many sources and compiles them into a single list of [over 1.6 million entries](http://jacobsalmela.com/block-millions-ads-network-wide-with-a-raspberry-pi-hole-2-0) (if you decide to use the [mahakala list](https://github.com/pi-hole/pi-hole/commit/963eacfe0537a7abddf30441c754c67ca1e40965)).

## Whitelist and blacklist
Domains can be whitelisted and blacklisted using two pre-installed scripts. See [the wiki page](https://github.com/pi-hole/pi-hole/wiki/Whitelisting-and-Blacklisting) for more details

## Web Interface
The [Web interface](https://github.com/jacobsalmela/AdminLTE#pi-hole-admin-dashboard) will be installed automatically so you can view stats and change settings.  You can find it at:

`http://192.168.1.x/admin/index.php`

![Pi-hole Advanced Stats Dashboard](http://i.imgur.com/rTlLYPh.png)

### API

A basic read-only API can be accessed at `/admin/api.php`. It returns the following JSON:
```JSON
{
	"domains_being_blocked": "136708",
	"dns_queries_today": "18108",
	"ads_blocked_today": "14648",
	"ads_percentage_today": "80.89"
}
```
The same output can be acheived on the CLI by running `chronometer.sh -j`

![Web](http://i.imgur.com/m114SCn.png)

## Real-time Statistics

You can view [real-time stats](http://pi-hole.net/faq/install-the-real-time-lcd-monitor-chronometer/) via `ssh` or on an [2.8" LCD screen](http://amzn.to/1P0q1Fj).  This is accomplished via [`chronometer.sh`](https://github.com/pi-hole/pi-hole/blob/master/advanced/Scripts/chronometer.sh).
![Pi-hole LCD](http://i.imgur.com/nBEqycp.jpg)

## Help
- See the [Wiki](https://github.com/pi-hole/pi-hole/wiki/Customization) entry for more details
- There is also an [FAQ section on pi-hole.net](http://pi-hole.net)

## Other Operating Systems
This script will work for other UNIX-like systems with some slight **modifications**.  As long as you can install `dnsmasq` and a Webserver, it should work OK.  The automated install is only for a clean install of a Debian based system, such as the Raspberry Pi.
