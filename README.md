# wordpress-http2-ldap
The WordPress 5.5 docker image with apache2 (http2 &amp; LDAP). The image based on Ubuntu 20.04, php-fpm-7.4 

https://hub.docker.com/r/ax2009live/wordpress-http2-ldap

	Create gateway
		
		docker network create --driver bridge --subnet=172.18.0.0/24 --gateway=172.18.0.1 mynet
		
		
	Create database container
		
    docker run -d \
                --restart=always \
                --name  mariadb \
                -e  MYSQL_DATABASE=mariadb \
                -e MYSQL_USER=user \
                -e MYSQL_PASSWORD='password' \
                -e MYSQL_RANDOM_ROOT_PASSWORD='1' \
                -v /root/nginx/wordpress/db:/var/lib/mysql \
                -p 3306:3306 \
                --network=mynet --ip 172.18.0.10 \
                bianjp/mariadb-alpine
					
					
	Create WordPress container
		
    docker run -d \
                --restart=always \
                --name wordpress \
                -v /root/apache2:/etc/apache2/sites-enabled \
                -v /root/nginx/wordpress:/var/www/html \
                -v /root/nginx/certs:/root/nginx/certs \
                -p 80.:80 -p 443:443 \
                --network=mynet --ip 172.18.0.20 \
                ax2009live/wordpress-http2-ldap:5.5
		
	https://host-ip
	


https://bb.ax2009live.com/install-the-certificate-automatically-update-every-month/

/root/nginx/certs: fullchain.pem key.pem

/root/apache2: 000-default.conf default-ssl.conf

https://github.com/ax2009live/wordpress-http2-ldap/tree/main/apache2

default-ssl.conf: 
		

          server {
                 …… 
                SSLEngine on


                #   A self-signed (snakeoil) certificate can be created by installing
                #   the ssl-cert package. See
                #   /usr/share/doc/apache2/README.Debian.gz for more info.
                #   If both key and certificate are stored in the same file, only the
                #   SSLCertificateFile directive is needed.
                SSLCertificateFile      /root/nginx/certs/fullchain.pem
                SSLCertificateKeyFile   /root/nginx/certs/key.pem
                
               # RemoteIPProxyProtocol On
               # RemoteIPHeader X-Forwarded-For
               # RemoteIPInternalProxy 172.18.0.1<proxy ip>
                # Get the user's real IP address, Delete # on the top three lines

                Protocols h2  http/1.1
           ……
           } 
