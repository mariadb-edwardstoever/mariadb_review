/* MariaDB Review */
/* Script by Edward Stoever for MariaDB Support */
/* This script was updated at SCRIPT VERSION 1.7.0 */

/* If you need to override hostname check to drop schema no matter on which host it was created, */
/* change to OVERRIDE_HOSTNAME_CHECK to 'YES'. */
SET @OVERRIDE_HOSTNAME_CHECK='NO';

/* DO NOT CHAGE VALUES BELOW THIS LINE */
set @DO_NOTHING='NO'; -- DEFAULT
SET @PREVIOUS_REPLICATE='YES'; -- DEFAULT
SET @MUST_DROP='TRUE'; -- DEFAULT

/* TOPOLOGY  IS_PRIMARY, IS_GALERA */
 select if(VARIABLE_VALUE>0,'YES','NO') into @IS_PRIMARY
  from information_schema.global_status 
  where VARIABLE_NAME='SLAVES_CONNECTED';
  
select if(sum(VARIABLE_VALUE)>0,'YES','NO') into @IS_REPLICA
  from information_schema.global_status 
  where VARIABLE_NAME in ('SLAVE_RECEIVED_HEARTBEATS','RPL_SEMI_SYNC_SLAVE_SEND_ACK','SLAVES_RUNNING');

select if(VARIABLE_VALUE > 0,'YES','NO') into @IS_GALERA 
  from information_schema.global_status 
  where VARIABLE_NAME='WSREP_THREAD_COUNT';

set @MARIADB_REVIEW_SCHEMA_EXISTS='NO';
select 'YES' into @MARIADB_REVIEW_SCHEMA_EXISTS from information_schema.SCHEMATA
where SCHEMA_NAME='mariadb_review' LIMIT 1;

set @CURRENT_RUN_EXISTS='NO';
select 'YES' into @CURRENT_RUN_EXISTS from information_schema.TABLES 
where TABLE_SCHEMA='mariadb_review' 
and TABLE_NAME='CURRENT_RUN' LIMIT 1;

/* AUTHORIZED_TO_SQL_LOG_BIN */
delimiter //
begin not atomic
DECLARE CONTINUE HANDLER FOR 1227
   begin
      set @AUTHORIZED_TO_SQL_LOG_BIN='FALSE';
   end;
SELECT SESSION_VALUE into @SESS_SQL_LOG_BIN FROM information_schema.SYSTEM_VARIABLES WHERE VARIABLE_NAME ='SQL_LOG_BIN';
set session sql_log_bin=@SESS_SQL_LOG_BIN;
IF @AUTHORIZED_TO_SQL_LOG_BIN IS NULL THEN SET @AUTHORIZED_TO_SQL_LOG_BIN='TRUE'; END IF;
end;
//
delimiter ;

/* AUTHORIZED_TO_WSREP_ON */
delimiter //
begin not atomic
DECLARE CONTINUE HANDLER FOR 1227
   begin
      set @AUTHORIZED_TO_WSREP_ON='FALSE';
   end;
SELECT SESSION_VALUE into @SESS_WSREP_ON FROM information_schema.SYSTEM_VARIABLES WHERE VARIABLE_NAME ='WSREP_ON';
set session wsrep_on=@SESS_WSREP_ON;
IF @AUTHORIZED_TO_WSREP_ON IS NULL THEN SET @AUTHORIZED_TO_WSREP_ON='TRUE'; END IF;
end;
//
delimiter ;

delimiter //
begin not atomic
/* OVERRIDE_HOSTNAME_CHECK? */
if @OVERRIDE_HOSTNAME_CHECK='YES' then
  update mariadb_review.CURRENT_RUN set `RUN_ON` = @@hostname where 1=1;
end if;


/* IS CURRENT_RUN RECENT VERSION? */
SET @RECENT='NO';
select 'YES' into @RECENT from information_schema.COLUMNS 
where TABLE_NAME='CURRENT_RUN' 
and TABLE_SCHEMA='mariadb_review' 
and COLUMN_NAME='REPLICATE';

/* GET CURRENT VALUES FOR SQL_LOG_BIN AND WSREP_ON */
if @CURRENT_RUN_EXISTS='YES' then
 if @RECENT='NO' then
  SET @SESS_SQL_LOG_BIN='OFF'; SET @SESS_WSREP_ON='OFF'; SET @PREVIOUS_REPLICATE='NO';
 else
  SELECT SESSION_SQL_LOG_BIN into @SESS_SQL_LOG_BIN FROM mariadb_review.CURRENT_RUN ORDER BY RUN_START DESC limit 1;
  SELECT SESSION_WSREP_ON    into @SESS_WSREP_ON    FROM mariadb_review.CURRENT_RUN ORDER BY RUN_START DESC limit 1;
  SELECT `REPLICATE` into @PREVIOUS_REPLICATE       FROM mariadb_review.CURRENT_RUN ORDER BY RUN_START DESC limit 1;
  SELECT `RUN_ON` into @PREVIOUS_HOST               FROM mariadb_review.CURRENT_RUN ORDER BY RUN_START DESC limit 1;
end if;
end if;

/* IF PREVIOUS HOSTNAME DOES NOT MATCH, DEMAND CLEAN UP */
IF @PREVIOUS_HOST != @@hostname AND @CURRENT_RUN_EXISTS='YES' AND @RECENT='YES' THEN
if @IS_REPLICA = 'YES' OR @IS_GALERA = 'YES' THEN
  set @DO_NOTHING='YES';
  select concat('It appears the schema mariadb_review was created on a different server and replicated here.') as `NOTE`;
  select concat('Use the clean_up.sql script on the host ',@PREVIOUS_HOST,' before running scripts on this host.') as `NOTE`;
END IF;
END IF;

end;
//
delimiter ;

delimiter //
begin not atomic
IF @IS_PRIMARY='YES' AND @PREVIOUS_REPLICATE!='YES' AND @AUTHORIZED_TO_SQL_LOG_BIN='FALSE' THEN
  set @DO_NOTHING='YES';
  select concat('This is a master. Previous REPLICATE=NO and user has insufficient privileges. Doing nothing.') as NOTE;
END IF;

IF @IS_GALERA='YES' AND @PREVIOUS_REPLICATE!='YES' AND @AUTHORIZED_TO_WSREP_ON='FALSE' THEN
  set @DO_NOTHING='YES';
  select concat('This is a Galera server. Previous REPLICATE=NO and user has insufficient privileges. Doing nothing.') as NOTE;
END IF;
end;
//
delimiter ;

delimiter //
begin not atomic

if @MARIADB_REVIEW_SCHEMA_EXISTS = 'YES' THEN

if @MUST_DROP='TRUE' AND @DO_NOTHING != 'YES' THEN

if @SESS_SQL_LOG_BIN = 'OFF' and @AUTHORIZED_TO_SQL_LOG_BIN='TRUE' THEN
  SET SESSION SQL_LOG_BIN=OFF; 
end if;

if @SESS_WSREP_ON = 'OFF' and @IS_GALERA = 'YES' and @AUTHORIZED_TO_WSREP_ON='TRUE' THEN
  SET SESSION WSREP_ON=OFF;
end if;

  WITH IS_REPLICATING as (
  SELECT 
  (select if(VARIABLE_VALUE > 0,'YES','NO') from information_schema.global_status where VARIABLE_NAME='SLAVES_CONNECTED') as IS_MASTER,
  (  select if(sum(VARIABLE_VALUE)>0,'YES','NO')
     from information_schema.global_status 
     where VARIABLE_NAME in
      ('SLAVE_RECEIVED_HEARTBEATS','RPL_SEMI_SYNC_SLAVE_SEND_ACK','SLAVES_RUNNING')) as IS_REPLICA,
  (select if(VARIABLE_VALUE > 0,'YES','NO') from information_schema.global_status where VARIABLE_NAME='WSREP_THREAD_COUNT') as IS_GALERA,
  (SELECT SESSION_VALUE  FROM information_schema.SYSTEM_VARIABLES WHERE VARIABLE_NAME ='SQL_LOG_BIN') as `SESSION SQL_LOG_BIN`,
  (SELECT SESSION_VALUE FROM information_schema.SYSTEM_VARIABLES WHERE VARIABLE_NAME ='WSREP_ON') as `SESSION WSREP_ON`)
  select * from IS_REPLICATING;

  select concat('Dropping schema mariadb_review.') as NOTE 
  from information_schema.SCHEMATA where SCHEMA_NAME='mariadb_review';
  drop schema if exists mariadb_review;

/* Put session variables for replication ON -- default behavior in most cases. */
 IF @AUTHORIZED_TO_SQL_LOG_BIN='TRUE' THEN
    SET SESSION SQL_LOG_BIN=ON;
 END IF;

  if @AUTHORIZED_TO_WSREP_ON='TRUE' AND @IS_GALERA ='YES' then
    SET SESSION WSREP_ON=ON;
  end if;

end if;
else
  select concat('The mariadb_review schema does not exist. Nothing done.') as `NOTE`;
end if; /* @MARIADB_REVIEW_SCHEMA_EXISTS = 'YES' */
end;
//
delimiter ;
