#
# Varnish 3 configuration for Wordpress
#
# On Debian OS:  /etc/varnish/default.vcl
#
# Nicolas Hennion (aka) Nicolargo
#

# Set the default backend (Nginx server for me)
backend default {
	# My Nginx server listen on IP address 127.0.0.1 and TCP port 8080
	.host = "127.0.0.1";
	.port = "8080";
	# Increase guru timeout
	# http://vincentfretin.ecreall.com/articles/varnish-guru-meditation-on-timeout
	.first_byte_timeout = 300s;
}

# Forbidden IP ACL
acl forbidden {
	# "41.194.61.2"/32;
}

# Purge ACL
acl purge {
	# Only localhost can purge my cache
	"127.0.0.1";
	"localhost";
	"88.190.27.139";
}

# This function is used when a request is send by a HTTP client (Browser) 
sub vcl_recv {
	# Block the forbidden IP addresse
	if (client.ip ~ forbidden) {
        	error 403 "Forbidden";
	}

	# Only cache the following sites
	#if ((req.http.host ~ "(blog.nicolargo.com)") || (req.http.host ~ "(blogtest.nicolargo.com)")) { 
	if ((req.http.host ~ "(blog.nicolargo.com)")) { 
		set req.backend = default; 
	} else { 
		return (pass); 
	}

	# Compatibility with Apache format log
	if (req.restarts == 0) {
 		if (req.http.x-forwarded-for) {
 	    		set req.http.X-Forwarded-For = req.http.X-Forwarded-For + ", " + client.ip;
	 	} else {
			set req.http.X-Forwarded-For = client.ip;
	 	}
     	}

	# Normalize the header, remove the port (in case you're testing this on various TCP ports)
	set req.http.Host = regsub(req.http.Host, ":[0-9]+", "");

	# Allow purging from ACL
	if (req.request == "PURGE") {
		# If not allowed then a error 405 is returned
		if (!client.ip ~ purge) {
			error 405 "This IP is not allowed to send PURGE requests.";
		}	
		# If allowed, do a cache_lookup -> vlc_hit() or vlc_miss()
		return (lookup);
	}

	# Post requests will not be cached
	if (req.http.Authorization || req.request == "POST") {
		return (pass);
	}

	# --- Wordpress specific configuration
	
	# Did not cache the RSS feed
	if (req.url ~ "/feed") {
		return (pass);
	}

	# Blitz hack
        if (req.url ~ "/mu-.*") {
                return (pass);
        }

	
	# Did not cache the admin and login pages
	if (req.url ~ "/wp-(login|admin)") {
		return (pass);
	}

	# Remove the "has_js" cookie
	set req.http.Cookie = regsuball(req.http.Cookie, "has_js=[^;]+(; )?", "");

	# Remove any Google Analytics based cookies
	set req.http.Cookie = regsuball(req.http.Cookie, "__utm.=[^;]+(; )?", "");

	# Remove the Quant Capital cookies (added by some plugin, all __qca)
	set req.http.Cookie = regsuball(req.http.Cookie, "__qc.=[^;]+(; )?", "");

	# Remove the wp-settings-1 cookie
	set req.http.Cookie = regsuball(req.http.Cookie, "wp-settings-1=[^;]+(; )?", "");

	# Remove the wp-settings-time-1 cookie
	set req.http.Cookie = regsuball(req.http.Cookie, "wp-settings-time-1=[^;]+(; )?", "");

	# Remove the wp test cookie
	set req.http.Cookie = regsuball(req.http.Cookie, "wordpress_test_cookie=[^;]+(; )?", "");

	# Are there cookies left with only spaces or that are empty?
	if (req.http.cookie ~ "^ *$") {
		    unset req.http.cookie;
	}
	
	# Cache the following files extensions 
	if (req.url ~ "\.(css|js|png|gif|jp(e)?g|swf|ico)") {
		unset req.http.cookie;
	}

	# Normalize Accept-Encoding header and compression
	# https://www.varnish-cache.org/docs/3.0/tutorial/vary.html
	if (req.http.Accept-Encoding) {
		# Do no compress compressed files...
		if (req.url ~ "\.(jpg|png|gif|gz|tgz|bz2|tbz|mp3|ogg)$") {
			   	remove req.http.Accept-Encoding;
		} elsif (req.http.Accept-Encoding ~ "gzip") {
		    	set req.http.Accept-Encoding = "gzip";
		} elsif (req.http.Accept-Encoding ~ "deflate") {
		    	set req.http.Accept-Encoding = "deflate";
		} else {
			remove req.http.Accept-Encoding;
		}
	}

	# Check the cookies for wordpress-specific items
	if (req.http.Cookie ~ "wordpress_" || req.http.Cookie ~ "comment_") {
		return (pass);
	}
	if (!req.http.cookie) {
		unset req.http.cookie;
	}
	
	# --- End of Wordpress specific configuration

	# Did not cache HTTP authentication and HTTP Cookie
	if (req.http.Authorization || req.http.Cookie) {
		# Not cacheable by default
		return (pass);
	}

	# Define the default grace period to serve cached content
	set req.grace = 30s;
	
	# Cache all others requests
	return (lookup);
}
 
sub vcl_pipe {
	return (pipe);
}
 
sub vcl_pass {
	return (pass);
}
 
# The data on which the hashing will take place
sub vcl_hash {
 	hash_data(req.url);
 	if (req.http.host) {
     	hash_data(req.http.host);
 	} else {
     	hash_data(server.ip);
 	}

	# If the client supports compression, keep that in a different cache
    	if (req.http.Accept-Encoding) {
        	hash_data(req.http.Accept-Encoding);
	}
     
	return (hash);
}
 
sub vcl_hit {
	# Allow purges
	if (req.request == "PURGE") {
		purge;
		error 200 "Purged.";
	}

	return (deliver);
}
 
sub vcl_miss {
	# Allow purges
	if (req.request == "PURGE") {
		purge;
		error 200 "Purged.";
	}
        
	return (fetch);
}

# This function is used when a request is sent by our backend (Nginx server)
sub vcl_fetch {
	# Remove some headers we never want to see
	unset beresp.http.Server;
	unset beresp.http.X-Powered-By;

	# For static content strip all backend cookies
	if (req.url ~ "\.(css|js|png|gif|jp(e?)g)|swf|ico") {
		unset beresp.http.cookie;
	}

	# Only allow cookies to be set if we're in admin area
	if (beresp.http.Set-Cookie && req.url !~ "^/wp-(login|admin)") {
        	unset beresp.http.Set-Cookie;
    	}

	# don't cache response to posted requests or those with basic auth
	if ( req.request == "POST" || req.http.Authorization ) {
        	return (hit_for_pass);
    	}
 
    	# don't cache search results
	if ( req.url ~ "\?s=" ){
		return (hit_for_pass);
	}
    
	# only cache status ok
	if ( beresp.status != 200 ) {
		return (hit_for_pass);
	}

	# A TTL of 24h
	set beresp.ttl = 24h;
	
	return (deliver);
}
 
# The routine when we deliver the HTTP request to the user
# Last chance to modify headers that are sent to the client
sub vcl_deliver {
	if (obj.hits > 0) { 
		set resp.http.X-Cache = "cached";
	} else {
		set resp.http.x-Cache = "uncached";
	}

	# Remove some headers: PHP version
	unset resp.http.X-Powered-By;

	# Remove some headers: Apache version & OS
	unset resp.http.Server;

	# Remove some heanders: Varnish
	unset resp.http.Via;
	unset resp.http.X-Varnish;

	return (deliver);
}
 
sub vcl_init {
 	return (ok);
}
 
sub vcl_fini {
 	return (ok);
}
