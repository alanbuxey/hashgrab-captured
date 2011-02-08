DROP DATABASE IF EXISTS hashgrab;
CREATE DATABASE hashgrab;

GRANT ALL ON hashgrab.* TO hashgrab@localhost IDENTIFIED BY 'barghsah';

USE hashgrab;

CREATE TABLE hashes (
  id INT UNSIGNED AUTO_INCREMENT NOT NULL,
  hash VARCHAR(40) NOT NULL,
  protocol VARCHAR(1) NOT NULL,
  description VARCHAR(128) NULL DEFAULT NULL,
  PRIMARY KEY (id)
);

CREATE UNIQUE INDEX hashes_hash ON hashes (hash);

CREATE TABLE ips (
  id INT UNSIGNED AUTO_INCREMENT NOT NULL,
  ip INT(20) UNSIGNED NOT NULL,
  PRIMARY KEY (id)
);

CREATE UNIQUE INDEX ips_ip ON ips (ip);

CREATE TABLE associations (
  id INT UNSIGNED AUTO_INCREMENT NOT NULL,
  hash_id INT UNSIGNED NOT NULL,
  ip_id INT UNSIGNED NOT NULL,
  start INT UNSIGNED NOT NULL,
  stop INT UNSIGNED NOT NULL,
  PRIMARY KEY (id)
);

CREATE INDEX associations_hash_id ON associations (hash_id);
CREATE INDEX associations_ip_id ON associations (ip_id);
CREATE INDEX associations_start ON associations (start);
CREATE INDEX associations_stop ON associations (stop);

CREATE TABLE instances (
  id INT UNSIGNED AUTO_INCREMENT NOT NULL,
  src_association_id INT UNSIGNED NOT NULL,
  src_port SMALLINT UNSIGNED NOT NULL,
  dst_association_id INT UNSIGNED NOT NULL,
  dst_port SMALLINT UNSIGNED NOT NULL,
  offer TINYINT UNSIGNED NOT NULL DEFAULT 0,
  moment INT UNSIGNED NOT NULL,
  PRIMARY KEY (id)
);

CREATE INDEX instances_src_assocation_id ON instances (src_association_id);
CREATE INDEX instances_src_port ON instances (src_port);
CREATE INDEX instances_dst_assocation_id ON instances (dst_association_id);
CREATE INDEX instances_dst_port ON instances (dst_port);
CREATE INDEX instances_offer ON instances (offer);
CREATE INDEX instances_moment ON instances (moment);
