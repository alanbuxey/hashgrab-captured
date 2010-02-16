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
use Compress::Bzip2;
use DateTime;
use File::Path;
use Proc::Daemon;
use DBI;

$0 =~ s#.*/##;

my $listen_port = 10000;
my $store_directory = "";
my $store_dbi = "";
my $store_dbi_username = "";
my $store_dbi_password = "";
my $store_expiry = 90;
my $daemonize = "";
my $reciever_socket;
my $reciever_select;
my $fiveminute_base;
my $fiveminute_handle;

GetOptions (
	"listen-port=s" => \$listen_port,
	"store-directory=s" => \$store_directory,
	"store-dbi=s" => \$store_dbi,
	"store-dbi-username=s" => \$store_dbi_username,
	"store-dbi-password=s" => \$store_dbi_password,
	"store-expiry=i" => \$store_expiry,
	"daemonize" => \$daemonize
) or die "usage: $0 [ --listen-port port ] [ --store-directory directory ] [ --store-dbi dbi-string ] [ --store-dbi-username username ] [ --store-dbi-password password ] [ --store-expiry days ] [ --daemonize ]\n";

die "either a storage directory and/or store DBI string must be provided\n" unless $store_directory || $store_dbi;

if ($store_directory && !-d $store_directory) {
	die "storage directory specified does not exist\n";
}

# If we need to daemonize then now do so.
if ($daemonize) {
        Proc::Daemon::Init;
}

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

		# Split into array, for file based storage we just need the TS, for DB we need all seperatly.
		@split_data = split(/,/, $data);

		# If we're saving to disk then do appropriate things.
		if ($store_directory) {
			# Check to see five minute base status
			if (!$fiveminute_base || ($fiveminute_base + 300 <= $split_data[0])) {
				my ($directory, $filename);

				$fiveminute_base = ($split_data[0] - ($split_data[0] % 300));

				if ($fiveminute_handle) {
					$fiveminute_handle->bzclose();
				}

				$directory = strftime("/%Y/%m/%d/", localtime($fiveminute_base));
				$filename = strftime("%H%M.bz", localtime($fiveminute_base));

				mkpath($store_directory . $directory);

				$fiveminute_handle = bzopen($store_directory . $directory . $filename, "w");
			}

			$fiveminute_handle->bzwrite($data."\n");
		}
	}
}
