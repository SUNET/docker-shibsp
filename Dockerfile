FROM debian:stable
MAINTAINER leifj@sunet.se
RUN echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections
RUN apt-get update
RUN apt-get -y install apache2 libapache2-mod-shib2 ssl-cert augeas-tools
RUN a2enmod rewrite
RUN a2enmod shib
RUN a2enmod proxy
RUN a2enmod proxy_http
ENV SP_HOSTNAME localhost
ENV SP_CONTACT root@localhost
ENV SP_ABOUT /about
ENV DISCO_URL https://use.this.io/ds/
ENV METADATA_URL http://mds.edugain.org/
ENV METADATA_SIGNER mds-v1.cer
RUN rm -f /etc/apache2/sites-available/*
ADD config /etc/apache2/sites-available/default.conf
RUN rm -f /etc/apache2/sites-enabled/*
RUN a2ensite default
ADD start.sh /start.sh
RUN chmod a+rx /start.sh
ADD md-signer.crt /etc/shibboleth/md-signer.crt
RUN cp /etc/apache2/sites-available/default.conf /etc/apache2/sites-available/default.conf.ORIG
RUN cp /etc/shibboleth/shibboleth2.xml /etc/shibboleth/shibboleth2.xml.ORIG
ADD attribute-map.xml /etc/shibboleth/attribute-map.xml
EXPOSE 80
EXPOSE 443
VOLUME /credentials
ENTRYPOINT ["/start.sh"]
