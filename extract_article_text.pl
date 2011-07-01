#!/usr/bin/perl

# Copyright (c) 2007, 2008, 2009 by Zeno Gantner <zeno.gantner@gmail.com>
# Licensed under the terms of GNU GPL 3 or later

use strict;
use warnings;
use utf8; # ä

use Carp;
use English; $OUTPUT_AUTOFLUSH = 1;
use Getopt::Long;

use Parse::MediaWikiDump;

my $file = '';
my $title = '';
my $index = 0;
GetOptions(
	'index=i' => \$index,
	'title=s' => \$title,
	  );

my $file = shift(@ARGV) or croak "You must specify a MediaWiki dump of the current pages";
#my $title = shift(@ARGV) or croak "must specify an article title";
if ($title eq '' && $index == 0) {
	croak "You must specify a title (--title=\"SOME TITLE\") or an index (--index=IDX)";
}

my $dump = Parse::MediaWikiDump::Pages->new($file);

binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');

#this is the only currently known value but there could be more in the future
if ($dump->case ne 'first-letter') {
	croak "unable to handle any case setting besides 'first-letter'";
}

$title = case_fixer($title);

my $count = 0;
while (my $page = $dump->next) {
	$count++;
	if ($count % 2000 == 0) {
		print STDERR '.';
	}
	if ($count % 140000 == 0) {
		print STDERR "\n";
	}
	if ($page->title eq $title) {
		print STDERR "\nLocated text for '$title' at position $count:\n";
	        my $text = $page->text;
		print $$text;
		exit 0;
	}
}

print STDERR "Unable to find article text for $title\n";
exit 1;

# removes any case sensativity from the very first letter of the title
# but not from the optional namespace name

sub case_fixer {
	my $title = shift;

	# check for namespace
	if ($title =~ /^(.+?):(.+)/) {
		$title = $1 . ':' . ucfirst($2);
	} else {
		$title = ucfirst($title);
	}
	return $title;
}

