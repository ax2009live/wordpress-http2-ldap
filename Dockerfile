FROM ubuntu:20.04

ENV APACHE_CONFDIR /etc/apache2
ENV APACHE_ENVVARS $APACHE_CONFDIR/envvars
ENV PHP_INI_DIR /etc/php/7.4/fpm

COPY docker-php-ext-enable docker-entrypoint.sh apache2-foreground docker-php-ext-configure  docker-php-ext-install  docker-php-source /usr/local/bin/
COPY php.tar.xz /usr/src/

RUN set -eux; \
		export DEBIAN_FRONTEND="noninteractive"; \
        	apt-get update; \
        	apt-get install -y --no-install-recommends \
        	php-fpm \
        	binutils \
        	libapache2-mod-php \
        	libfreetype6-dev \
		libjpeg-dev \
		libmagickwand-dev \
		libpng-dev \
		libzip-dev \
        	php-mysql \
        	php-gd \
        	php-imagick \
        	apache2 \
        	php-curl \
        	php-dom \
        	php-mbstring \
        	php-xml \
        	php-bcmath \
        	php-json \
        	php-readline \
        	php-zip \        	
        	xz-utils \ 
        	ca-certificates \
        	curl ;\        	
        	rm -rf /var/lib/apt/lists/* ;\
       		# generically convert lines like
			#   export APACHE_RUN_USER=www-data
			# into
			#   : ${APACHE_RUN_USER:=www-data}
			#   export APACHE_RUN_USER
			# so that they can be overridden at runtime ("-e APACHE_RUN_USER=...")
				sed -ri 's/^export ([^=]+)=(.*)$/: ${\1:=\2}\nexport \1/' "$APACHE_ENVVARS"; \
				\
			# setup directories and permissions
				. "$APACHE_ENVVARS"; \
				for dir in \
					"$APACHE_LOCK_DIR" \
					"$APACHE_RUN_DIR" \
					"$APACHE_LOG_DIR" \
				; do \
					rm -rvf "$dir"; \
					mkdir -p "$dir"; \
					chown "$APACHE_RUN_USER:$APACHE_RUN_GROUP" "$dir"; \
			# allow running as an arbitrary user (https://github.com/docker-library/php/issues/743)
					chmod 777 "$dir"; \
				done; \
				\
			# delete the "index.html" that installing Apache drops in here
				rm -rvf /var/www/html/*; \
				\
			# logs should go to stdout / stderr
				ln -sfT /dev/stderr "$APACHE_LOG_DIR/error.log"; \
				ln -sfT /dev/stdout "$APACHE_LOG_DIR/access.log"; \
				ln -sfT /dev/stdout "$APACHE_LOG_DIR/other_vhosts_access.log"; \
				chown -R --no-dereference "$APACHE_RUN_USER:$APACHE_RUN_GROUP" "$APACHE_LOG_DIR" 
				

RUN set -eux; \
		a2dismod php7.4 mpm_prefork;\
		a2enmod headers proxy_fcgi setenvif mpm_event http2 ssl;\
		a2enconf php7.4-fpm 




RUN set -eux; \
        docker-php-ext-enable opcache; \
        { \
                echo 'opcache.memory_consumption=128'; \
                echo 'opcache.interned_strings_buffer=8'; \
                echo 'opcache.max_accelerated_files=4000'; \
                echo 'opcache.revalidate_freq=2'; \
                echo 'opcache.fast_shutdown=1'; \
        } > $PHP_INI_DIR/conf.d/opcache-recommended.ini


RUN { \
## https://www.php.net/manual/en/errorfunc.constants.php
## https://github.com/docker-library/wordpress/issues/420#issuecomment-517839670
                #echo 'error_reporting = E_ERROR | E_WARNING | E_PARSE | E_CORE_ERROR | E_CORE_WARNING | E_COMPILE_ERROR | E_COMPILE_WARNING | E_RECOVERABLE_ERROR'; \
                echo 'display_errors = Off'; \
                echo 'display_startup_errors = Off'; \
                echo 'log_errors = On'; \
                echo 'error_log = /dev/stderr'; \
                echo 'log_errors_max_len = 1024'; \
                echo 'ignore_repeated_errors = On'; \
                echo 'ignore_repeated_source = Off'; \
                echo 'html_errors = Off'; \
        } > $PHP_INI_DIR/conf.d/error-logging.ini


RUN { \
		echo '<FilesMatch \.php$>'; \
		echo '\tSetHandler application/x-httpd-php'; \
		echo '</FilesMatch>'; \
		echo; \
		echo 'DirectoryIndex disabled'; \
		echo 'DirectoryIndex index.php index.html'; \
		echo; \
		echo '<Directory /var/www/html/ >'; \
		echo '\tOptions -Indexes'; \
		echo '\tAllowOverride All'; \
		echo '</Directory>'; \
	} | tee "/etc/apache2/conf-available/docker-php.conf" \
	&& a2enconf docker-php


ENV WORDPRESS_VERSION 5.5
ENV WORDPRESS_SHA1 03fe1a139b3cd987cc588ba95fab2460cba2a89e


RUN set -ex; \
        curl -o wordpress.tar.gz -fSL "https://wordpress.org/wordpress-${WORDPRESS_VERSION}.tar.gz"; \
        echo "$WORDPRESS_SHA1 *wordpress.tar.gz" | sha1sum -c -; \
# upstream tarballs include ./wordpress/ so this gives us /usr/src/wordpress
        tar -xzf wordpress.tar.gz -C /usr/src/; \
        rm wordpress.tar.gz; \
        chown -R www-data:www-data /usr/src/wordpress; \
# pre-create wp-content (and single-level children) for folks who want to bind-mount themes, etc so permissions are pre-created properly instead of root:root
        mkdir wp-content; \
        for dir in /usr/src/wordpress/wp-content/*/; do \
                dir="$(basename "${dir%/}")"; \
                mkdir "wp-content/$dir"; \
        done; \
        chown -R www-data:www-data wp-content; \
        chmod -R 777 wp-content

RUN set -eux; \
	a2enmod rewrite expires; \
	\
# https://httpd.apache.org/docs/2.4/mod/mod_remoteip.html
	a2enmod remoteip; \
	{ \
		echo 'RemoteIPHeader X-Forwarded-For'; \
# these IP ranges are reserved for "private" use and should thus *usually* be safe inside Docker
		echo 'RemoteIPTrustedProxy 10.0.0.0/8'; \
		echo 'RemoteIPTrustedProxy 172.16.0.0/12'; \
		echo 'RemoteIPTrustedProxy 192.168.0.0/16'; \
		echo 'RemoteIPTrustedProxy 169.254.0.0/16'; \
		echo 'RemoteIPTrustedProxy 127.0.0.0/8'; \
	} > /etc/apache2/conf-available/remoteip.conf; \
	a2enconf remoteip; \
# https://github.com/docker-library/wordpress/issues/383#issuecomment-507886512
# (replace all instances of "%h" with "%a" in LogFormat)
	find /etc/apache2 -type f -name '*.conf' -exec sed -ri 's/([[:space:]]*LogFormat[[:space:]]+"[^"]*)%h([^"]*")/\1%a\2/g' '{}' +
	
RUN set -x \
    && apt-get update \
    && apt-get install -y \
    php-dev \
    libldap2-dev \    
    && docker-php-ext-configure ldap --with-libdir=lib/x86_64-linux-gnu/ \
    && docker-php-ext-install ldap \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get purge -y --auto-remove libldap2-dev

VOLUME /usr/src/wordpress



WORKDIR /var/www/html

STOPSIGNAL SIGQUIT

ENTRYPOINT ["docker-entrypoint.sh"]

CMD ["apache2-foreground"]
