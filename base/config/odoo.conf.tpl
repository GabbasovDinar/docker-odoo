[options]
;------------------------------------------;
; Options not exposed on the command line. ;
;------------------------------------------;

; Sets the master password for administrative tasks
admin_passwd = ${ADMIN_PASSWORD}

; Used to specify the character that Odoo should use as a separator when importing and exporting CSV
csv_internal_sep = ${CSV_INTERNAL_SEP}

; Сonfiguration setting in Odoo that points to the URL used for Odoo's telemetry and publisher warranty services
publisher_warranty_url = ${PUBLISHER_WARRANTY_URL}

; Сontrols whether reports are generated in a gzipped (compressed) format
reportgz = ${REPORTGZ}

; The maximum time in seconds that a WebSocket connection can remain idle before it is closed by the server
websocket_keep_alive_timeout = ${WEBSOCKET_KEEP_ALIVE_TIMEOUT}

; The maximum number of concurrent WebSocket connections that Odoo will allow before rate limiting kicks in
websocket_rate_limit_burst = ${WEBSOCKET_RATE_LIMIT_BURST}

; The delay in seconds between WebSocket connection attempts that exceed the rate limit
websocket_rate_limit_delay = ${WEBSOCKET_RATE_LIMIT_DELAY}

; Odoo source root path
root_path = ${ROOT_PATH}

;-----------------------;
; Server startup config ;
;-----------------------;
; --config | -c
# config = ${ODOO_RC}

; --save
save = ${SAVE}

; --init | -i
init = ${INIT}

; --update | -u
update = ${UPDATE}

; --without-demo
demo = ${DEMO}
without_demo = ${WITHOUT_DEMO}

; --import-partial
import_partial = ${IMPORT_PARTIAL}

; --pidfile
pidfile = ${PIDFILE}

; --addons-path
addons_path = ${ADDONS_PATH}

; --upgrade-path
upgrade_path = ${UPGRADE_PATH}

; --load
server_wide_modules = ${LOAD}

; --data-dir
data_dir = ${DATA_DIR}

;------;
; HTTP ;
;------;
; --http-interface | --xmlrpc-interface
http_interface = ${HTTP_INTERFACE}

; --http-port | -p | --xmlrpc-port
http_port = ${HTTP_PORT}

; --xmlrpcs-interface
xmlrpcs_interface = ${XMLRPCS_INTERFACE}

; --xmlrpcs-port
xmlrpcs_port = ${XMLRPCS_PORT}

; --gevent-port | --longpolling-port (deprecated)
gevent_port = ${GEVENT_PORT}

; --no-http | --no-xmlrpc
http_enable = ${HTTP_ENABLE}

; --no-xmlrpcs
xmlrpcs = ${XMLRPCS}

; --report-url
report.url = ${ODOO_REPORT_URL}

; --proxy-mode
proxy_mode = ${PROXY_MODE}

; --x-sendfile
x_sendfile = ${X_SENDFILE}

;---------------;
; Testing Group ;
;---------------;
; --test-file
test_file = ${TEST_FILE}

; --test-enable
test_enable = ${TEST_ENABLE}

; --test-tags
test_tags = ${TEST_TAGS}

; --screencasts
screencasts = ${SCREENCASTS}

; --screenshots
screenshots = ${SCREENSHOTS}

;---------------;
; Logging Group ;
;---------------;
; --logfile
logfile = ${LOGFILE}

; --syslog
syslog = ${SYSLOG}

; --log-handler | --log-web (--log-handler=odoo.http:DEBUG) | --log-sql (--log-handler=odoo.sql_db:DEBUG)
log_handler = ${LOG_HANDLER}

; --log-db
log_db = ${LOG_DB}

; --log-db-level
log_db_level = ${LOG_DB_LEVEL}

; --log-level
log_level = ${LOG_LEVEL}

;------------;
; SMTP Group ;
;------------;
; --email-from
email_from = ${EMAIL_FROM}

; --from-filter
from_filter = ${FROM_FILTER}

; --smtp
smtp_server = ${SMTP_SERVER}

; --smtp-port
smtp_port = ${SMTP_PORT}

; --smtp-ssl
smtp_ssl = ${SMTP_SSL}

; --smtp-user
smtp_user = ${SMTP_USER}

; --smtp-password
smtp_password = ${SMTP_PASSWORD}

; --smtp-ssl-certificate-filename
smtp_ssl_certificate_filename = ${SMTP_SSL_CERTIFICATE_FILENAME}

; --smtp-ssl-private-key-filename
smtp_ssl_private_key_filename = ${SMTP_SSL_PRIVATE_KEY_FILENAME}

;----------;
; DB Group ;
;----------;
; --database | -d
db_name = ${DB_NAME}

; --db_user | -r
db_user = ${DB_USER}

; --db_password | -w
db_password = ${DB_PASSWORD}

; --pg_path
pg_path = ${PG_PATH}

; --db_host
db_host = ${DB_HOST}

; --db_port
db_port = ${DB_PORT}

; --db_sslmode
db_sslmode = ${DB_SSLMODE}

; --db_maxconn
db_maxconn = ${DB_MAXCONN}

; --db-template
db_template = ${DB_TEMPLATE}

;------------------------------;
; Internationalisation options ;
;------------------------------;
; --load-language
load_language = ${LOAD_LANGUAGE}

; --language
language = ${LANGUAGE}

; --i18n-export
translate_out = ${TRANSLATE_OUT}

; --i18n-import
translate_in = ${TRANSLATE_IN}

; --i18n-overwrite
overwrite_existing_translations = ${OVERWRITE_EXISTING_TRANSLATIONS}

; --modules
translate_modules = ${TRANSLATE_MODULES}

;----------;
; Security ;
;----------;
; --no-database-list
list_db = ${LIST_DB}

;-----;
; WEB ;
;-----;
; --db-filter
dbfilter = ${DBFILTER}

;------------------;
; Advanced options ;
;------------------;
; --dev (all, reload, xml, qweb, werkzeug, sql, shell, assets, tests)
dev_mode = ${DEV_MODE}

; --shell-interface
shell_interface = ${SHELL_INTERFACE}

; --stop-after-init
stop_after_init = ${STOP_AFTER_INIT}

; --osv-memory-count-limit
osv_memory_count_limit = ${OSV_MEMORY_COUNT_LIMIT}

; --transient-age-limit
transient_age_limit = ${TRANSIENT_AGE_LIMIT}

; --max-cron-threads
max_cron_threads = ${MAX_CRON_THREADS}

; --unaccent
unaccent = ${UNACCENT}

; --geoip-db
geoip_database = ${GEOIP_DATABASE}

; --workers
workers = ${WORKERS}

; --limit-memory-soft
limit_memory_soft = ${LIMIT_MEMORY_SOFT}

; --limit-memory-hard
limit_memory_hard = ${LIMIT_MEMORY_HARD}

; --limit-time-cpu
limit_time_cpu = ${LIMIT_TIME_CPU}

; --limit-time-real
limit_time_real = ${LIMIT_TIME_REAL}

; --limit-time-real-cron
limit_time_real_cron = ${LIMIT_TIME_REAL_CRON}

; --limit-request
limit_request = ${LIMIT_REQUEST}

; --- Additional Odoo extra options ---
${ODOO_EXTRA_OPTS}
