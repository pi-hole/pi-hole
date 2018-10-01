<?php
/* Pi-hole: A black hole for Internet advertisements
*  (c) 2017 Pi-hole, LLC (https://pi-hole.net)
*  Network-wide ad blocking via your own hardware.
*
*  This file is copyright under the latest version of the EUPL.
*  Please see LICENSE file for your rights under this license. */

// Sanitise HTTP_HOST output
$serverName = htmlspecialchars($_SERVER["HTTP_HOST"]);
// Remove external ipv6 brackets if any
$serverName = preg_replace('/^\[(.*)\]$/', '${1}', $serverName);

if (!is_file("/etc/pihole/setupVars.conf"))
  die("[ERROR] File not found: <code>/etc/pihole/setupVars.conf</code>");

// Get values from setupVars.conf
$setupVars = parse_ini_file("/etc/pihole/setupVars.conf");
$svPasswd = !empty($setupVars["WEBPASSWORD"]);
$svEmail = (!empty($setupVars["ADMIN_EMAIL"]) && filter_var($setupVars["ADMIN_EMAIL"], FILTER_VALIDATE_EMAIL)) ? $setupVars["ADMIN_EMAIL"] : "";
unset($setupVars);

// Set landing page location, found within /var/www/html/
$landPage = "../landing.php";

// Define array for hostnames to be accepted as self address for splash page
$authorizedHosts = [];
if (!empty($_SERVER["FQDN"])) {
    // If setenv.add-environment = ("fqdn" => "true") is configured in lighttpd,
    // append $serverName to $authorizedHosts
    array_push($authorizedHosts, $serverName);
} else if (!empty($_SERVER["VIRTUAL_HOST"])) {
    // Append virtual hostname to $authorizedHosts
    array_push($authorizedHosts, $_SERVER["VIRTUAL_HOST"]);
}

// Set which extension types render as Block Page (Including "" for index.ext)
$validExtTypes = array("asp", "htm", "html", "php", "rss", "xml", "");

// Get extension of current URL
$currentUrlExt = pathinfo($_SERVER["REQUEST_URI"], PATHINFO_EXTENSION);

// Check if this is served over HTTP or HTTPS
if(isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] == "on") {
    $proto = "https";
} else {
    $proto = "http";
}

// Set mobile friendly viewport
$viewPort = '<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1"/>';

// Set response header
function setHeader($type = "x") {
    header("X-Pi-hole: A black hole for Internet advertisements.");
    if (isset($type) && $type === "js") header("Content-Type: application/javascript");
}

// Determine block page type
if ($serverName === "pi.hole") {
    // Redirect to Web Interface
    exit(header("Location: /admin"));
} elseif (filter_var($serverName, FILTER_VALIDATE_IP) || in_array($serverName, $authorizedHosts)) {
    // Set Splash Page output
    $splashPage = "
    <html><head>
        $viewPort
        <link rel='stylesheet' href='/pihole/blockingpage.css' type='text/css'/>
    </head><body id='splashpage'><img src='/admin/img/logo.svg'/><br/>Pi-<b>hole</b>: Your black hole for Internet advertisements<br><a href='/admin'>Did you mean to go to the admin panel?</a></body></html>
    ";

    // Set splash/landing page based off presence of $landPage
    $renderPage = is_file(getcwd()."/$landPage") ? include $landPage : "$splashPage";

    // Unset variables so as to not be included in $landPage
    unset($serverName, $svPasswd, $svEmail, $authorizedHosts, $validExtTypes, $currentUrlExt, $viewPort);

    // Render splash/landing page when directly browsing via IP or authorised hostname
    exit($renderPage);
} elseif ($currentUrlExt === "js") {
    // Serve Pi-hole Javascript for blocked domains requesting JS
    exit(setHeader("js").'var x = "Pi-hole: A black hole for Internet advertisements."');
} elseif (strpos($_SERVER["REQUEST_URI"], "?") !== FALSE && isset($_SERVER["HTTP_REFERER"])) {
    // Serve blank image upon receiving REQUEST_URI w/ query string & HTTP_REFERRER
    // e.g: An iframe of a blocked domain
    exit(setHeader().'<html>
        <head><script>window.close();</script></head>
        <body><img src="data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACwAAAAAAQABAAACAkQBADs="></body>
    </html>');
} elseif (!in_array($currentUrlExt, $validExtTypes) || substr_count($_SERVER["REQUEST_URI"], "?")) {
    // Serve SVG upon receiving non $validExtTypes URL extension or query string
    // e.g: Not an iframe of a blocked domain, such as when browsing to a file/query directly
    // QoL addition: Allow the SVG to be clicked on in order to quickly show the full Block Page
    $blockImg = '<a href="/"><svg xmlns="http://www.w3.org/2000/svg" width="110" height="16"><defs><style>a {text-decoration: none;} circle {stroke: rgba(152,2,2,0.5); fill: none; stroke-width: 2;} rect {fill: rgba(152,2,2,0.5);} text {opacity: 0.3; font: 11px Arial;}</style></defs><circle cx="8" cy="8" r="7"/><rect x="10.3" y="-6" width="2" height="12" transform="rotate(45)"/><text x="19.3" y="12">Blocked by Pi-hole</text></svg></a>';
    exit(setHeader()."<html>
        <head>$viewPort</head>
        <body>$blockImg</body>
    </html>");
}

/* Start processing Block Page from here */

// Define admin email address text based off $svEmail presence
$bpAskAdmin = !empty($svEmail) ? '<a href="mailto:'.$svEmail.'?subject=Site Blocked: '.$serverName.'"></a>' : "<span/>";

// Determine if at least one block list has been generated
$blocklistglob = glob("/etc/pihole/list.0.*.domains");
if ($blocklistglob === array()) {
    die("[ERROR] There are no domain lists generated lists within <code>/etc/pihole/</code>! Please update gravity by running <code>pihole -g</code>, or repair Pi-hole using <code>pihole -r</code>.");
}

// Set location of adlists file
if (is_file("/etc/pihole/adlists.list")) {
    $adLists = "/etc/pihole/adlists.list";
} elseif (is_file("/etc/pihole/adlists.default")) {
    $adLists = "/etc/pihole/adlists.default";
} else {
    die("[ERROR] File not found: <code>/etc/pihole/adlists.list</code>");
}

// Get all URLs starting with "http" or "www" from adlists and re-index array numerically
$adlistsUrls = array_values(preg_grep("/(^http)|(^www)/i", file($adLists, FILE_IGNORE_NEW_LINES)));

if (empty($adlistsUrls))
    die("[ERROR]: There are no adlist URL's found within <code>$adLists</code>");

// Get total number of blocklists (Including Whitelist, Blacklist & Wildcard lists)
$adlistsCount = count($adlistsUrls) + 3;

// Set query timeout
ini_set("default_socket_timeout", 3);

// Logic for querying blocklists
function queryAds($serverName) {
    // Determine the time it takes while querying adlists
    $preQueryTime = microtime(true)-$_SERVER["REQUEST_TIME_FLOAT"];
    $queryAds = file("http://127.0.0.1/admin/scripts/pi-hole/php/queryads.php?domain=$serverName&bp", FILE_IGNORE_NEW_LINES);
    $queryAds = array_values(array_filter(preg_replace("/data:\s+/", "", $queryAds)));
    $queryTime = sprintf("%.0f", (microtime(true)-$_SERVER["REQUEST_TIME_FLOAT"]) - $preQueryTime);

    // Exception Handling
    try {
        // Define Exceptions
        if (strpos($queryAds[0], "No exact results") !== FALSE) {
            // Return "none" into $queryAds array
            return array("0" => "none");
        } else if ($queryTime >= ini_get("default_socket_timeout")) {
            // Connection Timeout
            throw new Exception ("Connection timeout (".ini_get("default_socket_timeout")."s)");
        } elseif (!strpos($queryAds[0], ".") !== false) {
            // Unknown $queryAds output
            throw new Exception ("Unhandled error message (<code>$queryAds[0]</code>)");
        }
        return $queryAds;
    } catch (Exception $e) {
        // Return exception as array
        return array("0" => "error", "1" => $e->getMessage());
    }
}

// Get results of queryads.php exact search
$queryAds = queryAds($serverName);

// Pass error through to Block Page
if ($queryAds[0] === "error")
    die("[ERROR]: Unable to parse results from <i>queryads.php</i>: <code>".$queryAds[1]."</code>");

// Count total number of matching blocklists
$featuredTotal = count($queryAds);

// Place results into key => value array
$queryResults = null;
foreach ($queryAds as $str) {
    $value = explode(" ", $str);
    @$queryResults[$value[0]] .= "$value[1]";
}

// Determine if domain has been blacklisted, whitelisted, wildcarded or CNAME blocked
if (strpos($queryAds[0], "blacklist") !== FALSE) {
    $notableFlagClass = "blacklist";
    $adlistsUrls = array("π" => substr($queryAds[0], 2));
} elseif (strpos($queryAds[0], "whitelist") !== FALSE) {
    $notableFlagClass = "noblock";
    $adlistsUrls = array("π" => substr($queryAds[0], 2));
    $wlInfo = "recentwl";
} elseif (strpos($queryAds[0], "wildcard") !== FALSE) {
    $notableFlagClass = "wildcard";
    $adlistsUrls = array("π" => substr($queryAds[0], 2));
} elseif ($queryAds[0] === "none") {
    $featuredTotal = "0";
    $notableFlagClass = "noblock";

    // QoL addition: Determine appropriate info message if CNAME exists
    // Suggests to the user that $serverName has a CNAME (alias) that may be blocked
    $dnsRecord = dns_get_record("$serverName")[0];
    if (array_key_exists("target", $dnsRecord)) {
        $wlInfo = $dnsRecord['target'];
    } else {
        $wlInfo = "unknown";
    }
}

// Set #bpOutput notification
$wlOutputClass = (isset($wlInfo) && $wlInfo === "recentwl") ? $wlInfo : "hidden";
$wlOutput = (isset($wlInfo) && $wlInfo !== "recentwl") ? "<a href='http://$wlInfo'>$wlInfo</a>" : "";

// Get Pi-hole Core version
$phVersion = exec("cd /etc/.pihole/ && git describe --long --tags");

// Print $execTime on development branches
// Testing for - is marginally faster than "git rev-parse --abbrev-ref HEAD"
if (explode("-", $phVersion)[1] != "0")
  $execTime = microtime(true)-$_SERVER["REQUEST_TIME_FLOAT"];

// Please Note: Text is added via CSS to allow an admin to provide a localised
// language without the need to edit this file

setHeader();
?>
<!DOCTYPE html>
<!-- Pi-hole: A black hole for Internet advertisements
*  (c) 2017 Pi-hole, LLC (https://pi-hole.net)
*  Network-wide ad blocking via your own hardware.
*
*  This file is copyright under the latest version of the EUPL. -->
<html>
<head>
  <meta charset="UTF-8">
  <?=$viewPort ?>
  <meta name="robots" content="noindex,nofollow"/>
  <meta http-equiv="x-dns-prefetch-control" content="off">
  <link rel="shortcut icon" href="<?=$proto ?>://pi.hole/admin/img/favicon.png" type="image/x-icon"/>
  <link rel="stylesheet" href="<?=$proto ?>://pi.hole/pihole/blockingpage.css" type="text/css"/>
  <title>● <?=$serverName ?></title>
  <script src="<?=$proto ?>://pi.hole/admin/scripts/vendor/jquery.min.js"></script>
  <script>
    window.onload = function () {
      <?php
      // Remove href fallback from "Back to safety" button
      if ($featuredTotal > 0) {
        echo '$("#bpBack").removeAttr("href");';

        // Enable whitelisting if JS is available
        echo '$("#bpWhitelist").prop("disabled", false);';

        // Enable password input if necessary
        if (!empty($svPasswd)) {
          echo '$("#bpWLPassword").attr("placeholder", "Password");';
          echo '$("#bpWLPassword").prop("disabled", false);';
        }
        // Otherwise hide the input
        else {
          echo '$("#bpWLPassword").hide();';
        }
      }
      ?>
    }
  </script>
</head>
<body id="blockpage"><div id="bpWrapper">
<header>
  <h1 id="bpTitle">
    <a class="title" href="/"><?php //Website Blocked ?></a>
  </h1>
  <div class="spc"></div>

  <input id="bpAboutToggle" type="checkbox"/>
  <div id="bpAbout">
    <div class="aboutPH">
      <div class="aboutImg"/></div>
      <p>Open Source Ad Blocker
        <small>Designed for Raspberry Pi</small>
      </p>
    </div>
    <div class="aboutLink">
      <a class="linkPH" href="https://github.com/pi-hole/pi-hole/wiki/What-is-Pi-hole%3F-A-simple-explanation"><?php //About PH ?></a>
      <?php if (!empty($svEmail)) echo '<a class="linkEmail" href="mailto:'.$svEmail.'"></a>'; ?>
    </div>
  </div>

  <div id="bpAlt">
    <label class="altBtn" for="bpAboutToggle"><?php //Why am I here? ?></label>
  </div>
</header>

<main>
  <div id="bpOutput" class="<?=$wlOutputClass ?>"><?=$wlOutput ?></div>
  <div id="bpBlock">
    <p class="blockMsg"><?=$serverName ?></p>
  </div>
  <?php if(isset($notableFlagClass)) { ?>
    <div id="bpFlag">
        <p class="flagMsg <?=$notableFlagClass ?>"></p>
    </div>
  <?php } ?>
  <div id="bpHelpTxt"><?=$bpAskAdmin ?></div>
  <div id="bpButtons" class="buttons">
    <a id="bpBack" onclick="javascript:history.back()" href="about:home"></a>
    <?php if ($featuredTotal > 0) echo '<label id="bpInfo" for="bpMoreToggle"></label>'; ?>
  </div>
  <input id="bpMoreToggle" type="checkbox">
  <div id="bpMoreInfo">
    <span id="bpFoundIn"><span><?=$featuredTotal ?></span><?=$adlistsCount ?></span>
    <pre id='bpQueryOutput'><?php if ($featuredTotal > 0) foreach ($queryResults as $num => $value) { echo "<span>[$num]:</span>$adlistsUrls[$num]\n"; } ?></pre>

    <form id="bpWLButtons" class="buttons">
      <input id="bpWLDomain" type="text" value="<?=$serverName ?>" disabled/>
      <input id="bpWLPassword" type="password" placeholder="Javascript disabled" disabled/><button id="bpWhitelist" type="button" disabled></button>
    </form>
  </div>
</main>

<footer><span><?=date("l g:i A, F dS"); ?>.</span> Pi-hole <?=$phVersion ?> (<?=gethostname()."/".$_SERVER["SERVER_ADDR"]; if (isset($execTime)) printf("/%.2fs", $execTime); ?>)</footer>
</div>

<script>
  function add() {
    $("#bpOutput").removeClass("hidden error exception");
    $("#bpOutput").addClass("add");
    var domain = "<?=$serverName ?>";
    var pw = $("#bpWLPassword");
    if(domain.length === 0) {
      return;
    }
    $.ajax({
      url: "/admin/scripts/pi-hole/php/add.php",
      method: "post",
      data: {"domain":domain, "list":"white", "pw":pw.val()},
      success: function(response) {
        if(response.indexOf("Pi-hole blocking") !== -1) {
          setTimeout(function(){window.location.reload(1);}, 10000);
          $("#bpOutput").removeClass("add");
          $("#bpOutput").addClass("success");
          $("#bpOutput").html("");
        } else {
          $("#bpOutput").removeClass("add");
          $("#bpOutput").addClass("error");
          $("#bpOutput").html(""+response+"");
        }
      },
      error: function(jqXHR, exception) {
        $("#bpOutput").removeClass("add");
        $("#bpOutput").addClass("exception");
        $("#bpOutput").html("");
      }
    });
  }
  <?php if ($featuredTotal > 0) { ?>
    $(document).keypress(function(e) {
        if(e.which === 13 && $("#bpWLPassword").is(":focus")) {
            add();
        }
    });
    $("#bpWhitelist").on("click", function() {
        add();
    });
  <?php } ?>
</script>
</body></html>
