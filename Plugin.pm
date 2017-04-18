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

my $log = Slim::Utils::Log->addLogCategory( {
	category     => 'plugin.sverigesradio',
	defaultLevel => 'INFO',
	description  => 'PLUGIN_SVERIGES_RADIO',
} );

my $prefs = preferences('plugin.sverigesradio');

# default values for settings?
# If the page is just being displayed initially, then this puts the current value found in prefs on the page.
# so mayby try to set them in initPlugin?

sub check_set_default_prefs {
	if ($prefs->get('programFilter') eq '') {	
	    $prefs->set('programFilter', 'http://api.sr.se/api/v2/programs/index?isarchived=false&pagination=false');
	}
	if ($prefs->get('maxNrOfPods') eq '') {	
	    $prefs->set('maxNrOfPods', 10);
	}
	
}

sub initPlugin {
	my $class = shift;

	if (main::WEBUI) {
		require Plugins::SverigesRadio::Settings;
		Plugins::SverigesRadio::Settings->new();
	}

	check_set_default_prefs(),
	
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
	
	push @menu, {name        => $favorite->{title},
		     icon        => $favorite->{icon},
		     url         => \&fetch_and_parse_xml,
		     passthrough =>
			 [{
			     parse_fun => \&parseProgramPods,
			     parse_fun_args  => {},
			     url => getProdsUrl($favorite->{'id'})
			  }]
	};	
    }
    $log->info(Data::Dump::dump(@menu));
    $cb->( {items => \@menu} );
}

sub lookupAndSetFavoriteIds {
    my ($class, $programFavorites) = @_;
    my $url = $prefs->get('programFilter');
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
		my $id = $xml->{programs}->{program}->{$title}->{id};
		my $iconUrl = $xml->{programs}->{program}->{$title}->{programimage};

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
	  },{
		      name => cstring($client, 'PLUGIN_SVERIGES_RADIO_LATEST_SHORT_NEWS'),
		      #See http://sverigesradio.se/api/documentation/v2/metoder/ljud.html
		      play => 'http://sverigesradio.se/api/radio/radio.aspx?type=latestbroadcast&id=4540&codingformat=.m4a&metafile=m3u',
		      on_select => 'play',
		      type => 'audio'
		  },{
		      name => cstring($client, 'PLUGIN_SVERIGES_RADIO_LATEST_MEDIUM_NEWS'),
		      # Since 'short' hourly EKO broadcasts are not kept as pod files
		      # asking for the latest EKO pod file will result in last 'big' news
		      # package
		      # See http://sverigesradio.se/sida/artikel.aspx?programid=3756&artikel=3498476 for more details
		      play => 'http://sverigesradio.se/topsy/senastepodd/3795.mp3',
		      on_select => 'play',
		      type => 'audio'
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
			      url        => $prefs->get('programFilter')#$'http://api.sr.se/api/v2/programs/index?isarchived=false&haspod=true&pagination=false'
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

    for my $name (keys %{$xml->{channels}->{channel}}) {
	my $type = $xml->{channels}->{channel}->{$name}->{channeltype};
	my $image = $xml->{channels}->{channel}->{$name}->{image};
	my $url = $xml->{channels}->{channel}->{$name}->{liveaudio}->{'url'};
	my $channel = {name => $name,
		       icon => $image,
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
sub getProdsUrl {
    my ($id) = @_;
    my $MaxNrOfPods = $prefs->get('maxNrOfPods') || 10;
    my $url = 'http://api.sr.se/api/v2/podfiles?programid=' . $id . '&size=' . $MaxNrOfPods;
}
sub parsePrograms {
    my ($xml) = @_;
    my @menu;
    
    for my $title (keys %{$xml->{programs}->{program}}) {
	my $id = $xml->{programs}->{program}->{$title}->{id};
	my $imageUrl = $xml->{programs}->{program}->{$title}->{programimage};
#	my $url = 'http://api.sr.se/api/v2/podfiles?programid=' . $id;
	my $url = getProdsUrl($id);

	push @menu, {name        => $title,
		     icon        => $imageUrl,
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
sub parseProgramPods {
    my ($xml, $args) = @_;
    my @menu;
    $log->info(Data::Dump::dump($xml));

    # id is head element according to xml
    for my $id (keys %{$xml->{podfiles}->{podfile}}) {
	my $title = $xml->{podfiles}->{podfile}->{$id}->{title};
	my $url = $xml->{podfiles}->{podfile}->{$id}->{url};
	my $publishDate = $xml->{podfiles}->{podfile}->{$id}->{publishdateutc};

	push @menu, {name  => $title,
		     published => $publishDate, # Ok to use this custom hash field for own purpose
		     type => 'audio',
		     on_select => 'play',
		     play  => $url
	};
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
