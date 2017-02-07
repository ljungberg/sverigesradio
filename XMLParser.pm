package Plugins::SverigesRadio::XMLParser;

use strict;

use Slim::Utils::Log;
use XML::Simple;
use URI::Escape qw(uri_escape_utf8 uri_unescape);

use Data::Dumper;


my $log = logger('plugin.sverigesradio');

sub parse {
    my $class  = shift;
    my $http   = shift;
    my $optstr = shift;

    # OBS anroparen OPML jippo cachar menyerna ifall svaret från sveriges radio är samma. Det tycks överleva omstart av squeezbox servern...
    $log->info("Options are: $optstr");
    $log->info("Http är: $http->contentRef");
    my $xml = eval {
	XMLin( 
	    $http->contentRef,
	    KeyAttr    =>  { program => 'id' },#'id', #attribute translated to hash key
#	    GroupTags  => { programs => 'program' }, # remove level 'program' from hash structure
	    ForceArray => [ 'program' ]
#ValueAttr => [ names ] # bra?
# ContentKey => 'keyname' # in+out - seldom used bra??
	    )
    };

    print Dumper($xml);
    
    # return xmlbrowser hash
    return {
	'name'    => "kalle",#$params->{'feedTitle'},
#	'items'   => \@menu, enough not to set items?
	'type'    => 'opml',
#	'nocache' => $opts->{'nocache'},
    };
}

1;
