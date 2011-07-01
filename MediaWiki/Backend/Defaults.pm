#
# (c) 2008 by Zeno Gantner <zeno.gantner@gmail.com>
#

use strict;
use warnings;
use utf8;

package MediaWiki::Backend::Defaults;
use base 'Exporter';
our @EXPORT = qw($WP_DB_HOST $WP_DB_USER $WP_DB_PASSWORD);

use version; our $VERSION = qv('0.0.1');
use Readonly;
use Carp;

# database access
Readonly our $WP_DB_HOST     => '147.172.223.227';
Readonly our $WP_DB_USER     => 'wikiuser';
Readonly our $WP_DB_PASSWORD => 'wikiuser_pw';

1;
