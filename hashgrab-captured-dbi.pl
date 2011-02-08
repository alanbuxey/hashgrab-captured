#!/usr/bin/perl
#
# hashgrabd-captured - Utility designed to capture the network output from 
# hashgrabd and store it either on disk or in a database.
# 
# Copyright (C) 2010 University of Lancaster
# 
# This program is free software: you can redistribute it and/or modify it 
# under the terms of the GNU General Public License as published by 
# the Free Software Foundation, either version 3 of the License, or 
# (at your option) any later version. This program is distributed in the 
# hope that it will be useful, but WITHOUT ANY WARRANTY; without 
# even the implied warranty of MERCHANTABILITY or FITNESS FOR 
# A PARTICULAR PURPOSE. See the GNU General Public License 
# for more details. You should have received a copy of the GNU General 
# Public License along with this program. If not, see <http://www.gnu.org/licenses/>.
#

use strict;
use warnings 'all';
use Getopt::Long;
use POSIX;
use IO::Socket;
use IO::Select;
use Socket;
use Fcntl;
use DateTime;
use File::Path;
use Proc::Daemon;
use DBI;

$0 =~ s#.*/##;

my $listen_port = 10000;
my $store_dbi = "";
my $store_dbi_username = "";
my $store_dbi_password = "";
my $store_expiry = 90;
my $daemonize = "";
my $reciever_socket;
my $reciever_select;
my $data_stdin;

GetOptions (
	"listen-port=s" => \$listen_port,
	"store-dbi=s" => \$store_dbi,
	"store-dbi-username=s" => \$store_dbi_username,
	"store-dbi-password=s" => \$store_dbi_password,
	"store-expiry=i" => \$store_expiry,
	"daemonize" => \$daemonize,
	"stdin" => \$data_stdin
) or die "usage: $0 [ --listen-port port ] [ --store-dbi dbi-string ] [ --store-dbi-username username ] [ --store-dbi-password password ] [ --store-expiry days ] [ --daemonize ] [ --stdin ]\n";

die "a store DBI string must be provided\n" unless $store_dbi;

# Connect to database
my $dbh = DBI->connect($store_dbi, $store_dbi_username, $store_dbi_password);
die "unable to connect to database" unless $dbh;

# If we need to daemonize then now do so.
if ($daemonize) {
        Proc::Daemon::Init;
}

sub find_or_create_ip {
	my ($ip) = @_;
	
	my $sth = $dbh->prepare("SELECT id FROM ips WHERE ip = INET_ATON(?)");
	$sth->execute($ip);

	my @row = $sth->fetchrow_array();
	$sth->finish;

	if ($sth->rows == 1) {
		return $row[0];
	} else {
		my $isth = $dbh->prepare("INSERT INTO ips (ip) VALUES (INET_ATON(?))");
		$isth->execute($ip);
		$isth->finish;
		return find_or_create_ip($ip);
	}
}

sub find_or_create_hash {
	my ($hash, $proto) = @_;
	
	my $sth = $dbh->prepare("SELECT id FROM hashes WHERE hash = LOWER(?) AND protocol = ?");
	$sth->execute($hash, $proto);

	my @row = $sth->fetchrow_array();
	$sth->finish;

	if ($sth->rows == 1) {
		return $row[0];
	} else {
		my $isth = $dbh->prepare("INSERT INTO hashes (hash, protocol) VALUES (LOWER(?), ?)");
		$isth->execute($hash, $proto);
		$isth->finish;
		return find_or_create_hash($hash, $proto);
	}
}

sub create_or_update_association {
	my ($ip_id, $hash_id, $moment) = @_;

	my $sth = $dbh->prepare("SELECT id, stop FROM associations WHERE ip_id = ? AND hash_id = ? AND start <= ? AND (stop + 900) >= ?");
	$sth->execute($ip_id, $hash_id, $moment, $moment);

        my @row = $sth->fetchrow_array();
        $sth->finish;

        if ($sth->rows >= 1) {
		#Update if need be.
		if ($moment > $row[1]) {
			my $usth = $dbh->prepare("UPDATE associations SET stop = ? WHERE id = ?");
			$usth->execute($moment, $row[0]);
			$usth->finish;
		}

                return $row[0];
        } else {
                my $isth = $dbh->prepare("INSERT INTO associations (ip_id, hash_id, start, stop) VALUES (?, ?, ?, ?)");
                $isth->execute($ip_id, $hash_id, $moment, $moment);
                $isth->finish;
                return create_or_update_association($ip_id, $hash_id, $moment);
        }
}

sub create_instance {
	my ($src_ass_id, $src_port, $dst_ass_id, $dst_port, $offer, $moment) = @_;
	$offer = ($offer eq "o" ? 1 : 0);

	my $isth = $dbh->prepare("INSERT INTO instances (src_association_id, src_port, dst_association_id, dst_port, offer, moment) VALUES (?, ?, ?, ?, ?, ?)");
	$isth->execute($src_ass_id, $src_port, $dst_ass_id, $dst_port, $offer, $moment);
	$isth->finish;
}

sub handle_data {
	# Get data
	my ($data) = @_;

	# Split into array, for file based storage we just need the TS, for DB we need all seperatly.
	my @split_data = split(/,/, $data);

	if (@split_data != 10) {
		printf "Invalid Data Recieved!\n";
		next;
	}
                
        # Resolve IP ids
        my $src_ip_id = find_or_create_ip($split_data[1]);
        my $dst_ip_id = find_or_create_ip($split_data[3]);

	my $hash_id = find_or_create_hash($split_data[8], $split_data[6]);

	my $src_ass_id = create_or_update_association($src_ip_id, $hash_id, $split_data[0]);
	my $dst_ass_id = create_or_update_association($dst_ip_id, $hash_id, $split_data[0]);
		
	create_instance($src_ass_id, $split_data[2], $dst_ass_id, $split_data[4], $split_data[7], $split_data[0]);
}

if ($data_stdin) {
	my $data;
	
	while(defined($data = <STDIN>)) {
		chomp($data);
		handle_data($data);
	}
} else {
	# Open UDP port
	$reciever_socket = IO::Socket::INET->new(LocalPort => $listen_port, Proto => "udp") or die "could not create UDP reciever: $@\n";

	# Create select object so we can poll with timeout easily.
	$reciever_select = IO::Select->new($reciever_socket);

	# Loop indefinatly
	while (1) {
		my $recieving_socket;

		foreach $recieving_socket ($reciever_select->can_read(1)) {
			my ($data, @split_data, $rv);

			# Recieve data from socket.
			$rv = $recieving_socket->recv($data, POSIX::BUFSIZ, 0);

			# Pass it for handling.
			handle_data($data);
		}
	}
}
