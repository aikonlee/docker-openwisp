#!/bin/sh
# OpenWISP common module init script
set -e
. ./utils.sh

init_conf

# Start services
if [ "$MODULE_NAME" = 'dashboard' ]; then
	if [ "$OPENWISP_GEOCODING_CHECK" = 'True' ]; then
		python manage.py check --deploy --tag geocoding
	fi
	python services.py database redis
	python manage.py migrate --noinput
	test -f "$SSH_PRIVATE_KEY_PATH" || ssh-keygen -t ed25519 -f "$SSH_PRIVATE_KEY_PATH" -N ""
	python load_init_data.py
	python collectstatic.py
	start_uwsgi
elif [ "$MODULE_NAME" = 'postfix' ]; then
	postfix_config
	postfix set-permissions
	postfix start
	rsyslogd -n
elif [ "$MODULE_NAME" = 'freeradius' ]; then
	# Ensure rest module is not enabled at runtime (some builds may include
	# rest files). Remove any rest* files from mods-enabled before starting.
	rm -f /etc/raddb/mods-enabled/*rest* || true
	wait_nginx_services
	# Wait for DB schema required by FreeRADIUS (e.g. 'nas' table) to exist
	# This prevents radiusd from exiting with 'relation "nas" does not exist'.
	# Use PGPASSWORD/PGHOST/PGPORT/PGUSER from env (set in Dockerfile).
	set +e
	echo "Waiting for database schema (nas table) to be available..."
	FOUND=0
	for i in $(seq 1 60); do
		psql -qtAX -c "SELECT to_regclass('public.nas');" 2>/dev/null | grep -q "nas" && {
			echo "DB schema present"
			FOUND=1
			break
		} || true
		sleep 2
	done
	set -e
	if [ "$FOUND" != "1" ]; then
		echo "Warning: 'nas' table not found after timeout; FreeRADIUS may fail to load clients from SQL. Continuing startup."
	fi
	# Some base images provide a docker-entrypoint.sh that sets up and runs
	# freeradius. If it's missing (we use alpine + apk), fall back to calling
	# radiusd directly. In debug mode run in foreground (-X) for logs.
	# Prefer docker-entrypoint.sh if present in any common locations
	if [ -f ./docker-entrypoint.sh ]; then
		ENTRYPOINT=./docker-entrypoint.sh
	elif [ -f /docker-entrypoint.sh ]; then
		ENTRYPOINT=/docker-entrypoint.sh
	elif [ -f /usr/local/bin/docker-entrypoint.sh ]; then
		ENTRYPOINT=/usr/local/bin/docker-entrypoint.sh
	else
		ENTRYPOINT=
	fi
	if [ -n "$ENTRYPOINT" ]; then
		# Exec the entrypoint so it becomes PID 1 (keeps container running)
		if [ "$DEBUG_MODE" = 'False' ]; then
			exec "$ENTRYPOINT"
		else
			exec "$ENTRYPOINT" -X
		fi
	else
		# Fallback to running radiusd directly. Exec so radiusd becomes PID 1
		if [ "$DEBUG_MODE" = 'False' ]; then
			exec radiusd -f
		else
			exec radiusd -X
		fi
	fi
elif [ "$MODULE_NAME" = 'openvpn' ]; then
	if [[ -z "$VPN_DOMAIN" ]]; then exit; fi
	wait_nginx_services
	openvpn_preconfig
	openvpn_config
	openvpn_config_download
	crl_download
	echo "*/1 * * * * sh /openvpn.sh" | crontab -
	(
		crontab -l
		echo "0 0 * * * sh /revokelist.sh"
	) | crontab -
	crond
	# Schedule send topology script only when
	# network topology module is enabled.
	if [ "$USE_OPENWISP_TOPOLOGY" == "True" ]; then
		init_send_network_topology
	fi
	# Supervisor is used to start the service because OpenVPN
	# needs to restart after crl list is updated or configurations
	# are changed. If OpenVPN as the service keeping the
	# docker container running, restarting would mean killing
	# the container while supervisor helps only to restart the service!
	supervisord --nodaemon --configuration supervisord.conf
elif [ "$MODULE_NAME" = 'nginx' ]; then
	rm -rf /etc/nginx/conf.d/default.conf
	if [ "$NGINX_CUSTOM_FILE" = 'True' ]; then
		nginx -g 'daemon off;'
	fi
	# Expand escape sequences in the optional events block so it can be injected
	# correctly into the nginx configuration template.
	NGINX_EVENTS_BLOCK=$(printf "%b" "${NGINX_EVENTS_BLOCK:-}")
	export NGINX_EVENTS_BLOCK
	# Use a sentinel value when the variable is unset. Since envsubst cannot
	# conditionally omit directives, we later remove any line containing this
	# sentinel from the generated nginx.conf.
	export NGINX_WORKER_RLIMIT_NOFILE="${NGINX_WORKER_RLIMIT_NOFILE:-__UNSET__}"
	envsubst </etc/nginx/nginx.template.conf >/etc/nginx/nginx.conf
	# Remove incomplete worker_rlimit_nofile directives if env var is unset or empty
	sed -i '/__UNSET__/d; /^worker_rlimit_nofile *$/d; /^[[:space:]]*$/d' /etc/nginx/nginx.conf
	envsubst_create_config /etc/nginx/openwisp.internal.template.conf internal INTERNAL
	if [ "$SSL_CERT_MODE" = 'Yes' ]; then
		nginx_prod
	elif [ "$SSL_CERT_MODE" = 'SelfSigned' ]; then
		nginx_dev
	else
		envsubst_create_config /etc/nginx/openwisp.template.conf http DOMAIN
	fi
	nginx -g 'daemon off;'
elif [ "$MODULE_NAME" = 'celery' ]; then
	python services.py database redis dashboard
	echo "Starting the 'default' celery worker"
	celery -A openwisp worker -l ${DJANGO_LOG_LEVEL} --queues celery \
		-n celery@%h --logfile /opt/openwisp/logs/celery.log \
		--pidfile /opt/openwisp/celery.pid --detach \
		${OPENWISP_CELERY_COMMAND_FLAGS}

	if [ "$USE_OPENWISP_CELERY_NETWORK" = "True" ]; then
		echo "Starting the 'network' celery worker"
		celery -A openwisp worker -l ${DJANGO_LOG_LEVEL} --queues network \
			-n network@%h --logfile /opt/openwisp/logs/celery_network.log \
			--pidfile /opt/openwisp/celery_network.pid --detach \
			${OPENWISP_CELERY_NETWORK_COMMAND_FLAGS}
	fi

	if [[ "$USE_OPENWISP_FIRMWARE" == "True" && "$USE_OPENWISP_CELERY_FIRMWARE" == "True" ]]; then
		echo "Starting the 'firmware_upgrader' celery worker"
		celery -A openwisp worker -l ${DJANGO_LOG_LEVEL} --queues firmware_upgrader \
			-n firmware_upgrader@%h --logfile /opt/openwisp/logs/celery_firmware_upgrader.log \
			--pidfile /opt/openwisp/celery_firmware_upgrader.pid --detach \
			${OPENWISP_CELERY_FIRMWARE_COMMAND_FLAGS}
	fi
	sleep 1s
	tail -f /opt/openwisp/logs/*
elif [ "$MODULE_NAME" = 'celery_monitoring' ]; then
	python services.py database redis dashboard
	if [[ "$USE_OPENWISP_MONITORING" == "True" && "$USE_OPENWISP_CELERY_MONITORING" == 'True' ]]; then
		echo "Starting the 'monitoring' celery worker"
		celery -A openwisp worker -l ${DJANGO_LOG_LEVEL} --queues monitoring \
			-n monitoring@%h --logfile /opt/openwisp/logs/celery_monitoring.log \
			--pidfile /opt/openwisp/celery_monitoring.pid --detach \
			${OPENWISP_CELERY_MONITORING_COMMAND_FLAGS}
		echo "Starting the 'monitoring_checks' celery worker"
		celery -A openwisp worker -l ${DJANGO_LOG_LEVEL} --queues monitoring_checks \
			-n monitoring_checks@%h --logfile /opt/openwisp/logs/celery_monitoring_checks.log \
			--pidfile /opt/openwisp/celery_monitoring_checks.pid --detach \
			${OPENWISP_CELERY_MONITORING_CHECKS_COMMAND_FLAGS}
		sleep 1s
		tail -f /opt/openwisp/logs/*
	else
		echo "Monitoring queues are not activated, exiting."
	fi
elif [ "$MODULE_NAME" = 'celerybeat' ]; then
	rm -rf celerybeat.pid
	python services.py database redis dashboard
	celery -A openwisp beat -l ${DJANGO_LOG_LEVEL}
else
	python services.py database redis dashboard
	start_uwsgi
fi
