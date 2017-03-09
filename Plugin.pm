package Plugins::SverigesRadio::Plugin;

# $Id$
#  335  sudo service logitechmediaserver restart
#  336  sudo chown -R squeezeboxserver SverigesRadio/
#sudo squeezeboxserver --debug plugin.sverigesradio=INFO,persist

use strict;
use base qw(Slim::Plugin::OPMLBased);

use File::Spec::Functions qw(catdir);
use Slim::Utils::Log;
use Slim::Networking::SimpleAsyncHTTP;
use XML::Simple;

use Slim::Player::ProtocolHandlers;
use Plugins::SverigesRadio::ProtocolHandler;

use Data::Dumper;

my $log = Slim::Utils::Log->addLogCategory( {
	category     => 'plugin.sverigesradio',
	defaultLevel => 'INFO',
#	defaultLevel => 'ERROR',
	description  => 'PLUGIN_SVERIGES_RADIO',
} );

sub initPlugin {
	my $class = shift;

#	my $file = catdir( $class->_pluginDataFor('basedir'), 'menu.opml' );#TODO LOG THE PROTOCOL HANDLER TO SEE IF IT SWITCHES ON sverigesradio
	Slim::Player::ProtocolHandlers->registerHandler(
		sverigesradio => 'Plugins::SverigesRadio::ProtocolHandler'
	);
#	Slim::Player::ProtocolHandlers->registerIconHandler(
#		qr|\.sr\.se/|, 
#		sub { $class->_pluginDataFor('icon') }
#	);
#	Slim::Player::ProtocolHandlers->registerHandler(
#		sverigesrad io => 'Plugins::SverigesRadio::ProtocolHandler'
#	); 

	$class->SUPER::initPlugin(
	    feed   => \&handleFeed, #Slim::Utils::Misc::fileURLFromPath($file), #\&handleFeed, #
	    tag    => 'sverigesradio',
	    #		node   => 'myMusic', what does the node argument do?
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
    my ($client, $cb, $params) = @_;
    $cb->({
	items => [{
	    name => "Alla Program",
	    url  => \&fetch_and_parse_xml,
	    passthrough =>
		[{
		    parse_fun => \&parsePrograms,
		    parse_fun_args => {},
		    # See http://sverigesradio.se/api/documentation/v2/metoder/program.html
		    # and http://sverigesradio.se/api/documentation/v2/generella_parametrar.html
		    # for more details on url generation
		    
		    # Ask for all programs that are active and ask for everyone at once
		    url        => 'http://api.sr.se/api/v2/programs/index?isarchived=false&pagination=false'
			#http://api.sr.se/api/v2/programs?pagination=false',
			#'http://api.sr.se/api/v2/programs/index',
		 }]
		  },{
	    name => "Kanaler",
	    url => \&fetch_and_parse_xml,
	    passthrough =>
		[{
		    parse_fun => \&parseChannels,
		    parse_fun_args => {},
		    url        => 'http://api.sr.se/api/v2/channels/index?pagination=false'
		 }]
		  }
	    ]});
}

sub parseChannels {
    my ($xml) = @_;
    my @menu;
    my %menuHash;
    my @realmChannels;
    
    for my $name (keys %{$xml->{'channels'}->{'channel'}}) {
	my $type = $xml->{'channels'}->{'channel'}->{$name}->{'channeltype'};
	my $url = $xml->{'channels'}->{'channel'}->{$name}->{'liveaudio'}->{'url'};
	#NEXT: put in hases then new menues
	my $channel = {name => $name,
		       type => 'audio',
		       play  => $url,
		       on_select => 'play'
	};
	if ($type eq "Rikskanal") {
	    push @realmChannels, $channel;
	}
	elsif (not exists $menuHash{$type}) {
	    @menuHash{$type} = [$channel];
	}
	else
	{
	    push @{%menuHash{$type}}, $channel;
	}
    }
    $log->info(Data::Dump::dump(%menuHash));
    for my $radioType (keys %menuHash) {
	push @menu, {name => $radioType,
		     items => $menuHash{$radioType}};
    }

    @menu = sort { $a->{name} cmp $b->{name} } @menu;
    @realmChannels = sort { $a->{name} cmp $b->{name} } @realmChannels;
    $log->info(Data::Dump::dump(@realmChannels));
 #   $log->info(Data::Dump::dump(@menu));
    push( @realmChannels, @menu);
    $log->info(Data::Dump::dump(@realmChannels));
#NEXT favorites ('save' in menu) for channelse
    return @realmChannels;
}

sub parsePrograms {
    my ($xml) = @_;
    my @menu;

    for my $title (keys %{$xml->{'programs'}->{'program'}}) {
	my $id = $xml->{'programs'}->{'program'}->{$title}->{'id'};
	my $imageUrl = $xml->{'programs'}->{'program'}->{$title}->{'programimage'};
#TEST
#	my $url = 'sverigesradio://api.sr.se/api/v2/podfiles?programid=' . $id;
	my $url = 'http://api.sr.se/api/v2/podfiles?programid=' . $id;
#	my $url = 'http://api.sr.se/api/v2/broadcasts?programid=' . $id;
#next sort + remove unused programs...
	push @menu, {name        => $title,
		     url         => \&fetch_and_parse_xml,
		     passthrough =>
			 [{
			     parse_fun => \&parseProgramPods,#\&parseProgramBroadcasts,
			     parse_fun_args  => {image_url => $imageUrl},
			     url       => $url
			  }]
	};
	@menu = sort { $a->{name} cmp $b->{name} } @menu;
    }
    return @menu;
}
sub http2SRHandler {
    my $url = shift;
    'sverigesradio://' . substr($url, 7);#test
}

sub parseProgramPod {
    my ($xml, $args) = @_;
    my $imageUrl = $args->{image_url};
    my @menu;
    
    my $title = $xml->{'podfile'}->{'title'};
    my $duration = $xml->{'podfile'}->{'duration'};
    my $description = $xml->{'podfile'}->{'description'};
    my $url = $xml->{'podfile'}->{'url'};
    
    # fetch image from layer above with args passthrough somehow? since it is not part of podfile or fetch it again at this level? but then parse a xml again...

    # NEXT WHY DOES IT NOT PLAY? WHY DID I NOT SUBMIT LAST GIT ;(
    
    push @menu, {name  => $title, #TODO how many chars can radio display? devide it into name2?
		 line1 => $description,#TODO how many chars can radio display? devide it into line2?
		 icon => $imageUrl,
		 type => 'audio',
		 play  => http2SRHandler($url),#'sverigesradio://' . $url, #test
		 duration => $duration, # SR duration is in seconds, what is squeezbox?
		 on_select => 'play'
    };
    $log->info(Data::Dump::dump(@menu));
    return @menu;
}
# SR verkar ha fixat så stream av pod ej fungerar utan förväntar sig att motagaren skall ta hela.
# Man kan kanske använda saveAs i HTTP.p. (Slim/Networking/Async/HTTP) eller öka bufferstorleken
# i HTTP.pm...
# NEXT: Hur seeka i låt på squeezebox radio? Hålla in fwd o rewind!
# Add 3rd level of indention
# Add go to next page on programiid
# Check xml.pm file to see what more parameters are good to set / parse
# NEXT: favorites
# NEXT: live channels
# New feeds (favorites broadcast and pods list)
#? check SR app
sub parseProgramPods {
    my ($xml, $args) = @_;
    my @menu;
#    $log->info(Data::Dump::dump($xml));

# id is head element according to xml
    for my $id (keys %{$xml->{'podfiles'}->{'podfile'}}) {
#	my $image = $xml->{'broadcasts'}->{'broadcast'}->{$title}->{'image'};
	my $title = $xml->{'podfiles'}->{'podfile'}->{$id}->{'title'};
#	$log->info(Data::Dump::dump($title));
	my $url = 'http://api.sr.se/api/v2/podfiles/' . $id;

#	my $url = $xml->{'podfiles'}->{'podfile'}->{$id}->{'url'};
#	my $duration = $xml->{'broadcasts'}->{'broadcast'}->{$id}->{'broadcastfiles'}->{'broadcastfile'}->{'duration'};
#	$log->info(Data::Dump::dump($url));
	push @menu, {name  => $title,
		     url         => \&fetch_and_parse_xml,
		     passthrough =>
			 [{
			     parse_fun => \&parseProgramPod,
			     parse_fun_args => $args,
			     url       => $url,
			  }]
	};

#		     type => 'audio',
		     # SR duration is in seconds, what is squeezbox?
#		     duration => $duration,
#		     play => $url,
#		     on_select => 'play'
			 # broadcasts are m4a files
			 # can not play m4a files! since outside decoder used that does not work...
			 #see http://forums.slimdevices.com/showthread.php?82324-Playing-m4a-%28AAC%29-with-Squeezebox-Server
    }
    return @menu;
}

sub parseProgramBroadcasts {
    my ($xml, $args) = @_;
    my @menu;
#    $log->info(Data::Dump::dump($xml));

# id is head element according to xml
    for my $id (keys %{$xml->{'broadcasts'}->{'broadcast'}}) {
#	my $image = $xml->{'broadcasts'}->{'broadcast'}->{$title}->{'image'};
	my $title = $xml->{'broadcasts'}->{'broadcast'}->{$id}->{'title'};
#	$log->info(Data::Dump::dump($title));
	# Always only one broadcastfile?
	my $url = $xml->{'broadcasts'}->{'broadcast'}->{$id}->{'broadcastfiles'}->{'broadcastfile'}->{'url'};
#	my $duration = $xml->{'broadcasts'}->{'broadcast'}->{$id}->{'broadcastfiles'}->{'broadcastfile'}->{'duration'};
#	$log->info(Data::Dump::dump($url));
	push @menu, {name        => $title,
		     type => 'audio',
		     # SR duration is in seconds, what is squeezbox?
#		     duration => $duration,
		     play => $url,
		     on_select => 'play'
			 # broadcasts are m4a files
			 # can not play m4a files! since outside decoder used that does not work...
			 #see http://forums.slimdevices.com/showthread.php?82324-Playing-m4a-%28AAC%29-with-Squeezebox-Server
	};
    }
    $log->info(Data::Dump::dump(@menu));
    return @menu;
}

# Podfiles are mp3 so should be able to use them.
#NEXT why only 5 xml entries for all programs?
#because it only return 10 per page...
# http://sverigesradio.se/api/documentation/v2/generella_parametrar.html#filter säger att man kan ha
#http://api.sr.se/api/v2/programs?pagination=false för att få allt :)

# good resource = Slim.Web.XMLBrowser ! (handling menu entries from this)

sub fetch_and_parse_xml{
    my ($client, $cb, $params, $args) = @_;
    my $url = $args->{url};
    my $parseFun = $args->{parse_fun};
    my $parseFunArgs = $args->{parse_fun_args};

    my $http = Slim::Networking::SimpleAsyncHTTP->new(
	sub {
	    my $response = shift;
	    my $xml = eval {
		XMLin( 
		    $response->contentRef
		    )
	    };
	    my @menu = $parseFun->($xml, $parseFunArgs);
	    $log->info(Data::Dump::dump(scalar(@menu)));
	    
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

1;
