<p align="center">
<a href=https://www.bountysource.com/trackers/3011939-pi-hole-pi-hole?utm_source=3011939&utm_medium=shield&utm_campaign=TRACKER_BADGE><img src="https://www.bountysource.com/badge/tracker?tracker_id=3011939"></a>
<a href="https://www.codacy.com/app/Pi-hole/pi-hole?utm_source=github.com&amp;utm_medium=referral&amp;utm_content=pi-hole/pi-hole&amp;utm_campaign=Badge_Grade"><img src="https://api.codacy.com/project/badge/Grade/c558a0f8d7124c99b02b84f0f5564238"/></a>
<a href=https://travis-ci.org/pi-hole/pi-hole><img src="https://travis-ci.org/pi-hole/pi-hole.svg?branch=development"></a>
</p>

<p align="center">
<a href=https://discourse.pi-hole.net><img src="https://assets.pi-hole.net/static/Vortex_with_text_and_TM.png" width=210></a>
</p>

## Pi-hole®: The multi-platform, network-wide ad blocker

Block ads for **all** your devices _without_ the need to install client-side software.

<p align="center">
<a href=http://www.digitalocean.com/?refcode=344d234950e1><img src="https://assets.pi-hole.net/static/DOHostingSlug.png"></a>
</p>

## Executive Summary
The Pi-hole blocks ads at the DNS-level, so all your devices are protected.

- **Easy-to-install** - our intelligent installer walks you through the process with no additional software needed on client devices
- **Universal** - ads are blocked in _non-browser locations_ such as ad-supported mobile apps and smart TVs
- **Quick** - installation takes less than ten minutes and it [_really_ is _that easy_](https://discourse.pi-hole.net/t/new-pi-hole-questions/3971/5?u=jacob.salmela)
- **Informative** - an administrative Web interface shows ad-blocking statistics
- **Lightweight** - designed to run on [minimal resources](https://discourse.pi-hole.net/t/hardware-software-requirements/273)
- **Scalable** - even in large environments, [Pi-hole can handle hundreds of millions of queries](https://pi-hole.net/2017/05/24/how-much-traffic-can-pi-hole-handle/) (with the right hardware specs)
- **Powerful** - advertisements are blocked over IPv4 _and_ IPv6
- **Fast** - it speeds up high-cost, high-latency networks by caching DNS queries and saves bandwidth by not downloading advertisement elements
- **Versatile** -  Pi-hole can function also function as a DHCP server

# One-Step Automated Install
1.  Install a [supported operating system](https://discourse.pi-hole.net/t/hardware-software-requirements/273/1)
2.  Run the command below (it downloads [this script](https://github.com/pi-hole/pi-hole/blob/master/automated%20install/basic-install.sh) in case you want to read over it first!)

#### `curl -sSL https://install.pi-hole.net | bash`

## Alternative Semi-Automated Install Methods
_If you wish to read over the script before running it, run `nano basic-install.sh` to open the file in a text viewer._

### Clone our repository and run the automated installer from your device.

```
git clone --depth 1 https://github.com/pi-hole/pi-hole.git Pi-hole
cd Pi-hole/automated\ install/
bash basic-install.sh
```

##### Or

```bash
wget -O basic-install.sh https://install.pi-hole.net
bash basic-install.sh
```

Once installed, [configure your router to have **DHCP clients use the Pi-hole as their DNS server**](https://discourse.pi-hole.net/t/how-do-i-configure-my-devices-to-use-pi-hole-as-their-dns-server/245) and then any device that connects to your network will have ads blocked without any further configuration.

If your router does not support setting the DNS server, you can [use Pi-hole's built in DHCP server](https://discourse.pi-hole.net/t/how-do-i-use-pi-holes-built-in-dhcp-server-and-why-would-i-want-to/3026); just be sure to disable DHCP on your router first.

Alternatively, you can manually set each device to use Pi-hole as their DNS server.

# What is Pi-hole and how do I install it?
<p align="center">
<a href=https://www.youtube.com/watch?v=vKWjx1AQYgs><img src="https://assets.pi-hole.net/static/video-explainer.png"></a>
</p>

# Pi-hole Is Free, But Powered By Your Donations

[Digital Ocean](http://www.digitalocean.com/?refcode=344d234950e1) helps with our infrastructure, but [our developers](https://github.com/orgs/pi-hole/people) are all volunteers so *your donations help keep us innovating*.

-   ![Paypal](https://assets.pi-hole.net/static/paypal.png) [Donate via PayPal](https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=3J2L3Z4DHW9UY)
-   ![Bitcoin](https://assets.pi-hole.net/static/Bitcoin.png) Bitcoin Address: 1GKnevUnVaQM2pQieMyeHkpr8DXfkpfAtL

## Other Ways To Support Us
### Affiliate Links
If you'd rather not send money, there are [other ways to support us](https://pi-hole.net/donate): you can sign up for services through our affiliate links, which will also help us offset some of the costs associated with keeping Pi-hole operational; or you can support us in some non-tangible ways as listed below.

### Contributing Code Via Pull Requests

We don't work on Pi-hole for monetary reasons; we work on it because we think it's fun and we think our software is important in today's world.  To that end, we welcome all contributors--from novices to masters.

If you feel you have some code to contribute, we're happy to take a look.  Just make sure to fill out our template when submitting a pull request.  We're all volunteers on the project and without all the information in the template, it's very difficult for us to quickly get the code merged in.

You'll find that the [install script](https://github.com/pi-hole/pi-hole/blob/master/automated%20install/basic-install.sh) and the [debug script](https://github.com/pi-hole/pi-hole/blob/master/advanced/Scripts/piholeDebug.sh) have an abundance of comments.  These are two important scripts but we think they can also be a valuable resource to those who want to learn how to write scripts or code a program, which is why they are fully commented.  So we encourage anyone who likes to tinker to read through it and submit a PR for us to review.

### Presenting About Pi-hole

Word-of-mouth has immensely helped our project grow.  If you are going to be presenting about Pi-hole at a conference, meetup, or even for a school project, [get a hold of us for some free swag](https://pi-hole.net/2017/05/17/giving-a-presentation-on-pi-hole-contact-us-first-for-some-goodies-and-support/) to hand out to your audience.

# Overview Of Features

## The Dashboard (Web Interface)

The [dashboard](https://github.com/pi-hole/AdminLTE#pi-hole-admin-dashboard) will (by default) be enabled during installation so you can view stats, change settings, and configure your Pi-hole.

![Pi-hole Dashboard](https://assets.pi-hole.net/static/dashboard.png)

There are several ways to [access the dashboard](https://discourse.pi-hole.net/t/how-do-i-access-pi-holes-dashboard-admin-interface/3168):

1. `http://<IP_ADDPRESS_OF_YOUR_PI_HOLE>/admin/`
2. `http:/pi.hole/admin/` (when using Pi-hole as your DNS server)
3. `http://pi.hole/` (when using Pi-hole as your DNS server)

### The Query Log

If enabled, the query log will show all of the DNS queries requested by clients using Pi-hole as their DNS server.  Forwarded domains will show in green, and blocked (_Pi-holed_) domains will show in red.  You can also white or black list domains from within this section.

<p align="center">
<img src="https://assets.pi-hole.net/static/query_log.png">
</p>

The query log and graphs are what have helped people [discover what sort of traffic is traversing their networks](https://pi-hole.net/2017/07/06/round-3-what-really-happens-on-your-network/).

#### Long-term Statistics
Using our Faster-Than-Light Engine ([FTL](https://github.com/pi-hole/FTL)), Pi-hole can store all of the domains queried in a database for retrieval or analysis later on.  You can view this data as a graph, individual queries, or top clients/advertisers.

<p align="center">
<img src="https://assets.pi-hole.net/static/long-term-stats.png">
</p>

### Whitelist And Blacklist

Domains can be [whitelisted](https://discourse.pi-hole.net/t/commonly-whitelisted-domains/212) and/or [blacklisted](https://discourse.pi-hole.net/t/commonly-blacklisted-domains/305) using either the dashboard or [the `pihole` command](https://discourse.pi-hole.net/t/the-pihole-command-with-examples/738).

<p align="center">
<a href=https://github.com/pi-hole/pi-hole/wiki/Whitelisting-and-Blacklisting><img src="https://assets.pi-hole.net/static/whitelist.png"></a>
</p>

#### Additional Blocklists
By default, Pi-hole blocks over 100,000 known ad-serving domains.  You can expand the blocking power of your Pi-hole by [adding additional lists](https://discourse.pi-hole.net/t/how-do-i-add-additional-block-lists-to-pi-hole/259) such as the ones found on [The Big Blocklist Collection](https://wally3k.github.io/).

<p align="center">
<a href=https://discourse.pi-hole.net/t/how-do-i-add-additional-block-lists-to-pi-hole/259><img src="https://assets.pi-hole.net/static/manage-ad-lists.png"></a>
</p>

### Enable And Disable Pi-hole
Sometimes you may want to stop using Pi-hole or turn it back on.  You can trigger this via the dashboard or command line.

<p align="center">
<img src="https://assets.pi-hole.net/static/enable-disable.png">
</p>

### Tools

<p align="center">
<img src="https://assets.pi-hole.net/static/tools.png">
</p>


#### Update Ad Lists
This runs `gravity` to download any newly-added domains from your source lists.

#### Query Ad Lists
You can find out what list a certain domain was on.  This is useful for troubleshooting sites that may not work properly due to a blocked domain.

#### `tail`ing Log Files
You can [watch the log files](https://discourse.pi-hole.net/t/how-do-i-watch-and-interpret-the-pihole-log-file/276) in real time to help debug any issues, or just see what's happening with your Pi-hole.

#### Pi-hole Debugger
If you are having trouble with your Pi-hole, this is the place to go.  You can run the debugger and it will attempt to diagnose any issues and then link to an FAQ with instructions on rectifying the problem.

<p align="center">
<img src="https://assets.pi-hole.net/static/debug-gui.png">
</p>

If run [via the command line](https://discourse.pi-hole.net/t/the-pihole-command-with-examples/738#debug), you will see red/yellow/green text, which makes it easy to identify any problems.

<p align="center">
<a href=https://discourse.pi-hole.net/t/the-pihole-command-with-examples/738#debugs><img src="https://assets.pi-hole.net/static/debug-cli.png"></a>
</p>


After the debugger has finished, you have the option to upload it to our secure server for 48 hours.  All you need to do then is provide one of our developers the unique token generated by the debugger (this is usually done via [our forums](https://discourse.pi-hole.net/c/bugs-problems-issues)).

<p align="center">
<a href=https://discourse.pi-hole.net/t/the-pihole-command-with-examples/738#debugs><img src="https://assets.pi-hole.net/static/debug-token.png"></a>
</p>

However, most of the time, you will be able to solve any issues without any intervention from us.  But if you can't, we're always around to help out.

### Settings

The settings page lets you control and configure your Pi-hole.  You can do things like:

- view networking information
- flush logs or disable the logging of queries
- [enable Pi-hole's built-in DHCP server](https://discourse.pi-hole.net/t/how-do-i-use-pi-holes-built-in-dhcp-server-and-why-would-i-want-to/3026)
- [manage block lists](https://discourse.pi-hole.net/t/how-do-i-add-additional-block-lists-to-pi-hole/259)
- exclude domains from the graphs and enable privacy options
- configure upstream DNS servers
- restart Pi-hole's services
- back up some of Pi-hole's important files
- and more!

<p align="center">
<img src="https://assets.pi-hole.net/static/settings-page.png">
</p>


## Built-in DHCP Server

Pi-hole ships with a [built-in DHCP server](https://discourse.pi-hole.net/t/how-do-i-use-pi-holes-built-in-dhcp-server-and-why-would-i-want-to/3026).  This allows you to let your network devices use Pi-hole as their DNS server if your router does not let you adjust the DHCP options.

One nice feature of using Pi-hole's DHCP server if you can set hostnames and DHCP reservations so you'll [see hostnames in the query log instead of IP addresses](https://discourse.pi-hole.net/t/how-do-i-show-hostnames-instead-of-ip-addresses-in-the-dashboard/3530).  You can still do this without using Pi-hole's DHCP server; it just takes a little more work.  If you do plan to use Pi-hole's DHCP server, be sure to disable DHCP on your router first.

<p align="center">
<a href=https://discourse.pi-hole.net/t/how-do-i-use-pi-holes-built-in-dhcp-server-and-why-would-i-want-to/3026><img src="https://assets.pi-hole.net/static/piholedhcpserver.png"></a>
</p>

## The FTL Engine: Our API

A read-only API can be accessed at `admin/api.php` (the same output can be achieved on the CLI by running `pihole -c -j`).

It returns the following JSON:
``` json
{
   "domains_being_blocked":111175,
   "dns_queries_today":15669,
   "ads_blocked_today":1752,
   "ads_percentage_today":11.181314,
   "unique_domains":1178,
   "queries_forwarded":9177,
   "queries_cached":4740,
   "unique_clients":18
 }
```

More details on the API can be found [here](https://discourse.pi-hole.net/t/pi-hole-api/1863) and on [the repo itself](https://github.com/pi-hole/FTL).

### Real-time Statistics, Courtesy Of The Time Cops

Using [chronometer2](https://github.com/pi-hole/pi-hole/blob/master/advanced/Scripts/chronometer.sh), you can view [real-time stats](https://discourse.pi-hole.net/t/how-do-i-view-my-pi-holes-stats-over-ssh-or-on-an-lcd-using-chronometer/240) via `ssh` or on an LCD screen such as the [2.8" LCD screen from Adafruit](http://amzn.to/1P0q1Fj).

Simply run `pihole -c` for some detailed information.
```
|¯¯¯(¯)__|¯|_  ___|¯|___        Pi-hole: v3.2
| ¯_/¯|__| ' \/ _ \ / -_)      AdminLTE: v3.2
|_| |_|  |_||_\___/_\___|           FTL: v2.10
 ——————————————————————————————————————————————————————————
  Hostname: pihole              (Raspberry Pi 1, Model B)
    Uptime: 11 days, 12:55:01
 Task Load: 0.35 0.16 0.15      (Active: 5 of 33 tasks)
 CPU usage: 48%                 (1 core @ 700 MHz, 47c)
 RAM usage: 12%                 (Used: 54 MB of 434 MB)
 HDD usage: 20%                 (Used: 1 GB of 7 GB)
  LAN addr: 192.168.1.100       (Gateway: 192.168.1.1)
   Pi-hole: Active              (Blocking: 111175 sites)
 Ads Today: 11%                 (1759 of 15812 queries)
   Fwd DNS: 208.67.222.222      (Alt DNS: 3 others)
 ——————————————————————————————————————————————————————————
 Recently blocked: www.google-analytics.com
   Top Advertiser: www.example.org
       Top Domain: www.example.org
       Top Client: somehost
```

<p align="center">
<img src="https://assets.pi-hole.net/static/chrono1.pn">
</p>

<p align="center">
<img src="https://assets.pi-hole.net/static/chrono2.png">
</p>

# Get Help Or Connect With Us On The Web

-   [Users Forum](https://discourse.pi-hole.net/)
-   [FAQs](https://discourse.pi-hole.net/c/faqs)
-   [Feature requests](https://discourse.pi-hole.net/c/feature-requests?order=votes)
-   [Wiki](https://github.com/pi-hole/pi-hole/wiki)
-   ![Twitter](https://assets.pi-hole.net/static/twitter.png) [Tweet @The_Pi_Hole](https://twitter.com/The_Pi_Hole)
-   ![Reddit](https://assets.pi-hole.net/static/reddit.png) [Reddit /r/pihole](https://www.reddit.com/r/pihole/)
-   ![YouTube](https://assets.pi-hole.net/static/youtube.png)  [Pi-hole channel](https://www.youtube.com/channel/UCT5kq9w0wSjogzJb81C9U0w)
-   [![Join the chat at https://gitter.im/pi-hole/pi-hole](https://badges.gitter.im/pi-hole/pi-hole.svg)](https://gitter.im/pi-hole/pi-hole?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge)

# Technical Details

To summarize into a short sentence, the Pi-hole is an **advertising-aware DNS/Web server**.  And while quite outdated at this point, [this original blog post about Pi-hole](https://jacobsalmela.com/2015/06/16/block-millions-ads-network-wide-with-a-raspberry-pi-hole-2-0/) goes into **great detail** about how it was setup and how it works.  Syntactically, it's no longer accurate, but the same basic principles and logic still apply to Pi-hole's current state.


# Pi-hole Projects

-   [An ad blocking Magic Mirror](https://zonksec.com/blog/magic-mirror-dns-filtering/#dnssoftware)
-   [Pi-hole stats in your Mac's menu bar](https://getbitbar.com/plugins/Network/pi-hole.1m.py)
-   [Get LED alerts for each blocked ad](http://thetimmy.silvernight.org/pages/endisbutton/)
-   [Pi-hole on Ubuntu 14.04 on VirtualBox](http://hbalagtas.blogspot.com/2016/02/adblocking-with-pi-hole-and-ubuntu-1404.html)
-   [Docker Pi-hole container (x86 and ARM)](https://hub.docker.com/r/diginc/pi-hole/)
-   [Splunk: Pi-hole Visualiser](https://splunkbase.splunk.com/app/3023/)
-   [Pi-hole Chrome extension](https://chrome.google.com/webstore/detail/pi-hole-list-editor/hlnoeoejkllgkjbnnnhfolapllcnaglh) ([open source](https://github.com/packtloss/pihole-extension))
-   [Go Bananas for CHiP-hole ad blocking](https://www.hackster.io/jacobsalmela/chip-hole-network-wide-ad-blocker-98e037)
-   [Sky-Hole](http://dlaa.me/blog/post/skyhole)
-   [Pi-hole in the Cloud!](http://blog.codybunch.com/2015/07/28/Pi-Hole-in-the-cloud/)
-   [unRaid-hole](https://github.com/spants/unraidtemplates/blob/master/Spants/unRaid-hole.xml#L13)--[Repo and more info](http://lime-technology.com/forum/index.php?PHPSESSID=c0eae3e5ef7e521f7866034a3336489d&topic=38486.0)
-   [Pi-hole on/off button](http://thetimmy.silvernight.org/pages/endisbutton/)
-   [Minibian Pi-hole](http://munkjensen.net/wiki/index.php/See_my_Pi-Hole#Minibian_Pi-hole)
-   [Windows Tray Stat Application](https://github.com/goldbattle/copernicus)
-   [Let your blink1 device blink when Pi-hole filters ads](https://gist.github.com/elpatron68/ec0b4c582e5abf604885ac1e068d233f)
-   [Pi-hole Prometheus exporter](https://github.com/nlamirault/pihole_exporter): a [Prometheus](https://prometheus.io/) exporter for Pi-hole
-   [Pi-hole Droid - open source Android client](https://github.com/friimaind/pi-hole-droid)
-   [Windows DNS Swapper](https://github.com/roots84/DNS-Swapper), see [#1400](https://github.com/pi-hole/pi-hole/issues/1400)

# Coverage

-   [Adafruit livestream install](https://www.youtube.com/watch?v=eg4u2j1HYlI)
-   [TekThing: 5 fun, easy projects for a Raspberry Pi](https://youtu.be/QwrKlyC2kdM?t=1m42s)
-   [Pi-hole on Adafruit's blog](https://blog.adafruit.com/2016/03/04/pi-hole-is-a-black-hole-for-internet-ads-piday-raspberrypi-raspberry_pi/)
-   [The Defrag Show - MSDN/Channel 9](https://channel9.msdn.com/Shows/The-Defrag-Show/Defrag-Endoscope-USB-Camera-The-Final-HoloLens-Vote-Adblock-Pi-and-more?WT.mc_id=dlvr_twitter_ch9#time=20m39s)
-   [MacObserver Podcast 585](http://www.macobserver.com/tmo/podcast/macgeekgab-585)
-   [Medium: Block All Ads For $53](https://medium.com/@robleathern/block-ads-on-all-home-devices-for-53-18-a5f1ec139693#.gj1xpgr5d)
-   [MakeUseOf: Adblock Everywhere, The Pi-hole Way](http://www.makeuseof.com/tag/adblock-everywhere-raspberry-pi-hole-way/)
-   [Lifehacker: Turn Your Pi Into An Ad Blocker With A Single Command](http://lifehacker.com/turn-a-raspberry-pi-into-an-ad-blocker-with-a-single-co-1686093533)!
-   [Pi-hole on TekThing](https://youtu.be/8Co59HU2gY0?t=2m)
-   [Pi-hole on Security Now! Podcast](http://www.youtube.com/watch?v=p7-osq_y8i8&t=100m26s)
-   [Foolish Tech Show](https://youtu.be/bYyena0I9yc?t=2m4s)
-   [Pi-hole on Ubuntu](http://www.boyter.org/2015/12/pi-hole-ubuntu-14-04/)
-   [Catchpoint: iOS 9 Ad Blocking](http://blog.catchpoint.com/2015/09/14/ad-blocking-apple/)
-   [Build an Ad-Blocker for less than 10$ with Orange-Pi](http://www.devacron.com/orangepi-zero-as-an-ad-block-server-with-pi-hole/)
