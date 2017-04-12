package Plugins::SverigesRadio::Plugin;


# sudo service logitechmediaserver restart
# sudo chown -R squeezeboxserver SverigesRadio/
# sudo squeezeboxserver --debug plugin.sverigesradio=INFO,persist

use strict;
use base qw(Slim::Plugin::OPMLBased);

use File::Spec::Functions qw(catdir);
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(cstring);
use Slim::Networking::SimpleAsyncHTTP;
use XML::Simple;

use Data::Dumper;
use LWP::UserAgent;

use Encode;

my $log = Slim::Utils::Log->addLogCategory( {
	category     => 'plugin.sverigesradio',
	defaultLevel => 'INFO',
	description  => 'PLUGIN_SVERIGES_RADIO',
} );

my $prefs = preferences('plugin.sverigesradio');

# default values for settings?
	# If the page is just being displayed initially, then this puts the current value found in prefs on the page.
# so mayby try to set them in initPlugin?

sub initPlugin {
	my $class = shift;

	if (main::WEBUI) {
		require Plugins::SverigesRadio::Settings;
		Plugins::SverigesRadio::Settings->new();
	}

	$class->SUPER::initPlugin(
	    feed   => \&handleFeed,
	    tag    => 'sverigesradio',
	    menu   => 'radios',
   	    weight => 1,
	);
}

# Don't add this item to any menu
sub playerMenu { }
sub getDisplayName { 'PLUGIN_SVERIGES_RADIO_NAME' }

sub generate_favorite_programs {
    my ($client, $cb, $params, $args) = @_;
    my $favoritesRef = $prefs->get('FavoriteIds');
    my @menu = ();
    $log->info(Data::Dump::dump(@$favoritesRef));

    for my $favorite (@$favoritesRef)
    {
	$log->info(Data::Dump::dump($favorite));
	
	push @menu, {name        => $favorite->{'title'},
		     icon        => $favorite->{'icon'},
		     url         => \&fetch_and_parse_xml,
		     passthrough =>
			 [{
			     parse_fun => \&parseProgramPods,
			     parse_fun_args  => {},
			     url => 'http://api.sr.se/api/v2/podfiles?programid=' . $favorite->{'id'}
			  }]
	};	
    }
    $log->info(Data::Dump::dump(@menu));
    $cb->( {items => \@menu} );
}

sub lookupAndSetFavoriteIds {
    my ($class, $programFavorites) = @_;
    my $url = 'http://api.sr.se/api/v2/programs/index?isarchived=false&pagination=false';
    my @titles = split(';', $programFavorites);
    my @programs = ();
    
    my $http = Slim::Networking::SimpleAsyncHTTP->new(
	sub {
	    my $response = shift;
	    my $xml = eval {
		XMLin( 
		    $response->contentRef
		    )
	    };
	    for my $title (@titles) {
		my $id = $xml->{'programs'}->{'program'}->{$title}->{'id'};
		my $iconUrl = $xml->{'programs'}->{'program'}->{$title}->{'programimage'};

		push @programs, {title => $title,
				 id    => $id,
				 icon  => $iconUrl};
	    }

	    $prefs->set('FavoriteIds', \@programs);
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
		    name => cstring($client, 'PLUGIN_SVERIGES_RADIO_FAVORITE_PROGRAMS'),
		    url => \&generate_favorite_programs
		 },
		  {
		      name => cstring($client, 'PLUGIN_SVERIGES_RADIO_ALL_PROGRAMS'),
		      url  => \&fetch_and_parse_xml,
		      passthrough =>
			  [{
			      parse_fun => \&parsePrograms,
			      parse_fun_args => {},
			      # See http://sverigesradio.se/api/documentation/v2/metoder/program.html
			      # and http://sverigesradio.se/api/documentation/v2/generella_parametrar.html
			      # for more details on url generation
			      
			      # Ask for all programs that are active and ask for everyone at once
			      url        => 'http://api.sr.se/api/v2/programs/index?isarchived=false&haspod=true&pagination=false'
				  #http://api.sr.se/api/v2/programs?pagination=false',
				  #'http://api.sr.se/api/v2/programs/index',
			   }]
		  },{
		      name => cstring($client, 'PLUGIN_SVERIGES_RADIO_CHANNELS'),
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
    my @favoriteChannels = split(';', $prefs->get('channelFavorites'));
    $log->info(Data::Dump::dump(@favoriteChannels));

    for my $name (keys %{$xml->{'channels'}->{'channel'}}) {
	my $type = $xml->{'channels'}->{'channel'}->{$name}->{'channeltype'};
	my $url = $xml->{'channels'}->{'channel'}->{$name}->{'liveaudio'}->{'url'};
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
    push( @realmChannels, @menu);
    $log->info(Data::Dump::dump(@realmChannels));
    return @realmChannels;
}

sub parsePrograms {
    my ($xml) = @_;
    my @menu;

    for my $title (keys %{$xml->{'programs'}->{'program'}}) {
	my $id = $xml->{'programs'}->{'program'}->{$title}->{'id'};
	my $imageUrl = $xml->{'programs'}->{'program'}->{$title}->{'programimage'};
	my $url = 'http://api.sr.se/api/v2/podfiles?programid=' . $id;

	push @menu, {name        => $title,
		     url         => \&fetch_and_parse_xml,
		     passthrough =>
			 [{
			     parse_fun => \&parseProgramPods,
			     parse_fun_args  => {image_url => $imageUrl},
			     url       => $url
			  }]
	};
	@menu = sort { $a->{name} cmp $b->{name} } @menu;
    }
    return @menu;
}
sub tmpLocalDownload {
    # since sr have some fault in their server, it is not possible to stream an audio file
    # consistently (timeout problems)
    # See https://kundo.se/org/sverigesradio/d/squeezebox-radio-poddfiler-stannar-efter-en-viss-t/
    #
    # Instead download the audio file localy to /tmp on LMS server and stream it locally to the player

    # Remove All old files
    unlink glob "/tmp/SverigesRadio_tmp_*";
    my $url = shift;

    # use timestamp in name so name is unique
    my $timestamp = getLoggingTime();
    my $filename = '/tmp/SverigesRadio_tmp_'. $timestamp . 'pod.mp3';
    download($url, $filename);

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
    
    push @menu, {name  => $title, #TODO how many chars can radio display? devide it into name2?
		 line1 => $description,#TODO how many chars can radio display? devide it into line2?
		 icon => $imageUrl,
		 type => 'audio',
		 play  => tmpLocalDownload($url),
		 duration => $duration, # SR duration is in seconds, what is squeezbox?
		 on_select => 'play'
    };
    return @menu;
}
sub parseProgramPods {
    my ($xml, $args) = @_;
    my @menu;
    $log->info(Data::Dump::dump($xml));

    # id is head element according to xml
    for my $id (keys %{$xml->{'podfiles'}->{'podfile'}}) {
	my $title = $xml->{'podfiles'}->{'podfile'}->{$id}->{'title'};
	my $url = 'http://api.sr.se/api/v2/podfiles/' . $id;
	my $publishDate = $xml->{'podfiles'}->{'podfile'}->{$id}->{'publishdateutc'};

	push @menu, {name  => $title,
		     published => $publishDate, # Ok to use this custom hash field for own purpose
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
    # Display in newst -> oldest order
    @menu = sort { $b->{published} cmp $a->{published} } @menu;
    return @menu;
}

# Podfiles are mp3 so should be able to use them.
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
