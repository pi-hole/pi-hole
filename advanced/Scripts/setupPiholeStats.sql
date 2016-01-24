
-- instal with this command: mysql -u root -p"raspberry" < /usr/local/bin/setupPiholeStats.sql
CREATE DATABASE charts;
USE charts;
DROP TABLE IF EXISTS `pie_chart_stats`;
CREATE TABLE `pie_chart_stats` (
	`insert_date` DATE NOT NULL COMMENT 'date when values were captured',
	`query_cnt` INT(10) UNSIGNED NOT NULL COMMENT 'query count appreaprence',
	`adver_cnt` INT(10) UNSIGNED NOT NULL COMMENT 'advertiser count apperance',
	PRIMARY KEY (`insert_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COMMENT 'table to store stats for pie (queries vs advertisers) chart';
-- this row would be updated to store SUM values
-- needs to be added within a table creation
INSERT INTO `pie_chart_stats` VALUES ('0000-00-00', 0, 0);

DROP TABLE IF EXISTS `top_chart_stats`;
CREATE TABLE `top_chart_stats` (
	`insert_date` DATE NOT NULL COMMENT 'date when values were captured',
	`adver_name` VARCHAR (60) NOT NULL COMMENT 'advertiser domain name',
	`cnt` MEDIUMINT(7) NOT NULL COMMENT 'advertiser count apperance',
	PRIMARY KEY (`insert_date`, `adver_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
