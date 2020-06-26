#!/bin/bash

if ! [ -x "$(command -v docker-compose)" ]; then
  echo 'Error: docker-compose is not installed.' >&2
  exit 1
fi

# put your multi domain here, separated by space. Don't forget make nginx multi domain conf
domains=(your-domain1.com your-sub.domain2.org your-multi-sub.domain3.net)

rsa_key_size=4096
data_path="./data/certbot"

email="" # Adding a valid address is strongly recommended, please add your own email !
staging=1 # Set to 1 if you're testing your setup to avoid hitting request limits, set 0 for production env.

echo "List of domains(s) :"
for domain in ${domains[@]}; do
  echo " - $domain"
done

echo
echo "Your email : $email ..." 
echo

if [ -d "$data_path" ]; then
  read -p "Your data maybe exist for this domain(s). Continue and replace existing certificate? (y/N) " decision
  if [ "$decision" != "Y" ] && [ "$decision" != "y" ]; then
    exit
  fi
fi

if [ ! -e "$data_path/conf/options-ssl-nginx.conf" ] || [ ! -e "$data_path/conf/ssl-dhparams.pem" ]; then
  echo "### Downloading recommended TLS parameters ..."
  mkdir -p "$data_path/conf"
  curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot-nginx/certbot_nginx/_internal/tls_configs/options-ssl-nginx.conf > "$data_path/conf/options-ssl-nginx.conf"
  curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot/certbot/ssl-dhparams.pem > "$data_path/conf/ssl-dhparams.pem"
  echo
fi

for domain in ${domains[@]}; do
  echo "### Creating directory certificate for $domain ..."
  path="/etc/letsencrypt/live/$domain"
  mkdir -p "$data_path/conf/live/$domain"

  echo "### Creating dummy certificate for $domain ..."
  docker-compose run --rm --entrypoint "\
    openssl req -x509 -nodes -newkey rsa:2048 -days 1\
      -keyout '$path/privkey.pem' \
      -out '$path/fullchain.pem' \
      -subj '/CN=localhost'" certbot
  echo
done

echo "### Starting nginx container ..."
docker-compose up --force-recreate -d nginx
echo

for domain in ${domains[@]}; do
  echo "### Deleting dummy certificate for $domain ..."
    docker-compose run --rm --entrypoint "\
      rm -Rf /etc/letsencrypt/live/$domain && \
      rm -Rf /etc/letsencrypt/archive/$domain && \
      rm -Rf /etc/letsencrypt/renewal/$domain.conf" certbot
    echo
done

for domain in ${domains[@]}; do
  echo "### Generating args / parameters for $domain ..."
  domain_args=""
  #Join $domains to -d args
  domain_args="$domain_args -d $domain"

  # Select appropriate email arg
  case "$email" in
    "") email_arg="--register-unsafely-without-email" ;;
    *) email_arg="--email $email" ;;
  esac

  # Enable staging mode if needed
  if [ $staging != "0" ]; then staging_arg="--staging"; fi

  echo "### Requesting Let's Encrypt certificate for $domain ..."
  docker-compose run --rm --entrypoint " \
    certbot certonly --webroot -w /var/www/certbot \
      $staging_arg \
      $email_arg \
      $domain_args \
      --rsa-key-size $rsa_key_size \
      --agree-tos \
      --force-renewal" certbot
  echo
done

echo "### Reloading nginx service ..."
docker-compose exec nginx nginx -s reload
