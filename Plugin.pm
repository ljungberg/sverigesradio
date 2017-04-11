package Plugins::SverigesRadio::Plugin;


# sudo service logitechmediaserver restart
# sudo chown -R squeezeboxserver SverigesRadio/
# sudo squeezeboxserver --debug plugin.sverigesradio=INFO,persist

use strict;
use base qw(Slim::Plugin::OPMLBased);

use File::Spec::Functions qw(catdir);
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Networking::SimpleAsyncHTTP;
use XML::Simple;

use Slim::Player::ProtocolHandlers;
use Plugins::SverigesRadio::ProtocolHandler;

use Data::Dumper;
use LWP::UserAgent;

use Encode;

my $log = Slim::Utils::Log->addLogCategory( {
	category     => 'plugin.sverigesradio',
	defaultLevel => 'INFO',
#	defaultLevel => 'ERROR',
	description  => 'PLUGIN_SVERIGES_RADIO',
} );

my $prefs = preferences('plugin.sverigesradio');

# default values for settings?
	# If the page is just being displayed initially, then this puts the current value found in prefs on the page.
# so mayby try to set them in initPlugin?

# list of things
#	my @newLibraries = split(/;/, $prefs->get('libraries')); from simple library view

# how to use?
#??
# add favorite channels


sub initPlugin {
	my $class = shift;

	if (main::WEBUI) {
		require Plugins::SverigesRadio::Settings;
		Plugins::SverigesRadio::Settings->new();
	}
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
sub generate_favorite_programs {
    my ($client, $cb, $params, $args) = @_;
    my @ProgramAndIds = split(';' , $prefs->get('FavoriteIds'));#split(/;/, $prefs->get('programFavorites'));
    my @menu;
    $log->info(Data::Dump::dump(@ProgramAndIds));

    for my $Favorite (@ProgramAndIds)
    {
	my ($Title, $id) = split(':', $Favorite);
	$log->info(Data::Dump::dump($Favorite));
	
	push @menu, {name        => $Title,
		     url         => \&fetch_and_parse_xml,
		     passthrough =>
			 [{
			     parse_fun => \&parseProgramPods,
			     parse_fun_args  => {},
			     url => 'http://api.sr.se/api/v2/podfiles?programid=' . $id
			  }]
	};	
    }
    $log->info(Data::Dump::dump(@menu));
	    $cb->({
		items => \@menu,
		  });
}

# Keep information in a textstring, since I'm unsure how hashes
# and array's are managed in the Pref module between sessions
# (for example when 'set' ing an array only the first element
# seem to be 'set')
#
# Instead keep the infomation in the following format:
# "Title:Id;NextTitle:NextId" etc.
sub lookupAndSetFavoriteIds {
    my ($class, $ProgramFavorites) = @_;
    $log->info(Data::Dump::dump($class));
    $log->info(Data::Dump::dump($ProgramFavorites));
    my $url = 'http://api.sr.se/api/v2/programs/index?isarchived=false&pagination=false';
    my @Titles = split(/;/, $ProgramFavorites);
    my @Programs = ();
    
    my $http = Slim::Networking::SimpleAsyncHTTP->new(
	sub {
	    my $response = shift;
	    my $xml = eval {
		XMLin( 
		    $response->contentRef
		    )
	    };
	    for my $Title (@Titles) {
		my $id = $xml->{'programs'}->{'program'}->{$Title}->{'id'};
		push @Programs, ($Title . ':' . $id);
	    }

	    # For some reasons the set method only sets the first hash in the array
	    # so 'join' is a workaround...
	    $prefs->set('FavoriteIds', join(';', @Programs));
	    $log->info(Data::Dump::dump($prefs->get('FavoriteIds')));
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
# refactor above with this func:
#sub fetchXmlByAsyncHttp(URL,XmlSuccessCallback)

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
		      name => "Favorit Program",
		      url => \&generate_favorite_programs
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
    # use decode to handle åäö correctly
#Radioapans knattekanal"
#    my @favoriteChannels =(decode('utf8', "P4 Väst") );#("P4 V\xE4st"); #("P4 Väst");# split(/;/, $ChannelFavorites);
    #    my @favoriteChannels = split(';', decode('utf8', $prefs->get('channelFavorites')));
    my @favoriteChannels = split(';', $prefs->get('channelFavorites'));
    $log->info(Data::Dump::dump(@favoriteChannels));

    for my $name (keys %{$xml->{'channels'}->{'channel'}}) {
	my $type = $xml->{'channels'}->{'channel'}->{$name}->{'channeltype'};
	my $url = $xml->{'channels'}->{'channel'}->{$name}->{'liveaudio'}->{'url'};
	#NEXT: put in hases then new menues
	my $channel = {name => $name,
		       type => 'audio',
		       play  => $url,
		       on_select => 'play'
	};
	if ( ($type eq "Rikskanal") || grep(/^$name$/, @favoriteChannels) ) {
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
#    $log->info(Data::Dump::dump(%menuHash));
    for my $radioType (keys %menuHash) {
	push @menu, {name => $radioType,
		     items => $menuHash{$radioType}};
    }

    @menu = sort { $a->{name} cmp $b->{name} } @menu;
    @realmChannels = sort { $a->{name} cmp $b->{name} } @realmChannels;
#    $log->info(Data::Dump::dump(@realmChannels));
 #   $log->info(Data::Dump::dump(@menu));
    push( @realmChannels, @menu);
    $log->info(Data::Dump::dump(@realmChannels));
#NEXT favorites ('save' in menu) for channelse
    return @realmChannels;
}

sub parsePrograms {
    my ($xml) = @_;
    my @menu;

    $log->info(Data::Dump::dump($prefs->get('programFilter')));
    $log->info(Data::Dump::dump($prefs->get('programFavorites')));

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
    #NEXT it does not work when the 'last' file is open (which will be when the player starts at last track) so file is open when we try to write to it etc
    # Remove All old files
    unlink glob "/tmp/SverigesRadio_tmp_*";
    my $url = shift;
#    'sverigesradio://' . substr($url, 7);#test
#    $url;
    # use timestamp in name so name is unique
    my $timestamp = getLoggingTime();
    my $filename = '/tmp/SverigesRadio_tmp_'. $timestamp . 'pod.mp3';
    download($url, $filename);
    #    'tmp://tmp/sample.mp3';
    'tmp://' . $filename;
}
sub getLoggingTime {

    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time);
    my $nice_timestamp = sprintf ( "%04d%02d%02d %02d:%02d:%02d",
                                   $year+1900,$mon+1,$mday,$hour,$min,$sec);
    return $nice_timestamp;
}
sub download {
    my $url = shift;
    my $filename = shift;
    my $ua = LWP::UserAgent->new;
    my $req = HTTP::Request->new(GET => $url);
    my $res = $ua->request($req, $filename);    
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

    
    push @menu, {name  => $title, #TODO how many chars can radio display? devide it into name2?
		 line1 => $description,#TODO how many chars can radio display? devide it into line2?
		 icon => $imageUrl,
		 type => 'audio',
		 play  => http2SRHandler($url),#'sverigesradio://' . $url, #test
		 duration => $duration, # SR duration is in seconds, what is squeezbox?
		 on_select => 'play'
    };
#    $log->info(Data::Dump::dump(@menu));
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
    $log->info(Data::Dump::dump($xml));

# id is head element according to xml
    for my $id (keys %{$xml->{'podfiles'}->{'podfile'}}) {
#	my $image = $xml->{'broadcasts'}->{'broadcast'}->{$title}->{'image'};
	my $title = $xml->{'podfiles'}->{'podfile'}->{$id}->{'title'};
#	$log->info(Data::Dump::dump($title));
	my $url = 'http://api.sr.se/api/v2/podfiles/' . $id;
#	$log->info(Data::Dump::dump($url));

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
    # Strange, menu items have to be sorted on name it seems...
    # (otherwise it does not work to select in player GUI, it choose another item then the displayed one)
    #NEXT add date and sort according to date...
    @menu = sort { $a->{name} cmp $b->{name} } @menu;
#    $log->info(Data::Dump::dump(@menu));
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
    @menu = sort { $a->{name} cmp $b->{name} } @menu;
#    $log->info(Data::Dump::dump(@menu));
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
#    $log->info(Data::Dump::dump($url));
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
#	    $log->info(Data::Dump::dump(scalar(@menu)));
	    
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
