package Plugins::SverigesRadio::ProtocolHandler;

# Handler for sverigesradio:// URLs

use strict;
use base qw(Slim::Player::Protocols::HTTP);
use Scalar::Util qw(blessed);

use Slim::Utils::Log;

my $log   = logger('plugin.sverigesradio');

sub new {
	my $class = shift;
	my $args  = shift;

	if (!$args->{'song'}) {

#		logWarning("No song passed!");
		
		# XXX: MusicIP abuses this as a non-async HTTP client, can't return undef
		# return undef;
	}

	my $self = $class->open($args);

	if (defined($self)) {
		${*$self}{'client'}  = $args->{'client'};
		${*$self}{'url'}     = $args->{'url'};
	}
	$log->info("fungerade att skapa stream med prefix sverigesradio");	return $self;
}

# Sveriges Radio use 128 KBit mp3. To buffer 1h we need
# (128 * 3600) / 8 KBytes (5760)
sub bufferThreshold { 57600 }

sub scanUrl {
	my ($class, $url, $args) = @_;
	$log->info("fungerade att skapa stream med prefix sverigesradio");
	$args->{'cb'}->($args->{'song'}->currentTrack());
}

#NEXT:
#since scan url was not used from base HTTP we probably need to implement the other functions in HTTP base? check qobuz and see whats overlap between qobuz protocolhandler and http...
1;
