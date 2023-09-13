/* MariaDB Review */
/* Script by Edward Stoever for MariaDB Support */

/* ENSURE THIS SCRIPT DOES NOT REPLICATE -- SQL_LOG_BIN=OFF and WSREP_ON=OFF */
SET SESSION SQL_LOG_BIN=OFF; 
/* If not Galera, WSREP_ON=OFF will have no effect. */
SET SESSION WSREP_ON=OFF;

drop schema if exists mariadb_review;

