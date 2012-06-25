#!/usr/bin/perl
# vim: sw=4 ts=2 nowrap
#
# NewsMan NNTP news tool
#
# REQUIRES: News::NNTPClient and DBD::SQLite
# (sudo apt-get install libnews-nntpclient-perl libdbd-sqlite3-perl)
# (recommended sudo apt-get install sqlite3)
#
# Copyright (c) 2012, mail@waterbrook.net
# All rights reserved.
#
# @section LICENSE
#  This program is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.
# 

use DBI;
use News::NNTPClient;

use warnings;
use strict;

# Globals
my $g_dbfile = $ENV{'HOME'} . '/.newsmandb';
my $g_db_h;
my @g_news_h = ();
my %g_opt = ();
my $baseprg = $0;
$baseprg =~ s{.*[/\\]}{};
#my @g_xover_fields = qw(numb subj frm date mesg refr char line xref);

######### FUNCTIONS

sub usage {

	print "\n";
	print "usage: $baseprg [-h] [-a] [-x] [-g <group> [-n <num>] [-p] -d <dir>] [-r <regex>] [-b <num>]\n";
	print "\n";
	print "-h		: this (help) message\n";
	print "\n";
	print "Group options:\n";
	print "-a		: get list of groups\n";
	print "\n";
	print "Article/header options:\n";
	print "-b <num>		: retrieve in size <num> batches (for -g and -a), default: 100000\n";
	print "-d <dir>		: save the articles to <dir> (for -g)\n";
	print "-n <num>		: retrieve only last <num> of articles (for -g)\n";
	print "-p		: purge db cache headers (for -g)\n";
	print "-g <group>	: specify newsgroup (eg alt.binaries.linux)\n";
	print "-x		: dont try to get new headers (for -g)\n";
	print "-y		: try to decode yEnc articles (for -g)\n";
	print "\n";
	print "General options:\n";
	print "-r <regex>	: get articles (-d), headers or group list (-a) matching <regex>\n";
	print "\n";
	print "Configuration options:\n";
	print "-l		: list servers in configuration\n";
	print "-s <serverhost>	: add server <serverhoststring> to configuration\n";
	print "-t <serverhost>	: takeaway (delete) server <serverhoststring> from configuration\n";
	print "\n";
	print "Example: (find news groups that have 'linux' in the name)\n";
	print "	$baseprg -a -r 'linux'\n";
	print "Example: (purge all topic headers for the alt.binaries.linux group so they can be recached from the beginning)\n";
	print "	$baseprg -p -g alt.binaries.linux\n";
	print "Example: (cache the last 50 topic headers for the alt.binaries.linux group)\n";
	print "	$baseprg -n 50 -g alt.binaries.linux\n";
	print "Example: (cache and search the cached topics in alt.binaries.linux group for the word 'pen' in the subject)\n";
	print "	$baseprg -g alt.binaries.linux -r 'pen'\n";
	print "\n";
	print "Quick start:\n";
	print "* add a server configuration,\n";
	print "* purge and cache the last 200,000 headers for the alt.binaries.movies.divx group (in default batches of 100000),\n";
	print "* and then download and decode the nzb files for the movies matching 'Plan.9.From.Outer.Space' from the alt.binaries.movies.divx group into the ~/Downloads directory)\n";
	print "	$baseprg -s MyUserName:PaSSW0rd\@free.newserver.com:119\n";
	print "	$baseprg -p -n 200000 -g alt.binaries.movies.divx\n";
	print "	$baseprg -g alt.binaries.movies.divx -d ~/Downloads -y -r 'Plan.9.From.Outer.Space.*nzb'\n";
	print "\n";
 
	exit 2;
}

sub init_opt {
 
	my $opt_string = 'hab:d:g:ln:pr:s:t:xy';
 
	use Getopt::Std;
	getopts( "$opt_string", \%g_opt ) or usage();
 
	usage() if(defined($g_opt{h}));
 
	#print "-s = $g_opt{s} (Running in mode)\n" if(defined($g_opt{s}));
	print "-a = $g_opt{a} (Specified get list)\n" if(defined($g_opt{a}));
	print "-b = $g_opt{b} (Specified chuck size)\n" if(defined($g_opt{b}));
	print "-d = $g_opt{d} (Specified dir)\n" if(defined($g_opt{d}));
	print "-g = $g_opt{g} (Specified group)\n" if(defined($g_opt{g}));
	print "-l = $g_opt{l} (Specified list)\n" if(defined($g_opt{l}));
	print "-n = $g_opt{n} (Specified last num)\n" if(defined($g_opt{n}));
	print "-p = $g_opt{p} (Specified purge)\n" if(defined($g_opt{p}));
	print "-r = $g_opt{r} (Specified regex for matching)\n" if(defined($g_opt{r}));
	print "-s = $g_opt{s} (Specified add serv)\n" if(defined($g_opt{s}));
	print "-t = $g_opt{t} (Specified rm serv)\n" if(defined($g_opt{t}));
	print "-x = $g_opt{x} (Specified no new headers)\n" if(defined($g_opt{x}));
	print "-y = $g_opt{y} (Specified yEnc)\n" if(defined($g_opt{y}));
}

sub lprint {
	my ($msg) = @_;
	#TODO log print
	print $msg . "\n";
}

sub connect_db_handle {

	# Open up the database handle
	$g_db_h = DBI->connect('dbi:SQLite:dbname=' . $g_dbfile, '', '', {'PrintError'=>1, AutoCommit =>1});
	if (!$g_db_h) {
		return 0;
	}

	my $found_headers = 0;
	my $host_q_handle = $g_db_h->prepare("SELECT * FROM sqlite_master WHERE type='table' and name='newsman_headers';"); #SQLITE specific command
	if ($host_q_handle) {
		$host_q_handle->execute();
		while (my $host_row = $host_q_handle->fetchrow_hashref()) {
			$found_headers++;
		}
	}
	# if we didnt find the headers table create it
	if ($found_headers <= 0) {
		lprint "Creating headers table...";
		$g_db_h->do("CREATE TABLE newsman_headers (hostname TEXT NOT NULL, newsgroup TEXT NOT NULL, numb INT, subj TEXT NOT NULL, frm TEXT NOT NULL, date TEXT NOT NULL, mesg TEXT NOT NULL, refr TEXT NOT NULL, char TEXT NOT NULL, line TEXT NOT NULL, xref TEXT NOT NULL);");
	}

	my $found_config = 0;
	my $config_q_handle = $g_db_h->prepare("SELECT * FROM sqlite_master WHERE type='table' and name='newsman_hosts';"); #SQLITE specific command
	if ($config_q_handle) {
		$config_q_handle->execute();
		while (my $config_row = $config_q_handle->fetchrow_hashref()) {
			$found_config++;
		}
	}
	if ($found_config <= 0) {
		lprint "Creating config table...";
		$g_db_h->do("CREATE TABLE newsman_hosts (hostname TEXT NOT NULL, port INT, username TEXT NOT NULL, password TEXT NOT NULL);");
	}
	return 1;
}

sub close_news_handles {

	while (scalar(@g_news_h)) {
		my $n_h = pop(@g_news_h);
		$n_h->quit();
	}

}

sub list_config {

	my $host_q_handle = $g_db_h->prepare("SELECT * FROM newsman_hosts;");
	if ($host_q_handle) {
		$host_q_handle->execute();
		while (my $host_row = $host_q_handle->fetchrow_hashref()) {
			lprint(" " . $host_row->{'username'} . ":" . $host_row->{'password'} . "@" . $host_row->{'hostname'} . ":" . $host_row->{'port'});
		}
	}
}

sub connect_news_handles {

	my $added_hosts = 0;

	# get a list of hosts
	my $host_q_handle = $g_db_h->prepare("SELECT * FROM newsman_hosts;");
	if ($host_q_handle) {
		$host_q_handle->execute();

		# For each host create an NNTP handle
		while (my $host_row = $host_q_handle->fetchrow_hashref()) {

			# Create a news handle
			my $n_h = new News::NNTPClient($host_row->{'hostname'}, $host_row->{'port'});
			if (!$n_h) {
				lprint "Error";
				next;
			}

			# Auth if needed
			if ($host_row->{'username'} ne '' && $host_row->{'password'} ne '') {
				$n_h->authinfo($host_row->{'username'}, $host_row->{'password'});
			}

			push(@g_news_h, $n_h);
			$added_hosts++;
		}
	}
	return $added_hosts;
}

sub list_groups {

	foreach my $n_h (@g_news_h) {
		my @groups;
		if (defined($g_opt{r})) {
			lprint "Getting list for '$g_opt{r}'...";
			@groups = $n_h->list('active', $g_opt{r});
		} else {
			# just do them all
			lprint "Getting whole list...";
			@groups = $n_h->list('active');
		}
		print @groups;
	}
}

sub refresh_headers {

	foreach my $n_h (@g_news_h) {

		if (defined($g_opt{p})) {
			lprint "purging db cache for newsgroup $g_opt{g}";
			$g_db_h->do("DELETE FROM newsman_headers WHERE newsgroup = '$g_opt{g}';");
		}

		my ($groupfirst, $grouplast) = $n_h->group($g_opt{g});
		lprint "$g_opt{g} has headers $groupfirst to $grouplast (" . ($grouplast - $groupfirst) . ")";
		#TODO retire old

		# initial assume get all headers
		my $dofirst = $groupfirst;
		my $dolast = $grouplast;

		# see what we already have
		my $dbmax = $g_db_h->selectrow_hashref("SELECT MAX(numb) as max FROM newsman_headers WHERE newsgroup = '$g_opt{g}';");
		if (defined($dbmax->{'max'})) {
			if ($dofirst < $dbmax->{'max'}) {
				$dofirst = $dbmax->{'max'} + 1;
				lprint "DB cached to $dbmax->{'max'}.";
			}
		}

		# only get last num
		if (defined($g_opt{n})) {
			my $newfirst = $grouplast - $g_opt{n} + 1;
			if ($newfirst > $dofirst) {
				$dofirst = $newfirst;
			}
			lprint "Only caching last $g_opt{n} headers from $dofirst";
		}

		if ($dofirst <= $dolast) {

			my $num_to_do = $dolast - $dofirst + 1;

			# do in batches (default)
			my $set_size = 100000;
			if (defined($g_opt{b})) {
				my $set_size = $g_opt{b};
			}

			lprint "Will be getting $num_to_do headers in batch sizes of $set_size.";

			my $max_set = int($num_to_do / $set_size);
			if ($max_set != $num_to_do / $set_size) {
				$max_set++; #add one to always round up
			}
			for (my $set = 0; $set < $max_set; $set++) {

				my $setfirst = $dofirst + ($set_size * $set);
				if ($setfirst < $dofirst || $setfirst > $dolast) {
					lprint "Error: trying to do more than we should so we should stop and finish.";
					last;
				}
				my $setlast = $dofirst + ($set_size * ($set + 1)) - 1;
				if ($setlast > $dolast) {
					$setlast = $dolast;
				}
			
				my $perc = int((($set) / $max_set) * 100);
				lprint "Caching headers $setfirst to $setlast... $perc% (" . ($set + 1) . "/" . $max_set . ")";
				my @xoverrsp = $n_h->xover($setfirst, $setlast);
				if (!@xoverrsp) {
					lprint "No response, Timed out? Try lower batch size";
					return;
				}
				$g_db_h->begin_work;
				#TODO hostname doesnt match with this method
				my $ins_q_handle = $g_db_h->prepare("INSERT INTO newsman_headers (hostname, newsgroup, numb, subj, frm, date, mesg, refr, char, line, xref) VALUES ('" . $n_h->host() . "', '$g_opt{g}', ?, ?, ?, ?, ?, ?, ?, ?, ?);");
				if ($ins_q_handle) {
					foreach my $xover (@xoverrsp) {
						my @fields = split /\t/, $xover;
						#TODO hostname etc
						$ins_q_handle->execute(@fields);
					}
				}
				$g_db_h->commit; #commit the inserts no undo now
			}
		} else {
			lprint "No new headers to cache ($dofirst > $dolast)";
		}
	}
}

sub ydecode {

	my ($newf) = @_;

	#open up the file for reading
	my $fh;
	if (!open($fh, '<', $newf)) {
		lprint("Error: Could not open article file $newf to read");
		return 0;
	}

	# get the "=ybegin" keyword
	my $begin;
	while ($begin = <$fh>) {
		if($begin =~ /^=ybegin/) {
			last;
		}
	}

	# if we are at the end we didnt find the keyword
	if (!$begin) {
		#lprint("Not a yEnc, no =ybegin found");
		close($fh);
		return 0;
	}

	# get the fields (part=11 total=66 line=128 size=50000000 name=image.gif)
	my %beginfields = ();

	# first get the name since it has spaces
	my @namesplit = split(' name=', $begin);
	my $nameval = $namesplit[1];
	$nameval =~ s/^\s+|\s+$//g; #remove any surrounding whitespace
	$beginfields{'name'} = $nameval;

	# now tokenize the rest with spaces
	my @bfields = split(' ', $namesplit[0]);
	foreach my $bfield (@bfields) {
		my ($key, $val) = split('=', $bfield);
		#remove any surrounding whitespace
		$val =~ s/^\s+|\s+$//g;
		#the first one is the =ybegin
		if ($val ne 'ybegin') {
			$beginfields{$key} = $val;
		}
	}

	# get the "=ypart" keyword directly after =ybegin
	my $part = <$fh>;

	# if we didnt find ypart fail
	if (!$part || $part !~ /^=ypart/) {
		lprint("Error: Not a good yEnc, no =ypart found");
		close($fh);
		return 0;
	}

	# get the fields (begin=7680001 end=8448000)
	my %partfields = ();
	my @pfields = split(' ', $part);
	foreach my $pfield (@pfields) {
		my ($key, $val) = split(/=/, $pfield);
		#remove any surrounding whitespace
		$val =~ s/^\s+|\s+$//g;
		#the first one is the =ypart
		if ($val ne 'ypart') {
			$partfields{$key} = $val;
		}
	}

	# open up the file for writing
	my $yfh;
	my $newy = $g_opt{d}. '/' . $beginfields{'name'};
	if (!open($yfh, '>>', $newy)) {
		lprint("Error: Could not open yenc file $beginfields{'name'} to write");
		return 0;
	}

	# set mode and seek to correct spot
	lprint "yEnc: $beginfields{'name'}...";
	binmode $yfh;
	my $offset = $partfields{'begin'} - 1; # subtract one from start for offset
	my $partsize = $partfields{'end'} - $offset;
	if (!seek($yfh, $offset, 0)) {
		lprint "Error: cant seek to yEnc file $offset";
	}
		
	# parse lines until the "=yend" keyword
	my $line;
	while ($line = <$fh>) {
		if($line =~ /^=yend/) {
			last;
		}
		chomp($line);
		# DECODER
		$line =~ s/=(.)/chr(ord($1)+256-64 & 255)/egosx;
		$line =~ tr[\000-\377][\326-\377\000-\325];

		print $yfh $line;
	}

	# close off the out file
	close($yfh);

	# if we didnt find yend fail
	if (!$line || $line !~ /^=yend/) {
		lprint("Error: My not be a good yEnc, no =yend found");
		close($fh);
		return 0;
	}

	# get the fields (size=768000 part=11 pcrc32=52b00c88)
	my %endfields = ();
	my @efields = split(' ', $line);
	foreach my $efield (@efields) {
		my ($key, $val) = split(/=/, $efield);
		#remove any surrounding whitespace
		$val =~ s/^\s+|\s+$//g;
		#the first one is the =yend
		if ($val ne 'yend') {
			$endfields{$key} = $val;
		}
	}

	#close off the in file
	close($fh);

	# check final sizes
	my $decode_size = defined($partsize) ? $partsize : $beginfields{'size'};
	if ($endfields{'size'} != $decode_size) {
		lprint("Error: Size didn't match $endfields{'size'} != $decode_size");
	}
}

sub get_articles {

	foreach my $n_h (@g_news_h) {

		# set the group context for the next article calls
		my ($groupfirst, $grouplast) = $n_h->group($g_opt{g});

		# TODO max batch
		my $art_q_handle = $g_db_h->prepare("SELECT numb,subj FROM newsman_headers WHERE newsgroup = '$g_opt{g}';"); #SQLITE specific command
		if ($art_q_handle) {
			$art_q_handle->execute();

			# For each article
			while (my $art_row = $art_q_handle->fetchrow_hashref()) {
				if (defined($g_opt{r})) {
					if ($art_row->{'subj'} !~ m/$g_opt{r}/) {
						next;
					}
					lprint "$art_row->{'numb'}: $art_row->{'subj'}";
				}
				if (defined($g_opt{d})) {
					my $newf = $g_opt{d}. '/' . $art_row->{'numb'} . '.txt';
					#if it doesnt already exist or not empty or not purging
					if(! -e $newf || -s $newf <= 0 || defined($g_opt{p})) {
						if(open(my $fh, '>', $newf)) {
							lprint "Saving article $newf ($art_row->{'subj'})...";
							print $fh $n_h->article($art_row->{'numb'});
							close($fh);
						}
					}
					if (defined($g_opt{y})) {
						ydecode($newf);
					}
				} else {
					#print $n_h->article($art_row->{'numb'});
				}
			}
		}
	}
}

######### MAIN

init_opt();

my $success = connect_db_handle();
if (!$success) {
	lprint "Error: database could not be opened (check permissions): $g_dbfile";
	exit 1;
}

if (defined($g_opt{l})) {
	list_config();
}

if (defined($g_opt{s})) {
	#TODO if username or password has @ or :
	my ($up, $hp) = split('@', $g_opt{s});
	my ($user, $pass) = split(':', $up);
	my ($host, $port) = split(':', $hp);
	$g_db_h->do("INSERT INTO newsman_hosts (hostname, port, username, password) VALUES ('$host', $port, '$user', '$pass');");
}

if (defined($g_opt{t})) {
	#TODO if username or password has @ or :
	my ($up, $hp) = split('@', $g_opt{t});
	my ($user, $pass) = split(':', $up);
	my ($host, $port) = split(':', $hp);
	$g_db_h->do("DELETE FROM newsman_hosts WHERE hostname = '$host' AND port = $port AND username = '$user' AND password = '$pass';");
}

my $num_handles = connect_news_handles();
# make sure we are configured for one or more hosts
if ($num_handles <= 0) {
	lprint "Error: No hosts are configured in the database, use $baseprg -s <hoststring>";
	exit 1;
}

# if we passed in a list command, show the ones that apply
if (defined($g_opt{a})) {
	list_groups();
}

# if we passed in a group, grab the headers
if (defined($g_opt{g})) {
	if (!defined($g_opt{x})) {
		refresh_headers();
	}
	get_articles();
}

close_news_handles();

exit 0;
