backend default  {
        .host = "10.196.XXX.XX";
        .port = "80";
}

sub set_backends {
        set req.backend_hint = default;
}

#Hosts allowed to purge the cache
acl acl_purge {
        # localhost
        "127.0.0.1";
        # postes bureautiques STI
        "10.196.XXX.0"/25;
        # postes bureautiques Prodstaff/SNSI
        "10.196.XXX.0"/24;
        # EUISAFR019 Contient l outil de decache
        "10.196.XXX.XXX";
}

sub vcl_recv {
        # Happens before we check if we have this in cache already.

        # Check the request method
        if ( req.method != "GET"
			 && req.method != "HEAD"
			 && req.method != "POST"
			 && req.method != "PURGE"  ) {
                return (synth(403, "Forbidden"));
        }

        # Gestion du Healthcheck
        if ( req.http.host == "healthcheck" ) {
                return (synth(204, "No Content"));
        }

        #Gestion du X-Forwarded-For
        if ( req.restarts == 0 ) {
                if (req.http.x-forwarded-for) {
                        set req.http.X-Forwarded-For = req.http.X-Forwarded-For + ", " + client.ip;
                } else {
                        set req.http.X-Forwarded-For = client.ip;
                }
        }

        # Manage PURGE request
        if (req.method == "PURGE") {
                if (client.ip ~ acl_purge ) {
                        return(purge);
                } else {
                        return(synth(403, "Access denied."));
                }
        }

        # Backend default function
        call set_backends;
}


sub vcl_hash {

    hash_data(req.url);
    if (req.http.host) {
        hash_data(req.http.host);
    } else {
        hash_data(server.ip);
    }
    return (lookup);

}

sub vcl_deliver {}

# Gestion des Retours de type Synth
sub vcl_synth {
# Gestion du cas spécifique 204
    if (resp.status == 204) {
        set resp.http.Content-Type = "text/plain;";
        synthetic( {""} );
        return (deliver);
    }
# Gestion des autres cas
    set resp.http.Content-Type = "text/html; charset=utf-8";
    set resp.http.Retry-After = "5";
    synthetic( {"<!DOCTYPE html>
<html>
  <head>
    <title>"} + resp.status + " " + resp.reason + {"</title>
  </head>
  <body>
    <h1>Error "} + resp.status + " " + resp.reason + {"</h1>
    <p>"} + resp.reason + {"</p>
    <h3>Guru Meditation:</h3>
    <p>XID: "} + req.xid + {"</p>
    <hr>
    <p>Varnish cache server</p>
  </body>
</html>
"} );
    return (deliver);
}

sub vcl_backend_response {
        set beresp.grace = 2m;
}
