package Plugins::SverigesRadio::Settings;


use strict;
use base qw(Slim::Web::Settings);
use Slim::Utils::Prefs;
use Slim::Utils::Log;
use Plugins::SverigesRadio::Plugin;

# Used for logging.
my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.sverigesradio',
	'defaultLevel' => 'INFO',
	'description'  => 'SverigesRadio Settings',
});

my $prefs = preferences('plugin.sverigesradio');

sub name {
	return Slim::Web::HTTP::CSRF->protectName('PLUGIN_SVERIGES_RADIO_NAME');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('plugins/SverigesRadio/settings/basic.html');
}

sub prefs {
	return ($prefs, 'filterProgramsQuery', 'favoritePrograms');
}
sub handler {
	my ($class, $client, $params) = @_;
	
	if ($params->{'saveSettings'} && $params->{'programFilter'}) {
		if ($params->{'programFilter'}) {
			$prefs->set('programFilter', $params->{'programFilter'});
		}
	
		if ($params->{'programFavorites'} ) {
			$prefs->set('programFavorites', $params->{'programFavorites'});
			$log->info(Data::Dump::dump($params->{'programFavorites'}));

			Plugins::SverigesRadio::Plugin->lookupAndSetFavoriteIds($params->{'programFavorites'});
		}
		
		if ($params->{'channelFavorites'} ) {
		    $prefs->set('channelFavorites', $params->{'channelFavorites'});
		    $log->info(Data::Dump::dump($params->{'channelFavorites'}));
		}	
	}
	
	# This puts the value on the webpage. 
	# If the page is just being displayed initially, then this puts the current value found in prefs on the page.

	# add a leading space to make the message display nicely
	$params->{'prefs'}->{'programFilter'} = $prefs->get('programFilter');
	$params->{'prefs'}->{'programFavorites'} = $prefs->get('programFavorites');
	$params->{'prefs'}->{'channelFavorites'} = $prefs->get('channelFavorites');

	# I have no idea what this does, but it seems important and it's not plugin-specific.
	return $class->SUPER::handler($client, $params);
}

1;

__END__
