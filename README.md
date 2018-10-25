<p align="center">
<a href="https://pi-hole.net"><img src="https://pi-hole.github.io/graphics/Vortex/Vortex_with_text.png" width="150" height="255" alt="Pi-hole"></a><br/>
<b>Network-wide ad blocking via your own Linux hardware</b><br/>
</p>

The Pi-hole[®](https://pi-hole.net/trademark-rules-and-brand-guidelines/) is a [DNS sinkhole](https://en.wikipedia.org/wiki/DNS_Sinkhole) that protects your devices from unwanted content, without installing any client-side software.

- **Easy-to-install**: our versatile installer walks you through the process, and [takes less than ten minutes](https://www.youtube.com/watch?v=vKWjx1AQYgs)
- **Resolute**: content is blocked in _non-browser locations_, such as ad-laden mobile apps and smart TVs
- **Responsive**: seamlessly speeds up the feel of everyday browsing by caching DNS queries
- **Lightweight**: runs smoothly with [minimal hardware and software requirements](https://discourse.pi-hole.net/t/hardware-software-requirements/273)
- **Robust**: a command line interface that is quality assured for interoperability
- **Insightful**: a beautiful responsive Web Interface dashboard to view and control your Pi-hole
- **Versatile**: can optionally function as a [DHCP server](https://discourse.pi-hole.net/t/how-do-i-use-pi-holes-built-in-dhcp-server-and-why-would-i-want-to/3026), ensuring *all* your devices are protected automatically
- **Scalable**: [capable of handling hundreds of millions of queries](https://pi-hole.net/2017/05/24/how-much-traffic-can-pi-hole-handle/) when installed on server-grade hardware
- **Modern**: blocks ads over both IPv4 and IPv6
- **Free**: open source software which helps ensure _you_ are the sole person in control of your privacy

-----
<a href="https://www.codacy.com/app/Pi-hole/pi-hole?utm_source=github.com&amp;utm_medium=referral&amp;utm_content=pi-hole/pi-hole&amp;utm_campaign=Badge_Grade"><img src="https://api.codacy.com/project/badge/Grade/c558a0f8d7124c99b02b84f0f5564238" alt="Codacy Grade"/></a>
<a href="https://travis-ci.org/pi-hole/pi-hole"><img src="https://travis-ci.org/pi-hole/pi-hole.svg?branch=development" alt="Travis Build Status"/></a>
<a href="https://www.bountysource.com/trackers/3011939-pi-hole-pi-hole?utm_source=3011939&utm_medium=shield&utm_campaign=TRACKER_BADGE"><img src="https://www.bountysource.com/badge/tracker?tracker_id=3011939" alt="BountySource"/></a>

## One-Step Automated Install
Those who want to get started quickly and conveniently may install Pi-hole using the following command:

#### `curl -sSL https://install.pi-hole.net | bash`

## Alternative Install Methods
[Piping to `bash` is controversial](https://pi-hole.net/2016/07/25/curling-and-piping-to-bash), as it prevents you from [reading code that is about to run](https://github.com/pi-hole/pi-hole/blob/master/automated%20install/basic-install.sh) on your system. Therefore, we provide these alternative installation methods which allow code review before installation:

### Method 1: Clone our repository and run
```
git clone --depth 1 https://github.com/pi-hole/pi-hole.git Pi-hole
cd "Pi-hole/automated install/"
sudo bash basic-install.sh
```

### Method 2: Manually download the installer and run
```
wget -O basic-install.sh https://install.pi-hole.net
sudo bash basic-install.sh
```

## Post-install: Make your network take advantage of Pi-hole

Once the installer has been run, you will need to [configure your router to have **DHCP clients use Pi-hole as their DNS server**](https://discourse.pi-hole.net/t/how-do-i-configure-my-devices-to-use-pi-hole-as-their-dns-server/245) which ensures that all devices connecting to your network will have content blocked without any further intervention.

If your router does not support setting the DNS server, you can [use Pi-hole's built-in DHCP server](https://discourse.pi-hole.net/t/how-do-i-use-pi-holes-built-in-dhcp-server-and-why-would-i-want-to/3026); just be sure to disable DHCP on your router first (if it has that feature available).

As a last resort, you can always manually set each device to use Pi-hole as their DNS server.

-----

## Pi-hole is free, but powered by your support
There are many reoccurring costs involved with maintaining free, open source, and privacy-respecting software; expenses which [our volunteer developers](https://github.com/orgs/pi-hole/people) pitch in to cover out-of-pocket. This is just one example of how strongly we feel about our software, as well as the importance of keeping it maintained.

Make no mistake: **your support is absolutely vital to help keep us innovating!**

### Donations
Sending a donation using our links below is **extremely helpful** in offsetting a portion of our monthly expenses:

- <img src="https://pi-hole.github.io/graphics/Badges/paypal-badge-black.svg" width="24" height="24" alt="PP"/> <a href="https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=3J2L3Z4DHW9UY">Donate via PayPal</a><br/>
- <img src="https://pi-hole.github.io/graphics/Badges/bitcoin-badge-black.svg" width="24" height="24" alt="BTC"/> [Bitcoin](https://commerce.coinbase.com/checkout/fb7facaf-bebd-46be-bb77-b358f4546763): <code>
3MDPzjXu2hjw5sGLJvKUi1uXbvQPzVrbpF</code></br>
- <img src="https://pi-hole.github.io/graphics/Badges/bitcoin-badge-black.svg" width="24" height="24" alt="BTC"/> [Bitcoin Cash](https://commerce.coinbase.com/checkout/fb7facaf-bebd-46be-bb77-b358f4546763): <code>qzqsz4aju2eecc6uhs7tus4vlwhhela24sdruf4qp5</code></br>
- <img src="https://pi-hole.github.io/graphics/Badges/ethereum-badge-black.svg" width="24" height="24" alt="BTC"/> [Ethereum](https://commerce.coinbase.com/checkout/fb7facaf-bebd-46be-bb77-b358f4546763): <code>0x79d4e90A4a0C732819526c93e21A3F1356A2FAe1</code>

### Alternative support
If you'd rather not [donate](https://pi-hole.net/donate/) (_which is okay!_), there are other ways you can help support us:
- [Patreon](https://patreon.com/pihole) _Become a patron for rewards_
- [Digital Ocean](http://www.digitalocean.com/?refcode=344d234950e1) _affiliate link_
- [Stickermule](https://www.stickermule.com/unlock?ref_id=6055890701&utm_medium=link&utm_source=invite) _earn a $10 credit after your first purchase_
- [Pi-hole Swag Store](https://pi-hole.net/shop/) _affiliate link_
- [Amazon](http://www.amazon.com/exec/obidos/redirect-home/pihole09-20) _affiliate link_
- [DNS Made Easy](https://cp.dnsmadeeasy.com/u/133706) _affiliate link_
- [Vultr](http://www.vultr.com/?ref=7190426) _affiliate link_
- Spreading the word about our software, and how you have benefited from it

### Contributing via GitHub
We welcome _everyone_ to contribute to issue reports, suggest new features, and create pull requests.

If you have something to add - anything from a typo through to a whole new feature, we're happy to check it out! Just make sure to fill out our template when submitting your request; the questions that it asks will help the volunteers quickly understand what you're aiming to achieve.

You'll find that the [install script](https://github.com/pi-hole/pi-hole/blob/master/automated%20install/basic-install.sh) and the [debug script](https://github.com/pi-hole/pi-hole/blob/master/advanced/Scripts/piholeDebug.sh) have an abundance of comments, which will help you better understand how Pi-hole works. They're also a valuable resource to those who want to learn how to write scripts or code a program! We encourage anyone who likes to tinker to read through it and submit a pull request for us to review.

### Presentations about Pi-hole
Word-of-mouth continues to help our project grow immensely, and so we are helping make this easier for people.

If you are going to be presenting Pi-hole at a conference, meetup or even a school project, [get in touch with us](https://pi-hole.net/2017/05/17/giving-a-presentation-on-pi-hole-contact-us-first-for-some-goodies-and-support/) so we can hook you up with free swag to hand out to your audience!

-----

## Getting in touch with us
While we are primarily reachable on our <a href="https://discourse.pi-hole.net/">Discourse User Forum</a>, we can also be found on a variety of social media outlets. **Please be sure to check the FAQ's** before starting a new discussion, as we do not have the spare time to reply to every request for assistance.

<ul>
  <li><a href="https://discourse.pi-hole.net/c/faqs">Frequently Asked Questions</a></li>
  <li><a href="https://github.com/pi-hole/pi-hole/wiki">Pi-hole Wiki</a></li>
  <li><a href="https://discourse.pi-hole.net/c/feature-requests?order=votes">Feature Requests</a></li>
  <li><a href="https://discourse.pi-hole.net/">Discourse User Forum</a></li>
  <li><a href="https://www.reddit.com/r/pihole/">Reddit</a></li>
  <li><a href="https://gitter.im/pi-hole/pi-hole">Gitter</a> (Real-time chat)</li>
  <li><a href="https://twitter.com/The_Pi_Hole">Twitter</a></li>
  <li><a href="https://www.youtube.com/channel/UCT5kq9w0wSjogzJb81C9U0w">YouTube</a></li>
  <li><a href="https://www.facebook.com/ThePiHole/">Facebook</a></li>
</ul>

-----

## Breakdown of Features
### The Command Line Interface
The `pihole` command has all the functionality necessary to be able to fully administer the Pi-hole, without the need of the Web Interface. It's fast, user-friendly, and auditable by anyone with an understanding of `bash`.

<a href="https://pi-hole.github.io/graphics/Screenshots/blacklist-cli.gif"><img src="https://pi-hole.github.io/graphics/Screenshots/blacklist-cli.gif" alt="Pi-hole Blacklist Demo"/></a>

Some notable features include:
* [Whitelisting, Blacklisting and Wildcards](https://github.com/pi-hole/pi-hole/wiki/Core-Function-Breakdown#whitelisting-blacklisting-and-wildcards)
* [Debugging utility](https://github.com/pi-hole/pi-hole/wiki/Core-Function-Breakdown#debugger)
* [Viewing the live log file](https://github.com/pi-hole/pi-hole/wiki/Core-Function-Breakdown#tail)
* [Real-time Statistics via `ssh`](https://github.com/pi-hole/pi-hole/wiki/Core-Function-Breakdown#chronometer) or [your TFT LCD screen](http://www.amazon.com/exec/obidos/ASIN/B00ID39LM4/pihole09-20)
* [Updating Ad Lists](https://github.com/pi-hole/pi-hole/wiki/Core-Function-Breakdown#gravity)
* [Querying Ad Lists for blocked domains](https://github.com/pi-hole/pi-hole/wiki/Core-Function-Breakdown#query)
* [Enabling and Disabling Pi-hole](https://github.com/pi-hole/pi-hole/wiki/Core-Function-Breakdown#enable--disable)
* ... and *many* more!

You can read our [Core Feature Breakdown](https://github.com/pi-hole/pi-hole/wiki/Core-Function-Breakdown), as well as read up on [example usage](https://discourse.pi-hole.net/t/the-pihole-command-with-examples/738) for more information.

### The Web Interface Dashboard
This [optional dashboard](https://github.com/pi-hole/AdminLTE) allows you to view stats, change settings, and configure your Pi-hole. It's the power of the Command Line Interface, with none of the learning curve!

<img src="https://pi-hole.github.io/graphics/Screenshots/pihole-dashboard.png"  alt="Pi-hole Dashboard"/></a>

Some notable features include:
* Mobile friendly interface
* Password protection
* Detailed graphs and doughnut charts
* Top lists of domains and clients
* A filterable and sortable query log
* Long Term Statistics to view data over user-defined time ranges
* The ability to easily manage and configure Pi-hole features
* ... and all the main features of the Command Line Interface!

There are several ways to [access the dashboard](https://discourse.pi-hole.net/t/how-do-i-access-pi-holes-dashboard-admin-interface/3168):

1. `http://<IP_ADDPRESS_OF_YOUR_PI_HOLE>/admin/`
2. `http://pi.hole/admin/` (when using Pi-hole as your DNS server)
3. `http://pi.hole/` (when using Pi-hole as your DNS server)

## Faster-than-light Engine
FTLDNS is a lightweight, purpose-built daemon used to provide statistics needed for the Web Interface, and its API can be easily integrated into your own projects. As the name implies, FTLDNS does this all *very quickly*!

Some of the statistics you can integrate include:
* Total number of domains being blocked
* Total number of DNS queries today
* Total number of ads blocked today
* Percentage of ads blocked
* Unique domains
* Queries forwarded (to your chosen upstream DNS server)
* Queries cached
* Unique clients

The API can be accessed via [`telnet`](https://github.com/pi-hole/FTL), the Web (`admin/api.php`) and Command Line (`pihole -c -j`). You can out find [more details over here](https://discourse.pi-hole.net/t/pi-hole-api/1863).

-----

## The Origin Of Pi-hole
Pi-hole being an **advertising-aware DNS/Web server**, makes use of the following technologies:

* [`dnsmasq`](http://www.thekelleys.org.uk/dnsmasq/doc.html) - a lightweight DNS and DHCP server
* [`curl`](https://curl.haxx.se) - A command line tool for transferring data with URL syntax
* [`lighttpd`](https://www.lighttpd.net) - web server designed and optimized for high performance
* [`php`](https://secure.php.net) - a popular general-purpose web scripting language
* [AdminLTE Dashboard](https://github.com/almasaeed2010/AdminLTE) - premium admin control panel based on Bootstrap 3.x

While quite outdated at this point, [this original blog post about Pi-hole](https://jacobsalmela.com/2015/06/16/block-millions-ads-network-wide-with-a-raspberry-pi-hole-2-0/) goes into **great detail** about how Pi-hole was originally set up and how it works. Syntactically, it's no longer accurate, but the same basic principles and logic still apply to Pi-hole's current state.

-----

## Coverage
- [Lifehacker: Turn A Raspberry Pi Into An Ad Blocker With A Single Command](https://www.lifehacker.com.au/2015/02/turn-a-raspberry-pi-into-an-ad-blocker-with-a-single-command/) (Feburary, 2015)
- [MakeUseOf: Adblock Everywhere: The Raspberry Pi-Hole Way](http://www.makeuseof.com/tag/adblock-everywhere-raspberry-pi-hole-way/) (March, 2015)
- [Catchpoint: Ad-Blocking on Apple iOS9: Valuing the End User Experience](http://blog.catchpoint.com/2015/09/14/ad-blocking-apple/) (September, 2015)
- [Security Now Netcast: Pi-hole](https://www.youtube.com/watch?v=p7-osq_y8i8&t=100m26s) (October, 2015)
- [TekThing: Raspberry Pi-Hole Makes Ads Disappear!](https://youtu.be/8Co59HU2gY0?t=2m) (December, 2015)
- [Foolish Tech Show](https://youtu.be/bYyena0I9yc?t=2m4s) (December, 2015)
- [Block Ads on All Home Devices for $53.18](https://medium.com/@robleathern/block-ads-on-all-home-devices-for-53-18-a5f1ec139693#.gj1xpgr5d) (December, 2015)
- [Pi-Hole for Ubuntu 14.04](http://www.boyter.org/2015/12/pi-hole-ubuntu-14-04/) (December, 2015)
- [MacObserver Podcast 585](https://www.macobserver.com/tmo/podcast/macgeekgab-585) (December, 2015)
- [The Defrag Show: Endoscope USB Camera, The Final [HoloLens] Vote, Adblock Pi and more](https://channel9.msdn.com/Shows/The-Defrag-Show/Defrag-Endoscope-USB-Camera-The-Final-HoloLens-Vote-Adblock-Pi-and-more?WT.mc_id=dlvr_twitter_ch9#time=20m39s) (January, 2016)
- [Adafruit: Pi-hole is a black hole for internet ads](https://blog.adafruit.com/2016/03/04/pi-hole-is-a-black-hole-for-internet-ads-piday-raspberrypi-raspberry_pi/) (March, 2016)
- [Digital Trends: 5 Fun, Easy Projects You Can Try With a $35 Raspberry Pi](https://youtu.be/QwrKlyC2kdM?t=1m42s) (March, 2016)
- [Adafruit: Raspberry Pi Quick Look at Pi Hole ad blocking server with Tony D](https://www.youtube.com/watch?v=eg4u2j1HYlI) (June, 2016)
- [Devacron: OrangePi Zero as an Ad-Block server with Pi-Hole](http://www.devacron.com/orangepi-zero-as-an-ad-block-server-with-pi-hole/) (December, 2016)
- [Linux Pro: The Hole Truth](http://www.linuxpromagazine.com/Issues/2017/200/The-sysadmin-s-daily-grind-Pi-hole) (July, 2017)
- [Adafruit: installing Pi-hole on a Pi Zero W](https://learn.adafruit.com/pi-hole-ad-blocker-with-pi-zero-w/install-pi-hole) (August, 2017)
- [CryptoAUSTRALIA: How We Tried 5 Privacy Focused Raspberry Pi Projects](https://blog.cryptoaustralia.org.au/2017/10/05/5-privacy-focused-raspberry-pi-projects/) (October, 2017)
- [CryptoAUSTRALIA: Pi-hole Workshop](https://blog.cryptoaustralia.org.au/2017/11/02/pi-hole-network-wide-ad-blocker/) (November, 2017)
- [Know How 355: Killing ads with a Raspberry Pi-Hole!](https://www.twit.tv/shows/know-how/episodes/355) (November, 2017)
- [Scott Helme: Securing DNS across all of my devices with Pi-Hole + DNS-over-HTTPS + 1.1.1.1](https://scotthelme.co.uk/securing-dns-across-all-of-my-devices-with-pihole-dns-over-https-1-1-1-1/) (April, 2018)
- [Scott Helme: Catching and dealing with naughty devices on my home network](https://scotthelme.co.uk/catching-naughty-devices-on-my-home-network/) (April, 2018)
- [Bloomberg Business Week: Brotherhood of the Ad blockers](https://www.bloomberg.com/news/features/2018-05-10/inside-the-brotherhood-of-pi-hole-ad-blockers) (May, 2018)
- [Software Engineering Daily: Interview with the creator of Pi-hole](https://softwareengineeringdaily.com/2018/05/29/pi-hole-ad-blocker-hardware-with-jacob-salmela/) (May, 2018)
- [Raspberry Pi: Block ads at home using Pi-hole and a Raspberry Pi](https://www.raspberrypi.org/blog/pi-hole-raspberry-pi/) (July, 2018)
- [Troy Hunt: Mmm... Pi-hole...](https://www.troyhunt.com/mmm-pi-hole/) (September, 2018)
- [PEBKAK Podcast: Interview With Jacob Salmela](https://www.jerseystudios.net/2018/10/11/150-pi-hole/) (October, 2018)

-----

## Pi-hole Projects
- [The Big Blocklist Collection](https://wally3k.github.io)
- [Pie in the Sky-Hole](https://dlaa.me/blog/post/skyhole)
- [Copernicus: Windows Tray Application](https://github.com/goldbattle/copernicus)
- [Magic Mirror with DNS Filtering](https://zonksec.com/blog/magic-mirror-dns-filtering/#dnssoftware)
- [Windows DNS Swapper](https://github.com/roots84/DNS-Swapper)
