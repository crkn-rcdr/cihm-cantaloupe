FROM httpd:2.4.41

RUN sed -i \
    -e 's/^#\(Include .*vhosts.conf\)/\1/' \
    -e 's/^#\(Include .*httpd-mpm.conf\)/\1/' \
    -e 's/^#\(LoadModule .*mod_proxy.so\)/\1/' \
    -e 's/^#\(LoadModule .*mod_proxy_http.so\)/\1/' \
    -e 's/^#\(LoadModule .*mod_proxy_html.so\)/\1/' \
    -e 's/^#\(LoadModule .*mod_xml2enc.so\)/\1/' \
    -e 's/^#\(LoadModule .*mod_rewrite.so\)/\1/' \
    -e 's/^#\(LoadModule .*mod_allowmethods.so\)/\1/' \
    conf/httpd.conf ; \
    sed -i \
    -e 's/logs\/httpd.pid/httpd.pid/' \
    conf/extra/httpd-mpm.conf

ENV CIHM_CANTALOUPE cantaloupe:8182

COPY httpd-vhosts.conf /usr/local/apache2/conf/extra/
EXPOSE 80
