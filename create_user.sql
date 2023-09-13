/* Script by Edward Stoever for Mariadb Support */
/* Create a new user to run mariadb_review with only necessary privileges. */
/* Script to create user with minimum privileges to run mariadb_review.sql */
set @USERNAME='revu';
set @HOSTNAME='%';
set @PASSWORD='password';

/* DO NOT EDIT BELOW THIS LINE */

select concat('Creating user ','`',@USERNAME,'`','@','`',@HOSTNAME,'`') as `NOTE`;

set @SQL=concat('GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, ALTER, DROP, CREATE VIEW, PROCESS on *.* to ','`',@USERNAME,'`','@','`',@HOSTNAME,'`',
'IDENTIFIED BY ''',@PASSWORD,'''');

PREPARE STMT FROM @SQL;
EXECUTE STMT;
DEALLOCATE PREPARE STMT;
