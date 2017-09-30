<p align="center">
<a href=https://www.bountysource.com/trackers/3011939-pi-hole-pi-hole?utm_source=3011939&utm_medium=shield&utm_campaign=TRACKER_BADGE><img src="https://www.bountysource.com/badge/tracker?tracker_id=3011939"></a>
<a href="https://www.codacy.com/app/Pi-hole/pi-hole?utm_source=github.com&amp;utm_medium=referral&amp;utm_content=pi-hole/pi-hole&amp;utm_campaign=Badge_Grade"><img src="https://api.codacy.com/project/badge/Grade/c558a0f8d7124c99b02b84f0f5564238"/></a>
<a href=https://travis-ci.org/pi-hole/pi-hole><img src="https://travis-ci.org/pi-hole/pi-hole.svg?branch=development"></a>
</p>

<p align="center">
<a href=https://discourse.pi-hole.net><img src="https://assets.pi-hole.net/static/Vortex_with_text_and_TM.png" width=210></a><br/>
<b>Network-wide ad blocking via your own Linux hardware</b>
</p>

# Core & Command Line Interface

## Summary
The Pi-hole blocks ads via a [DNS sinkhole](https://en.wikipedia.org/wiki/DNS_Sinkhole), so all your devices are protected without the need to install client-side software.

- **Easy-to-install**: our versatile installer walks you through the process, and [takes less than ten minutes](https://www.youtube.com/watch?v=vKWjx1AQYgs)
- **Resolute**: ads are blocked in _non-browser locations_ such as ad-laden mobile apps and smart TVs
- **Fast**: speeds up the feel of everyday browsing by caching DNS queries, saving bandwidth
- **Lightweight**: runs smoothly and requires [minimal resources](https://discourse.pi-hole.net/t/hardware-software-requirements/273)
- **Robust**: a command line interface for those preferring CLI, and/or wanting to automate tasks
- **Informative**: a beautiful and secure Web Interface dashboard to control your Pi-hole
- **Versatile**: can optionally function as a DHCP server, ensuring each device will not need further intervention
- **Scalable**: [capable of handling hundreds of millions of queries](https://pi-hole.net/2017/05/24/how-much-traffic-can-pi-hole-handle/) when installed on powerful hardware
- **Modern**: blocks ads over both IPv4 and IPv6
- **Free**: open source software which helps ensure _you_ are the sole person in control of your privacy

-----

## One-Step Automated Install
1. Install a [supported operating system](https://discourse.pi-hole.net/t/hardware-software-requirements/273/1)
2. Run the following command

#### `curl -sSL https://install.pi-hole.net | bash`

## Alternative Install Methods
[Piping to `bash` can be dangerous](https://pi-hole.net/2016/07/25/curling-and-piping-to-bash/), so we understand the importance of giving people the option to review our code! Our installer is [found here](https://github.com/pi-hole/pi-hole/blob/master/automated%20install/basic-install.sh), if you wish to read it before running.

You can install Pi-hole via one of the two alternative methods:

### Clone our repository and run the automated installer from your device
```
git clone --depth 1 https://github.com/pi-hole/pi-hole.git Pi-hole
cd Pi-hole/automated\ install/
bash basic-install.sh
```

### Manually download and execute the install file
```
wget -O basic-install.sh https://install.pi-hole.net
bash basic-install.sh
```

## Post-install: Make your network take advantage of Pi-hole

Once the installer has been run, you will need to [configure your router to have **DHCP clients use the Pi-hole as their DNS server**](https://discourse.pi-hole.net/t/how-do-i-configure-my-devices-to-use-pi-hole-as-their-dns-server/245) so that any device that connects to your network will have ads blocked without any further intervention.

If your router does not support setting the DNS server, you can [use Pi-hole's built in DHCP server](https://discourse.pi-hole.net/t/how-do-i-use-pi-holes-built-in-dhcp-server-and-why-would-i-want-to/3026); just be sure to disable DHCP on your router first (if it has that feature available).

As a last resort, you can always manually set each device to use Pi-hole as their DNS server.

-----

## Pi-hole is free, but powered by your support
There are many reoccuring costs involved with maintaining free, open source and privacy respecting software; expenses which [our volunteers](https://github.com/orgs/pi-hole/people) pitch in to cover out-of-pocket. This is just one example of how strongly we feel about our software, as well as the importance of keeping it maintained.

Make no mistake: **your support is absolutely vital to help keep us innovating!**

### Donations
Sending a donation using our links below is **extremely helpful** in offset a portion of our monthly costs:

- ![Paypal](https://assets.pi-hole.net/static/paypal.png) [Donate via PayPal](https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=3J2L3Z4DHW9UY)
- ![Bitcoin](https://assets.pi-hole.net/static/Bitcoin.png) Bitcoin Address: 1GKnevUnVaQM2pQieMyeHkpr8DXfkpfAtL

### Alternative support
If you'd rather not donate (_which is okay!_), there are other ways you can help support us:

- [Digital Ocean](http://www.digitalocean.com/?refcode=344d234950e1) affiliate link
- [Vultr](http://www.vultr.com/?ref=7190426) affiliate link
- [UNIXstickers.com](http://unixstickers.refr.cc/jacobs) affiliate link
- [Pi-hole Swag Store](https://pi-hole.net/shop/)
- Spreading the word about our software, and how you have benefited from it

### Contributing via GitHub
We welcome everyone to contribute to issue reports, suggest new features and create pull requests.

If you have something to add - anything from a typo through to a whole new feature, we're happy to check it out! Just make sure to fill out our template when submitting your request; the questions that it asks will help the volunteers quickly understand what you're aiming to achieve.

You'll find that the [install script](https://github.com/pi-hole/pi-hole/blob/master/automated%20install/basic-install.sh) and the [debug script](https://github.com/pi-hole/pi-hole/blob/master/advanced/Scripts/piholeDebug.sh) have an abundance of comments, which will help you better understand how Pi-hole works. They're also a valuable resource to those who want to learn how to write scripts or code a program! We encourage anyone who likes to tinker to read through it, and submit a pull request for us to review.

### Presentations about Pi-hole
Word-of-mouth continues to help our project grow immensely, and we'd like to help those who are going to be presenting Pi-hole at a conference, meetup or even a school project. If you'd like some free swag to hand out to your audience, [get in touch with us](https://pi-hole.net/2017/05/17/giving-a-presentation-on-pi-hole-contact-us-first-for-some-goodies-and-support/).

-----

## Getting in touch with us
- [Users Forum](https://discourse.pi-hole.net/)
- [Feature requests](https://discourse.pi-hole.net/c/feature-requests?order=votes)
- [FAQs](https://discourse.pi-hole.net/c/faqs)
- [Wiki](https://github.com/pi-hole/pi-hole/wiki)
- [/r/pihole on Reddit](https://www.reddit.com/r/pihole/)
- [@The_Pi_Hole on Twitter](https://twitter.com/The_Pi_Hole)
- [Pi-hole on YouTube](https://www.youtube.com/channel/UCT5kq9w0wSjogzJb81C9U0w)
- [ThePiHole on Facebook](https://www.facebook.com/ThePiHole/)
- [Chat on Gitter](https://gitter.im/pi-hole/pi-hole)

-----

## Features
* <sub>[The Web Interface Dashboard](#the-web-interface-dashboard)</sub>
* <sub>[The Faster-Than-Light Engine](#the-faster-than-light-engine)</sub>
* <sub>[The Query Log](#the-query-log)</sub>
* <sub>[Long-term Statistics](#long-term-statistics)</sub>
* <sub>[Whitelisting and Blacklisting](#whitelisting-and-blacklisting)</sub>
* <sub>[Additional Blocklists](#additional-blocklists)</sub>
* <sub>[Enable and Disable Pi-hole](#enable-and-disable-pi-hole)</sub>
* <sub>[Tools](#tools)</sub>
* <sub>[Web Interface Settings](#web-interface-settings)</sub>
* <sub>[Built-in DHCP Server](#built-in-dhcp-server)</sub>
* <sub>[Real-time Statistics](#real-time-statistics)</sub>

### The Web Interface Dashboard
This optional [open source](https://github.com/almasaeed2010/AdminLTE) dashboard allows you to view stats, change settings, and configure your Pi-hole.

![Pi-hole Dashboard](https://assets.pi-hole.net/static/dashboard.png)

There are several ways to [access the dashboard](https://discourse.pi-hole.net/t/how-do-i-access-pi-holes-dashboard-admin-interface/3168):

1. `http://<IP_ADDPRESS_OF_YOUR_PI_HOLE>/admin/`
2. `http:/pi.hole/admin/` (when using Pi-hole as your DNS server)
3. `http://pi.hole/` (when using Pi-hole as your DNS server)

## The Faster-Than-Light Engine
The [FTL API](https://github.com/pi-hole/FTL) can be accessed via the Web, Command Line and `telnet`.

The Web (`admin/api.php`) and Command Line (`pihole -c -j`) will return `json` formatted output:
``` 
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

More details on the API can be found [here](https://discourse.pi-hole.net/t/pi-hole-api/1863) and `telnet` on [the repo itself](https://github.com/pi-hole/FTL).

### The Query Log
If enabled, the query log will show all of the DNS queries requested by clients using Pi-hole as their DNS server. Standard domains will show in green, and blocked (_Pi-holed_) domains will show in red. You can also whitelist or blacklist domains from within this section.

<p align="center">
<img src="https://assets.pi-hole.net/static/query_log.png">
</p>

The query log and graphs are what have helped people [discover all sorts of unexpected traffic traversing their networks](https://pi-hole.net/2017/07/06/round-3-what-really-happens-on-your-network/).

#### Long-term Statistics
Using our FTL API, Pi-hole will store all the DNS queries in a database for later retrieval and analysis. You can view this data as a graph, individual queries, top clients/advertisers, or even query the database yourself for your own applications.

<p align="center">
<img src="https://assets.pi-hole.net/static/long-term-stats.png">
</p>

### Whitelisting and Blacklisting
Domains can be [whitelisted](https://discourse.pi-hole.net/t/commonly-whitelisted-domains/212) or [blacklisted](https://discourse.pi-hole.net/t/commonly-blacklisted-domains/305) using either the dashboard, or via [the `pihole` command](https://discourse.pi-hole.net/t/the-pihole-command-with-examples/738).

<p align="center">
<a href=https://github.com/pi-hole/pi-hole/wiki/Whitelisting-and-Blacklisting><img src="https://assets.pi-hole.net/static/whitelist.png"></a>
</p>

#### Additional Blocklists
Pi-hole's stock block lists cover over 100,000 known ad-serving domains, which helps ensure you encounter minimal false positives. You can expand the blocking power of your Pi-hole by [adding additional lists](https://discourse.pi-hole.net/t/how-do-i-add-additional-block-lists-to-pi-hole/259) such as the ones found at [The Big Blocklist Collection](https://wally3k.github.io/).

<p align="center">
<a href=https://discourse.pi-hole.net/t/how-do-i-add-additional-block-lists-to-pi-hole/259><img src="https://assets.pi-hole.net/static/manage-ad-lists.png"></a>
</p>

### Enable and Disable Pi-hole
There are times where you may want to disable the blocking functionality, and turn it back on again. You can toggle this via the dashboard or command line.

<p align="center">
<img src="https://assets.pi-hole.net/static/enable-disable.png">
</p>

### Tools

<p align="center">
<img src="https://assets.pi-hole.net/static/tools.png">
</p>

##### Update Ad Lists
This runs [`gravity`](https://github.com/pi-hole/pi-hole/blob/master/gravity.sh) which checks your source list for updates, and downloads if changes are found.

##### Query Ad Lists
You can find out what blocklist a specific domain was found on. This is useful for troubleshooting websites that may not work properly due to a blocked domain.

##### `tail`ing Log Files
You can [watch the log files](https://discourse.pi-hole.net/t/how-do-i-watch-and-interpret-the-pihole-log-file/276) in real time to help debug any issues, or just see what's happening on your network.

##### Pi-hole Debugger
If you are having trouble with your Pi-hole, this is the place to go. You can run the debugger and it will attempt to diagnose any issues, and then link to an FAQ with instructions on rectifying the problem.

<p align="center">
<img src="https://assets.pi-hole.net/static/debug-gui.png">
</p>

If run [via the command line](https://discourse.pi-hole.net/t/the-pihole-command-with-examples/738#debug), you will see coloured text, which makes it easy to identify any problems.

<p align="center">
<a href=https://discourse.pi-hole.net/t/the-pihole-command-with-examples/738#debugs><img src="https://assets.pi-hole.net/static/debug-cli.png"></a>
</p>

After the debugger has finished, you have the option to upload it to our secure server for 48 hours. All you need to do is provide [one of our developers](https://github.com/orgs/pi-hole/teams/debug/members) the unique token generated by the debugger via [one of the various ways of getting in touch with us](#getting-in-touch-with-us).

<p align="center">
<a href=https://discourse.pi-hole.net/t/the-pihole-command-with-examples/738#debugs><img src="https://assets.pi-hole.net/static/debug-token.png"></a>
</p>

You should be able to resolve most issues using the provided FAQ links, but we're always happy to help out if you'd like assistance!

### Web Interface Settings
The settings page lets you control and configure your Pi-hole. You can do things like:

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

### Built-in DHCP Server
Pi-hole ships with a [built-in DHCP server](https://discourse.pi-hole.net/t/how-do-i-use-pi-holes-built-in-dhcp-server-and-why-would-i-want-to/3026). This allows you to let your network devices use Pi-hole as their DNS server if your router does not let you adjust the DHCP options.

One nice feature of using Pi-hole's DHCP server if you can set hostnames and DHCP reservations so you'll [see hostnames in the query log instead of IP addresses](https://discourse.pi-hole.net/t/how-do-i-show-hostnames-instead-of-ip-addresses-in-the-dashboard/3530). You can still do this without using Pi-hole's DHCP server; it just takes a little more work. If you do plan to use Pi-hole's DHCP server, be sure to disable DHCP on your router first.

<p align="center">
<a href=https://discourse.pi-hole.net/t/how-do-i-use-pi-holes-built-in-dhcp-server-and-why-would-i-want-to/3026><img src="https://assets.pi-hole.net/static/piholedhcpserver.png"></a>
</p>

### Real-time Statistics
Using [chronometer2](https://github.com/pi-hole/pi-hole/blob/master/advanced/Scripts/chronometer.sh), you can view [real-time stats](https://discourse.pi-hole.net/t/how-do-i-view-my-pi-holes-stats-over-ssh-or-on-an-lcd-using-chronometer/240) via `ssh` or on an LCD screen such as the [2.8" LCD screen from Adafruit](http://amzn.to/1P0q1Fj).

Simply run `pihole -c` for some detailed information.

<p align="center">
<img src="https://assets.pi-hole.net/static/chrono1.jpg">
<sub><a href="https://www.reddit.com/r/pihole/comments/6ldjna/pihole_setup_went_so_well_at_home_for_the_1st/">Image courtesy of /u/super_nicktendo22</a></sub>
</p>

-----

## Technical Details
To summarize into a short sentence, the Pi-hole is an **advertising-aware DNS/Web server**. While quite outdated at this point, [this original blog post about Pi-hole](https://jacobsalmela.com/2015/06/16/block-millions-ads-network-wide-with-a-raspberry-pi-hole-2-0/) goes into **great detail** about how it was setup and how it works. Syntactically, it's no longer accurate, but the same basic principles and logic still apply to Pi-hole's current state.

-----

## Pi-hole Projects
- [An ad blocking Magic Mirror](https://zonksec.com/blog/magic-mirror-dns-filtering/#dnssoftware)
- [Pi-hole stats in your Mac's menu bar](https://getbitbar.com/plugins/Network/pi-hole.1m.py)
- [Get LED alerts for each blocked ad](http://thetimmy.silvernight.org/pages/endisbutton/)
- [Pi-hole on Ubuntu 14.04 on VirtualBox](http://hbalagtas.blogspot.com/2016/02/adblocking-with-pi-hole-and-ubuntu-1404.html)
- [Docker Pi-hole container (x86 and ARM)](https://hub.docker.com/r/diginc/pi-hole/)
- [Splunk: Pi-hole Visualiser](https://splunkbase.splunk.com/app/3023/)
- [Pi-hole Chrome extension](https://chrome.google.com/webstore/detail/pi-hole-list-editor/hlnoeoejkllgkjbnnnhfolapllcnaglh) ([open source](https://github.com/packtloss/pihole-extension))
- [Go Bananas for CHiP-hole ad blocking](https://www.hackster.io/jacobsalmela/chip-hole-network-wide-ad-blocker-98e037)
- [Sky-Hole](http://dlaa.me/blog/post/skyhole)
- [Pi-hole in the Cloud!](http://blog.codybunch.com/2015/07/28/Pi-Hole-in-the-cloud/)
- [unRaid-hole](https://github.com/spants/unraidtemplates/blob/master/Spants/unRaid-hole.xml#L13)--[Repo and more info](http://lime-technology.com/forum/index.php?PHPSESSID=c0eae3e5ef7e521f7866034a3336489d&topic=38486.0)
- [Pi-hole on/off button](http://thetimmy.silvernight.org/pages/endisbutton/)
- [Minibian Pi-hole](http://munkjensen.net/wiki/index.php/See_my_Pi-Hole#Minibian_Pi-hole)
- [Windows Tray Stat Application](https://github.com/goldbattle/copernicus)
- [Let your blink1 device blink when Pi-hole filters ads](https://gist.github.com/elpatron68/ec0b4c582e5abf604885ac1e068d233f)
- [Pi-hole Prometheus exporter](https://github.com/nlamirault/pihole_exporter): a [Prometheus](https://prometheus.io/) exporter for Pi-hole
- [Pi-hole Droid - open source Android client](https://github.com/friimaind/pi-hole-droid)
- [Windows DNS Swapper](https://github.com/roots84/DNS-Swapper), see [#1400](https://github.com/pi-hole/pi-hole/issues/1400)

-----

## Coverage
- [Adafruit livestream install](https://www.youtube.com/watch?v=eg4u2j1HYlI)
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
- [Build an Ad-Blocker for less than 10$ with Orange-Pi](http://www.devacron.com/orangepi-zero-as-an-ad-block-server-with-pi-hole/)
