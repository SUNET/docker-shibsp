#!/bin/sh -x

printenv

export HTTP_IP="127.0.0.1"
export HTTP_PORT="8080"
if [ "x${BACKEND_PORT}" != "x" ]; then
   HTTP_IP=`echo "${BACKEND_PORT}" | sed 's%/%%g' | awk -F: '{ print $2 }'`
   HTTP_PORT=`echo "${BACKEND_PORT}" | sed 's%/%%g' | awk -F: '{ print $3 }'`
fi

if [ "x$SP_HOSTNAME" = "x" ]; then
   SP_HOSTNAME="`hostname`"
fi

if [ "x$DISCO_URL" = "x" ]; then
   DISCO_URL="https://md.nordu.net/role/idp.ds"
fi

if [ "x$METADATA_URL" = "x" ]; then
   METADATA_URL="http://mds.swamid.se/md/swamid-idp-transitive.xml"
fi

if [ "x$METADATA_SIGNER" = "x" ]; then
   METADATA_SIGNER="md-signer2.crt"
fi

if [ "x$SP_CONTACT" = "x" ]; then
   SP_CONTACT="info@$SP_CONTACT"
fi

if [ "x$SP_ABOUT" = "x" ]; then
   SP_ABOUT="/about"
fi

if [ "x$HTTP_PROTO" = "x" ]; then
   HTTP_PROTO="http"
fi

if [ "x$BACKEND_URL" = "x" ]; then
   BACKEND_URL="$HTTP_PROTO://$HTTP_IP:$HTTP_PORT/"
fi

if [ -z "$KEYDIR" ]; then
   KEYDIR=/etc/ssl
   mkdir -p $KEYDIR
   export KEYDIR
fi

if [ ! -f "$KEYDIR/private/shibsp-${SP_HOSTNAME}.key" -o ! -f "$KEYDIR/certs/shibsp-${SP_HOSTNAME}.crt" ]; then
   shib-keygen -o /tmp -h $SP_HOSTNAME 2>/dev/null
   mv /tmp/sp-key.pem "$KEYDIR/private/shibsp-${SP_HOSTNAME}.key"
   mv /tmp/sp-cert.pem "$KEYDIR/certs/shibsp-${SP_HOSTNAME}.crt"
fi

if [ ! -f "$KEYDIR/private/${SP_HOSTNAME}.key" -o ! -f "$KEYDIR/certs/${SP_HOSTNAME}.crt" ]; then
   make-ssl-cert generate-default-snakeoil --force-overwrite
   cp /etc/ssl/private/ssl-cert-snakeoil.key "$KEYDIR/private/${SP_HOSTNAME}.key"
   cp /etc/ssl/certs/ssl-cert-snakeoil.pem "$KEYDIR/certs/${SP_HOSTNAME}.crt"
fi

CHAINSPEC=""
export CHAINSPEC
if [ -f "$KEYDIR/certs/${SP_HOSTNAME}.chain" ]; then
   CHAINSPEC="SSLCertificateChainFile $KEYDIR/certs/${SP_HOSTNAME}.chain"
elif [ -f "$KEYDIR/certs/${SP_HOSTNAME}-chain.crt" ]; then
   CHAINSPEC="SSLCertificateChainFile $KEYDIR/certs/${SP_HOSTNAME}-chain.crt"
elif [ -f "$KEYDIR/certs/${SP_HOSTNAME}.chain.crt" ]; then
   CHAINSPEC="SSLCertificateChainFile $KEYDIR/certs/${SP_HOSTNAME}.chain.crt"
elif [ -f "$KEYDIR/certs/chain.crt" ]; then
   CHAINSPEC="SSLCertificateChainFile $KEYDIR/certs/chain.crt"
elif [ -f "$KEYDIR/certs/chain.pem" ]; then
   CHAINSPEC="SSLCertificateChainFile $KEYDIR/certs/chain.pem"
fi

cp /etc/shibboleth/shibboleth2.xml.ORIG /etc/shibboleth/shibboleth2.xml && augtool -s --noautoload --noload <<EOF
set /augeas/load/xml/lens "Xml.lns"
set /augeas/load/xml/incl "/etc/shibboleth/shibboleth2.xml"
load
defvar ad /files/etc/shibboleth/shibboleth2.xml/SPConfig/ApplicationDefaults
set \$ad/#attribute/entityID "https://$SP_HOSTNAME/shibboleth"
set \$ad/Sessions/#attribute/cookieProps "https"
set \$ad/Sessions/#attribute/handlerSSL "true"
set \$ad/Sessions/SSO/#attribute/discoveryProtocol "SAMLDS"
rm \$ad/Sessions/SSO/#attribute/entityID
set \$ad/Sessions/SSO/#attribute/discoveryURL "$DISCO_URL"
set \$ad/Errors/#attribute/supportContact "$SP_CONTACT"
set \$ad/Errors/#attribute/helpLocation "$SP_ABOUT"
ins MetadataProvider after \$ad/Errors[1]
defvar mdp \$ad/MetadataProvider[1]
set \$mdp/#attribute/uri "$METADATA_URL"
set \$mdp/#attribute/type "XML"
set \$mdp/#attribute/backingFilePath "metadata.xml"
set \$mdp/#attribute/reloadInterval "7200"
set \$mdp/MetadataFilter[1]/#attribute/type "RequireValidUntil"
set \$mdp/MetadataFilter[1]/#attribute/maxValidityInterval "2419200"
set \$mdp/MetadataFilter[2]/#attribute/type "Signature"
set \$mdp/MetadataFilter[2]/#attribute/certificate "$METADATA_SIGNER"
defvar cr /files/etc/shibboleth/shibboleth2.xml/SPConfig/ApplicationDefaults/CredentialResolver
set \$cr/#attribute/type "File"
set \$cr/#attribute/key "$KEYDIR/private/shibsp-${SP_HOSTNAME}.key"
set \$cr/#attribute/certificate "$KEYDIR/certs/shibsp-${SP_HOSTNAME}.crt"
EOF

cp /etc/apache2/sites-available/default.conf.ORIG /etc/apache2/sites-available/default.conf && augtool -s --noautoload --noload <<EOF
set /augeas/load/httpd/lens "Httpd.lns"
set /augeas/load/httpd/incl "/etc/apache2/sites-available/default.conf"
load
set /files/etc/apache2/sites-available/default.conf/*[self::directive="ServerName"]/arg "$SP_HOSTNAME"
defvar vh /files/etc/apache2/sites-available/default.conf/VirtualHost
set \$vh/*[self::directive="ServerName"]/arg "$SP_HOSTNAME"
set \$vh/*[self::directive="ServerAdmin"]/arg "$SP_CONTACT"

set \$vh/directive[last()+1] "ProxyPass"
set \$vh/directive[last()]/arg[1] "/"
set \$vh/directive[last()]/arg[2] "$BACKEND_URL"

set \$vh/directive[last()+1] "ProxyPassReverse"
set \$vh/directive[last()]/arg[1] "/"
set \$vh/directive[last()]/arg[2] "$BACKEND_URL"
EOF

echo "----"
cat /etc/shibboleth/shibboleth2.xml
echo "----"
cat /etc/apache2/sites-available/default.conf

service shibd start

rm -f /var/run/apache2/apache2.pid

env APACHE_LOCK_DIR=/var/lock/apache2 APACHE_RUN_DIR=/var/run/apache2 APACHE_PID_FILE=/var/run/apache2/apache2.pid APACHE_RUN_USER=www-data APACHE_RUN_GROUP=www-data APACHE_LOG_DIR=/var/log/apache2 apache2 -DFOREGROUND
