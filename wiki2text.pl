#!/usr/bin/perl

# Copyright (c) 2008, 2009 by Zeno Gantner <zeno.gantner@gmail.com>
# Licensed under the terms of GNU GPL 3 or later

use strict;
use warnings;
use utf8; # ä
binmode STDOUT, ':utf8';
binmode STDERR, ':utf8';

use Getopt::Long;
use Carp;
use English; $OUTPUT_AUTOFLUSH = 1;

use Text::MediawikiFormat;

use Text::Util;

my $debug       = 0;
my $verbose     = 0;
my $help        = 0;

GetOptions(
	'help'         => \$help,
	'debug+'       => \$debug,
	'verbose+'     => \$verbose,
	  ) or usage(-1);

if ($help) {
    usage(0);
}

my %tags = (
	    #indent	    => qr/^(?:[:*#;]*)(?=[:*#;])/,        # TODO
	    link	    => \&Text::MediawikiFormat::_make_text_link,
	    strong	    => sub { $_[0] },
	    emphasized	    => sub { $_[0] },

	    code	    => ['', '', '', "\n"],
	    line	    => ['', '', '----' x 10, "\n"],
	    paragraph	    => ['', "\n", '', "\n", 1],
	    paragraph_break => ['', '', '', "\n"],
	    unordered	    => ['//', '\\', '* ', "!\n"],  ## TODO
	    ordered         => ['', '', '# ', "\n"],
	    definition	    => ['', '', '* ', "\n"],
	    header          => ['', "\n", sub { $_[3] }],
	   );

while (<>) {
    my $wiki_line = $_;

    print Text::MediawikiFormat::format(
        $wiki_line,
        \%tags,
        {   # options:
            implicit_links => 0,
            generate_links => 0,
            #exists $self->{get_template} ? (get_template => $self->{get_template}) : (),
            #exists $self->{template_ref} ? (template_ref => $self->{template_ref}) : (),
       }
    );
}

# TODO: move the cleaning procedures into a module
# also in WDG::Extractor::Util --> combine that!
sub remove_categories {
    my ($text) = @_;

	my $no_brackets         = qr/[^\[\]]/;
	my $no_brackets_no_pipe = qr/[^\[\]|]/;

    $text =~ s/\[\[
                (?:Kategorie|Category):          # TODO: other languages
                ($no_brackets_no_pipe+)
                (?:\|($no_brackets_no_pipe*))?
                \]\]
              //xmsg;

    return trim($text);
}

sub remove_interwiki_links {
    my ($text) = @_;

	my $no_brackets         = qr/[^\[\]]/;
	my $no_brackets_no_pipe = qr/[^\[\]|]/;

    $text =~ s/\[\[
                (?:\w{2,3}|simple|bat-smg|nds-nl):
                ($no_brackets_no_pipe+)
                \]\]
              //xmsg;

    $text =~ s/
              \{\{
              Link
              \s
              FA
              \|
              (?:\w{2,3}|simple)
               \}\}
             //xmsg;

    return trim($text);
}

sub usage {
    my ($return_code) = @_;

    print << "END";
Convert MediaWiki syntax to plain text.

usage: $PROGRAM_NAME [OPTIONS] article|category|page_id

    --help                              display this usage information
    --verbose                           increment verbosity level by one
    --debug                             increment debug level by one
END

    exit $return_code;
}

