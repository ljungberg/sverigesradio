package Plugins::SverigesRadio::Plugin;

# $Id$
#  335  sudo service logitechmediaserver restart
#  336  sudo chown -R squeezeboxserver MyHelloWorld/
#sudo squeezeboxserver --debug plugin.myhelloworld=INFO,persist

use strict;
use base qw(Slim::Plugin::OPMLBased);
use File::Spec::Functions qw(catdir);
use Slim::Utils::Log;

my $log = Slim::Utils::Log->addLogCategory( {
	category     => 'plugin.sverigesradio',
	defaultLevel => 'INFO',
#	defaultLevel => 'ERROR',
	description  => 'PLUGIN_SVERIGES_RADIO',
} );

sub initPlugin {
	my $class = shift;

	my $file = catdir( $class->_pluginDataFor('basedir'), 'menu.opml' );
	$log->info("file is $file");

	$class->SUPER::initPlugin(
	    feed   => Slim::Utils::Misc::fileURLFromPath($file), #\&handleFeed,
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
    my $items = [{name => "file",
		  play => 'http://sverigesradio.se/topsy/ljudfil/4381232.mp3',
	          on_select => 'play'}];
    
    $cb->({
	items => $items
	  });
}
1;
