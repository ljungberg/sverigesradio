package Plugins::SverigesRadio::Plugin;

# $Id$
#  335  sudo service logitechmediaserver restart
#  336  sudo chown -R squeezeboxserver MyHelloWorld/
#sudo squeezeboxserver --debug plugin.myhelloworld=INFO,persist

use strict;
use base qw(Slim::Plugin::OPMLBased);
use File::Spec::Functions qw(catdir);
use Slim::Utils::Log;
use Slim::Networking::SimpleAsyncHTTP;
use XML::Simple;

use Data::Dumper;

my $log = Slim::Utils::Log->addLogCategory( {
	category     => 'plugin.sverigesradio',
	defaultLevel => 'INFO',
#	defaultLevel => 'ERROR',
	description  => 'PLUGIN_SVERIGES_RADIO',
} );

sub initPlugin {
	my $class = shift;

	my $file = catdir( $class->_pluginDataFor('basedir'), 'menu.opml' );

#	Slim::Player::ProtocolHandlers->registerHandler(
#		sverigesrad io => 'Plugins::SverigesRadio::ProtocolHandler'
#	); 

	$class->SUPER::initPlugin(
	    feed   => \&handleFeed, #Slim::Utils::Misc::fileURLFromPath($file), #\&handleFeed, #
	    tag    => 'sverigesradio',
	    #		node   => 'myMusic', what does the node argument do?
	    #		node   => 'home',
	    #		is_app => 1, #this makes the app apear in 'extras'...
	    menu   => 'radios', # menu=radios and is_app not set makes the app appear in home->radios...
 # can only be radios for opml based? (line 40 refer to radio.png)
   	    weight => 1,
	);
}

# Don't add this item to any menu
sub playerMenu { }
sub getDisplayName { 'PLUGIN_SVERIGES_RADIO_NAME' }
sub handleFeed {
    my ($client, $cb, $args) = @_;

#    my $items = [{name => cstring($client, 'PLUGIN_MYHELLOWORLD'),
#		  type => 'textarea'}];
#    my $items = [{name => "file",
#		  play => 'http://sverigesradio.se/topsy/ljudfil/4381232.mp3',
#	          on_select => 'play'}];
    #NEXT -> fetch xml programs and check BBCIPlayer how to parse into a menue...

    my $url = 'http://api.sr.se/api/v2/programs/index';
    #DOES NOT WORK! (ie no printout) maybe must be called from a ProtocolHandler.pm?
    #both iPlayer and Qubuz does it like that...!!
    # NEXT -> try fix a protocol handler
    # does we realy need protocol handler for this? not according to API.pm Qobuz...
    # try to use same callback handling (the below has none...)
    # Fungerade efter att jag fattat att denna metod inte kördes...
    # Jag tror att man borde göra som BBCXMLParser.pm! blir nog jättebra
    # Men varför behöver man då en protocol handler??????
    my $http = Slim::Networking::SimpleAsyncHTTP->new(
		sub {
		    my $response = shift;

		    my @menu = parseXMLprograms($response);
		    $log->info(Data::Dump::dump(@menu));

#		    my $items = [{name => "filflflfle",
#				  play => 'http://sverigesradio.se/topsy/ljudfil/4381232.mp3',
#				  on_select => 'play'}];
		    $cb->({
			items => \@menu,
			  });
	},
		sub {
		    my ($http, $error) = @_;
		    $log->warn("Error: $error");
		},
		{
		    timeout => 15,
		},
	);
    $http->get($url);
}

#####################################XMLPARSWER#####################
sub parseXMLprograms{
    my $response   = shift;
#    $log->info("Response IN subfunction $httpResponse");
#    $log->info(Data::Dump::dump($response));
#    $log->info(Data::Dump::dump($response->content));
#    $log->info(Data::Dump::dump($response->contentRef));

    my $xml = eval {
	XMLin( 
	    $response->contentRef,
#	    KeyAttr    =>  { program => 'id' }, #attribute translated to hash key
#	    GroupTags  => { programs => 'program' }, # remove level 'program' from hash structure
	    ForceArray => [ 'program' ] # GroupTags performed first so 'programs' instead of 'program'
#ValueAttr => [ names ] # bra?
# ContentKey => 'keyname' # in+out - seldom used bra??
	    )
    };
#    $log->info(Data::Dump::dump($xml));

    my @menu;

    for my $title (keys %{$xml->{'programs'}->{'program'}}) {
	$log->info(Data::Dump::dump($title));
	my $id = $xml->{'programs'}->{'program'}->{$title}->{'id'};
	my $url = 'http://api.sr.se/api/v2/broadcasts?programid=' . $id;
	$log->info(Data::Dump::dump($id));
	push @menu, {'name' => $title,
		     'url'   => $url
	};
    }
    return @menu;

    # programs -> name (index)
    #          -> program id
}
sub parseProgramId {
    my $id = shift;
#    'http://api.sr.se/api/v2/broadcasts?programid=3718$id};
}
    
################################################################

1;
