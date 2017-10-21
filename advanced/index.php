<?php
/* Detailed Pi-hole Block Page: Show "Website Blocked" if user browses to site, but not to image/file requests based on the work of WaLLy3K for DietPi & Pi-Hole */

function validIP($address){
	if (preg_match('/[.:0]/', $address) && !preg_match('/[1-9a-f]/', $address)) {
		// Test if address contains either `:` or `0` but not 1-9 or a-f
		return false;
	}
	return !filter_var($address, FILTER_VALIDATE_IP) === false;
}

$uri = escapeshellcmd($_SERVER['REQUEST_URI']);
$serverName = escapeshellcmd($_SERVER['SERVER_NAME']);

// Retrieve server URI extension (EG: jpg, exe, php)
ini_set('pcre.recursion_limit',100);
$uriExt = pathinfo($uri, PATHINFO_EXTENSION);

// Define which URL extensions get rendered as "Website Blocked"
$webExt = ['asp', 'htm', 'html', 'php', 'rss', 'xml'];

// Get IPv4 and IPv6 addresses from setupVars.conf (if available)
$setupVars = parse_ini_file("/etc/pihole/setupVars.conf");
$ipv4 = isset($setupVars["IPV4_ADDRESS"]) ? explode("/", $setupVars["IPV4_ADDRESS"])[0] : $_SERVER['SERVER_ADDR'];
$ipv6 = isset($setupVars["IPV6_ADDRESS"]) ? explode("/", $setupVars["IPV6_ADDRESS"])[0] : $_SERVER['SERVER_ADDR'];

$AUTHORIZED_HOSTNAMES = array(
	$ipv4,
	$ipv6,
	str_replace(array("[","]"), array("",""), $_SERVER["SERVER_ADDR"]),
	gethostname(),
	'pi.hole',
	'localhost'
);
// Allow user set virtual hostnames
$virtual_host = getenv('VIRTUAL_HOST');
if (!empty($virtual_host)){
    array_push($AUTHORIZED_HOSTNAMES, $virtual_host);
} else {
    $virtual_host = "pi.hole";
}

// Immediately quit since we didn't block this page (the IP address or pi.hole is explicitly requested)
if(validIP($serverName))
{
	http_response_code(404);
	die();
}

if(in_array($serverName, $AUTHORIZED_HOSTNAMES)){
    // Redirect user to admin
    header('HTTP/1.1 301 Moved Permanently');
    header("Location: /admin/");
}

$showPage = (in_array($uriExt, $webExt) || empty($uriExt)) ? true : false;
// Get Pi-hole version
$piHoleVersion = exec('cd /etc/.pihole/ && git describe --tags --abbrev=0');

// Handle incoming URI types

if(!$showPage):
    ?>
    <html>
    <head>
        <script>window.close();</script>
    </head>
    <body>
    <img src="data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7">
    </body>
    </html>

<?php else:
    ob_start();
    include("blocked.include.html.php");
    ob_get_contents();
    ob_end_flush();
endif;