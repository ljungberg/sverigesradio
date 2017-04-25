package Plugins::SverigesRadio::Plugin;

# Plugin to play pods and channels from sr.se (Sveriges Radio)

# Lazy instructions how to initiate a compile-restart cycle
# --------------------------------------------------------

# only once per computer restart
# /usr/share/squeezeboxserver/Plugins$ sudo service logitechmediaserver stop
# 
# /usr/share/squeezeboxserver/Plugins$ sudo chown -R squeezeboxserver SverigesRadio/
# /usr/share/squeezeboxserver/Plugins$ sudo squeezeboxserver --debug plugin.sverigesradio=INFO,persist

use strict;
use base qw(Slim::Plugin::OPMLBased);

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(cstring);
use Slim::Networking::SimpleAsyncHTTP;
use XML::Simple;

use Data::Dumper;

my $log = Slim::Utils::Log->addLogCategory( {
    category     => 'plugin.sverigesradio',
    # defaultLevel is the defualt debug level of this plugin!
    # i.e keep OFF by default... Can be changed in web GUI
    # 'Settings'->'Advanced' choose 'Logging' in drop down menu
    defaultLevel => 'OFF',
    description  => 'PLUGIN_SVERIGES_RADIO'
					    } );

my $prefs = preferences('plugin.sverigesradio');

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

sub getDisplayName { 'PLUGIN_SVERIGES_RADIO' }

# Set up the top menu under 'Home > SverigesRadio'
sub handleFeed {
    my ($client, $cb, $params) = @_;
    $cb->({
	items => [{
	    name => cstring($client, 'PLUGIN_SVERIGES_RADIO_FAVORITE_PROGRAMS'),
	    url => \&generate_favorite_programs
	  },{
	      name => cstring($client, 'PLUGIN_SVERIGES_RADIO_LATEST_MEDIUM_NEWS'),
		      # Since 'short' hourly EKO broadcasts are not kept as pod files
		      # asking for the latest EKO pod file will result in last 'big' news
		      # package
		      # See http://sverigesradio.se/sida/artikel.aspx?programid=3756&artikel=3498476 for more details
		      play => 'http://sverigesradio.se/topsy/senastepodd/3795.mp3',
		      on_select => 'play',
		      type => 'audio'
		  },{
		      name => cstring($client, 'PLUGIN_SVERIGES_RADIO_ALL_PROGRAMS'),
		      url  => \&fetch_and_parse_xml,
		      passthrough =>
			  [{
			      parse_fun => \&parsePrograms,
			      parse_fun_args => {},
			      url        => $prefs->get('programFilter')
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

# Take Programs Title, Icon url and ID saved in preference
# and construct menu items
sub generate_favorite_programs {
    my ($client, $cb, $params, $args) = @_;
    my $favoritesRef = $prefs->get('FavoriteIds');
    main::DEBUGLOG && $log->debug(@$favoritesRef);
    my @menu;

    for my $favorite (@$favoritesRef)
    {
	push @menu, {name        => $favorite->{title},
		     icon        => $favorite->{icon},
		     url         => \&fetch_and_parse_xml,
		     passthrough =>
			 [{
			     parse_fun => \&parseProgramPods,
			     parse_fun_args  => {},
			     url => getPodsUrl($favorite->{'id'})
			  }]
	};	
    }
    main::DEBUGLOG && $log->debug(sub { return Data::Dump::dump(@menu); });
    $cb->( {items => \@menu} );
}

# Get menu items from returned xml file from 'http://api.sr.se/api/v2/channels/index?...'
sub parseChannels {
    my ($xml) = @_;
    my @menu;
    my %menuHash;
    my @realmChannels;
    my @favoriteChannels = split(';', $prefs->get('channelFavorites'));
    main::DEBUGLOG && $log->debug(sub { return Data::Dump::dump(@favoriteChannels); });

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
	# place all 'Rikskanal' channels and favorite channels at the top level
	if ( ($type eq "Rikskanal") || grep(/^$name$/, @favoriteChannels) ) {
	    push @realmChannels, $channel;
	}
	# and the rest in corresponding sub-menues
	elsif (not exists $menuHash{$type}) {
	    @menuHash{$type} = [$channel];
	}
	else
	{
	    #NEXT why not work on pi but on develop computer? different perl?
	    push @menuHash{$type}, $channel;
	}
    }
    for my $radioType (keys %menuHash) {
	push @menu, {name => $radioType,
		     items => $menuHash{$radioType}};
    }

    @menu = sort { $a->{name} cmp $b->{name} } @menu;
    @realmChannels = sort { $a->{name} cmp $b->{name} } @realmChannels;
    push( @realmChannels, @menu);
    main::DEBUGLOG && $log->debug(sub { return Data::Dump::dump(@realmChannels); });
    return @realmChannels;
}

# Get menu items from returned xml file from 'http://api.sr.se/api/v2/programs/index?...'
sub parsePrograms {
    my ($xml) = @_;
    my @menu;
    
    for my $title (keys %{$xml->{programs}->{program}}) {
	my $id = $xml->{programs}->{program}->{$title}->{id};
	my $imageUrl = $xml->{programs}->{program}->{$title}->{programimage};
	my $url = getPodsUrl($id);

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
     main::DEBUGLOG && $log->debug(sub { return Data::Dump::dump(@menu); });
    return @menu;
}

# Get menu items from returned xml file from 'http://api.sr.se/api/v2/podfiles?programid=...'
sub parseProgramPods {
    my ($xml, $args) = @_;
    my @menu;
     main::DEBUGLOG && $log->debug(sub { return Data::Dump::dump($xml); });

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
     main::DEBUGLOG && $log->debug(sub { return Data::Dump::dump(@menu); });
    return @menu;
}

# Fetch xml file pointed to in 'url' asynchronously and apply xml parser2menu
# function defined in 'parse_fun' with arguments 'parse_fun_args'
sub fetch_and_parse_xml{
    my ($client, $cb, $params, $args) = @_;
    my $url = $args->{url};
     main::DEBUGLOG && $log->debug(sub { return Data::Dump::dump($url); });
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

	    $cb->({
		items => \@menu,
		  });
	},
	sub {
	    my ($http, $error) = @_;
	     main::DEBUGLOG && $log->warn("Error: $error");
	},
	{
	    timeout => 15,
	},
	);
    $http->get($url);
}

# To be used by Settings.pm
# When the user enter favorite Program Titles this
# function will look up the corresponding ID and
# Icon url to be saved in preference.
sub lookupAndSetFavoriteIds {
    my ($class, $programFavorites) = @_;
     main::DEBUGLOG && $log->debug($programFavorites);
    my $url = $prefs->get('programFilter');
     main::DEBUGLOG && $log->debug($url);
    my @titles = split(';', $programFavorites);
    my @programs;
    
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
	     main::DEBUGLOG && $log->debug(sub { return Data::Dump::dump($prefs->get('FavoriteIds')); });
	},
	sub {
	    my ($http, $error) = @_;
	     main::DEBUGLOG && $log->warn("Error: $error");
	},
	{
	    timeout => 15,
	},
	);
    $http->get($url);
}

# Set (required) default values the first time plugin is run
sub check_set_default_prefs {
	if ($prefs->get('programFilter') eq '') {	
	    $prefs->set('programFilter', 'http://api.sr.se/api/v2/programs/index?isarchived=false&pagination=false');
	}
	if ($prefs->get('maxNrOfPods') eq '') {	
	    $prefs->set('maxNrOfPods', 10);
	}
	
}

sub getPodsUrl {
    my ($id) = @_;
    my $MaxNrOfPods = $prefs->get('maxNrOfPods') || 10;
    my $url = 'http://api.sr.se/api/v2/podfiles?programid=' . $id . '&size=' . $MaxNrOfPods;
}

1;
