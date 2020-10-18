<!-- markdownlint-configure-file { "MD004": { "style": "consistent" } } -->
<!-- markdownlint-disable MD033 -->
<p align="center">
    <a href="https://pi-hole.net/">
        <img src="https://pi-hole.github.io/graphics/Vortex/Vortex_with_Wordmark.svg" width="150" height="260" alt="Pi-hole">
    </a>
    <br>
    <strong>Network-wide ad blocking via your own Linux hardware</strong>
</p>
<!-- markdownlint-enable MD033 -->

#

The Pi-hole® is a [DNS sinkhole](https://en.wikipedia.org/wiki/DNS_Sinkhole) that protects your devices from unwanted content, without installing any client-side software.

- **Easy-to-install**: our versatile installer walks you through the process, and takes less than ten minutes
- **Resolute**: content is blocked in _non-browser locations_, such as ad-laden mobile apps and smart TVs
- **Responsive**: seamlessly speeds up the feel of everyday browsing by caching DNS queries
- **Lightweight**: runs smoothly with [minimal hardware and software requirements](https://docs.pi-hole.net/main/prerequisites/)
- **Robust**: a command line interface that is quality assured for interoperability
- **Insightful**: a beautiful responsive Web Interface dashboard to view and control your Pi-hole
- **Versatile**: can optionally function as a [DHCP server](https://discourse.pi-hole.net/t/how-do-i-use-pi-holes-built-in-dhcp-server-and-why-would-i-want-to/3026), ensuring *all* your devices are protected automatically
- **Scalable**: [capable of handling hundreds of millions of queries](https://pi-hole.net/2017/05/24/how-much-traffic-can-pi-hole-handle/) when installed on server-grade hardware
- **Modern**: blocks ads over both IPv4 and IPv6
- **Free**: open source software which helps ensure _you_ are the sole person in control of your privacy

-----

Master [![Build Status](https://travis-ci.com/pi-hole/pi-hole.svg?branch=master)](https://travis-ci.com/pi-hole/pi-hole) Development [![Build Status](https://travis-ci.com/pi-hole/pi-hole.svg?branch=development)](https://travis-ci.com/pi-hole/pi-hole)

## One-Step Automated Install

Those who want to get started quickly and conveniently may install Pi-hole using the following command:

### `curl -sSL https://install.pi-hole.net | bash`

## Alternative Install Methods

Piping to `bash` is [controversial](https://pi-hole.net/2016/07/25/curling-and-piping-to-bash), as it prevents you from [reading code that is about to run](https://github.com/pi-hole/pi-hole/blob/master/automated%20install/basic-install.sh) on your system. Therefore, we provide these alternative installation methods which allow code review before installation:

### Method 1: Clone our repository and run

```bash
git clone --depth 1 https://github.com/pi-hole/pi-hole.git Pi-hole
cd "Pi-hole/automated install/"
sudo bash basic-install.sh
```

### Method 2: Manually download the installer and run

```bash
wget -O basic-install.sh https://install.pi-hole.net
sudo bash basic-install.sh
```

## [Post-install: Make your network take advantage of Pi-hole](https://docs.pi-hole.net/main/post-install/)

Once the installer has been run, you will need to [configure your router to have **DHCP clients use Pi-hole as their DNS server**](https://discourse.pi-hole.net/t/how-do-i-configure-my-devices-to-use-pi-hole-as-their-dns-server/245) which ensures that all devices connecting to your network will have content blocked without any further intervention.

If your router does not support setting the DNS server, you can [use Pi-hole's built-in DHCP server](https://discourse.pi-hole.net/t/how-do-i-use-pi-holes-built-in-dhcp-server-and-why-would-i-want-to/3026); just be sure to disable DHCP on your router first (if it has that feature available).

As a last resort, you can always manually set each device to use Pi-hole as their DNS server.

-----

## Pi-hole is free, but powered by your support

There are many reoccurring costs involved with maintaining free, open source, and privacy-respecting software; expenses which [our volunteer developers](https://github.com/orgs/pi-hole/people) pitch in to cover out-of-pocket. This is just one example of how strongly we feel about our software, as well as the importance of keeping it maintained.

Make no mistake: **your support is absolutely vital to help keep us innovating!**

### [Donations](https://pi-hole.net/donate)

Sending a donation using our Sponsor Button is **extremely helpful** in offsetting a portion of our monthly expenses:

### Alternative support

If you'd rather not donate (_which is okay!_), there are other ways you can help support us:

- [Patreon](https://patreon.com/pihole) _Become a patron for rewards_
- [Digital Ocean](https://www.digitalocean.com/?refcode=344d234950e1) _affiliate link_
- [Stickermule](https://www.stickermule.com/unlock?ref_id=9127301701&utm_medium=link&utm_source=invite) _earn a $10 credit after your first purchase_
- [Amazon](http://www.amazon.com/exec/obidos/redirect-home/pihole09-20) _affiliate link_
- Spreading the word about our software, and how you have benefited from it

### Contributing via GitHub

We welcome _everyone_ to contribute to issue reports, suggest new features, and create pull requests.

If you have something to add - anything from a typo through to a whole new feature, we're happy to check it out! Just make sure to fill out our template when submitting your request; the questions that it asks will help the volunteers quickly understand what you're aiming to achieve.

You'll find that the [install script](https://github.com/pi-hole/pi-hole/blob/master/automated%20install/basic-install.sh) and the [debug script](https://github.com/pi-hole/pi-hole/blob/master/advanced/Scripts/piholeDebug.sh) have an abundance of comments, which will help you better understand how Pi-hole works. They're also a valuable resource to those who want to learn how to write scripts or code a program! We encourage anyone who likes to tinker to read through it and submit a pull request for us to review.

-----

## Getting in touch with us

While we are primarily reachable on our [Discourse User Forum](https://discourse.pi-hole.net/), we can also be found on a variety of social media outlets. **Please be sure to check the FAQ's** before starting a new discussion, as we do not have the spare time to reply to every request for assistance.

- [Frequently Asked Questions](https://discourse.pi-hole.net/c/faqs)
- [Feature Requests](https://discourse.pi-hole.net/c/feature-requests?order=votes)
- [Reddit](https://www.reddit.com/r/pihole/)
- [Twitter](https://twitter.com/The_Pi_hole)

-----

## Breakdown of Features

### The Command Line Interface

The [pihole](https://docs.pi-hole.net/core/pihole-command/) command has all the functionality necessary to be able to fully administer the Pi-hole, without the need of the Web Interface. It's fast, user-friendly, and auditable by anyone with an understanding of `bash`.

![Pi-hole Blacklist Demo](https://pi-hole.github.io/graphics/Screenshots/blacklist-cli.gif)

Some notable features include:

- [Whitelisting, Blacklisting and Regex](https://docs.pi-hole.net/core/pihole-command/#whitelisting-blacklisting-and-regex)
- [Debugging utility](https://docs.pi-hole.net/core/pihole-command/#debugger)
- [Viewing the live log file](https://docs.pi-hole.net/core/pihole-command/#tail)
- [Updating Ad Lists](https://docs.pi-hole.net/core/pihole-command/#gravity)
- [Querying Ad Lists for blocked domains](https://docs.pi-hole.net/core/pihole-command/#query)
- [Enabling and Disabling Pi-hole](https://docs.pi-hole.net/core/pihole-command/#enable-disable)
- ... and *many* more!

You can read our [Core Feature Breakdown](https://docs.pi-hole.net/core/pihole-command/#pi-hole-core) for more information.

### The Web Interface Dashboard

This [optional dashboard](https://github.com/pi-hole/AdminLTE) allows you to view stats, change settings, and configure your Pi-hole. It's the power of the Command Line Interface, with none of the learning curve!

![Pi-hole Dashboard](https://pi-hole.github.io/graphics/Screenshots/pihole-dashboard.png)

Some notable features include:

- Mobile friendly interface
- Password protection
- Detailed graphs and doughnut charts
- Top lists of domains and clients
- A filterable and sortable query log
- Long Term Statistics to view data over user-defined time ranges
- The ability to easily manage and configure Pi-hole features
- ... and all the main features of the Command Line Interface!

There are several ways to [access the dashboard](https://discourse.pi-hole.net/t/how-do-i-access-pi-holes-dashboard-admin-interface/3168):

1. `http://pi.hole/admin/` (when using Pi-hole as your DNS server)
2. `http://<IP_ADDPRESS_OF_YOUR_PI_HOLE>/admin/`
3. `http://pi.hole/` (when using Pi-hole as your DNS server)

## Faster-than-light Engine

FTLDNS is a lightweight, purpose-built daemon used to provide statistics needed for the Web Interface, and its API can be easily integrated into your own projects. As the name implies, FTLDNS does this all *very quickly*!

Some of the statistics you can integrate include:

- Total number of domains being blocked
- Total number of DNS queries today
- Total number of ads blocked today
- Percentage of ads blocked
- Unique domains
- Queries forwarded (to your chosen upstream DNS server)
- Queries cached
- Unique clients

The API can be accessed via [`telnet`](https://github.com/pi-hole/FTL), the Web (`admin/api.php`) and Command Line (`pihole -c -j`). You can find out [more details over here](https://discourse.pi-hole.net/t/pi-hole-api/1863).
