<?php
/* Detailed Pi-Hole Block Page: Show "Website Blocked" if user browses to site, but not to image/file requests based on the work of WaLLy3K for DietPi & Pi-Hole */

$uri = escapeshellcmd($_SERVER['REQUEST_URI']);
$serverName = escapeshellcmd($_SERVER['SERVER_NAME']);

// Retrieve server URI extension (EG: jpg, exe, php)
$uriExt = pathinfo($uri, PATHINFO_EXTENSION);

// Define which URL extensions get rendered as "Website Blocked"
$webExt = array('asp', 'htm', 'html', 'php', 'rss', 'xml');

if(in_array($uriExt, $webExt) || empty($uriExt))
{
	// Requested resource has an extension listed in $webExt
	// or no extension (index access to some folder incl. the root dir)
	$showPage = true;
}
else
{
	// Something else
	$showPage = false;
}

// Handle incoming URI types
if (!$showPage)
{
?>
<html>
<head>
<script>window.close();</script></head>
<body>
</body>
</html>
<?php
	die();
}

// Get Pi-Hole version
$piHoleVersion = exec('cd /etc/.pihole/ && git describe --tags --abbrev=0');

?>
<!DOCTYPE html>
<head>
	<meta charset='UTF-8'/>
	<title>Website Blocked</title>
	<link rel='stylesheet' href='http://firebog.net/pihole.css'/>
	<link rel='shortcut icon' href='http://${_SERVER['SERVER_ADDR']}/adminimgfavicon.png' type='image/png'/>
	<meta name='viewport' content='width=device-width,initial-scale=1.0,maximum-scale=1.0, user-scalable=no'/>
	<meta name='robots' content='noindex,nofollow'/>
</head>
<body>
<header>
	<h1><a href='/'>Website Blocked</a></h1>
</header>
<main>
	<div>Access to the following site has been blocked:<br/>
	<span class='pre msg'><?php echo $serverName.$uri; ?></span></div>
	<div>If you have an ongoing use for this website, please ask to owner of the Pi-Hole in your network to have it whitelisted.</div>
	<div class='buttons blocked'><a class='safe' href='javascript:history.back()'>Back to safety</a>
</main>
<footer>Generated <?php echo date('D g:i A, M d'); ?> by Pi-hole <?php echo $piHoleVersion; ?></footer>
</body>
</html>
