/* MariaDB Review */
/* Script by Edward Stoever for MariaDB Support */

/* CLEAN UP BY DROPPING THE SCHEMA mariadb_review */
/* SESSION SQL_LOG_BIN=OFF ENSURES THIS WILL NOT REPLICATE OR EFFECT GTIDs. In almost all cases it should be OFF. */
SET SESSION SQL_LOG_BIN=OFF;

drop schema if exists mariadb_review;

