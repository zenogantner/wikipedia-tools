use strict;
use warnings;
use encoding 'utf8'; # ä
binmode STDOUT, ':utf8';
binmode STDERR, ':utf8';

use Test::More qw( no_plan);

use lib "$ENV{HOME}/zeno/perl-modules/";
use MediaWiki::Utilities;
use Test::Multi;

my $category_data = {
    '[[:Category:Ice hockey]]' => '[[:Category:Ice hockey]]',
    '[[Category:Ice hockey]] [[Category:Beer]]'       => '',
    "[[Category:Ice hockey]]\n[[Category:Beer]]"      => '',
    'Sentence with category [[Category:Ice hockey]]?' => 'Sentence with category ?',
    '{{DEFAULTSORT:Gantner, Zeno}}'                   => '',
};
my $interwiki_data = {
    ''         => '',
    'abc'      => 'abc',
    'Category'                 => 'Category',
    '[[Category]]'             => '[[Category]]',
    '[[Category:Ice hockey]]'  => '[[Category:Ice hockey]]',
    '[[de:Artikel]]'           => '',
    '[[de:Artikel]][[en:Article]]'      => '',
    "[[de:Artikel]]\n[[en:Article]]"    => '',
    "[[de:Artikel]]\n[[en:Article|FA]]" => '',
};


test_one_arg($category_data,  \&remove_categories,      'remove_categories');
test_one_arg($interwiki_data, \&remove_interwiki_links, 'remove_interwiki_links');

