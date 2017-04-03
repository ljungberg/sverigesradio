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
	my $song      = $args->{song};

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
#	$log->info("Song: ");
#	$log->info(Data::Dump::dump($song));
#	$log->info("fungerade att skapa stream med prefix sverigesradio");
	return $self;
}
# Sveriges Radio use 128 KBit mp3. To buffer 1h we need
# (128 * 3600) / 8 KBytes (5760)
sub bufferThreshold { 57600 }


# sub isRemote { 1 }

# sub readMetaData {
#     my $class = shift;
#     $log->info("readMetaData");
#     $class->SUPER::readMetaData();
# }
# # Needed?
# #sub getFormatForURL {

# sub parseMetadata {
#     my ( $class, $client, undef, $metadata ) = @_;
#     $log->info("parseMetadata");
#     $class->SUPER::parseMetadata($client, undef, $metadata);
# }

# # Sveriges Radio use 128 KBit mp3. To buffer 1h we need
# # (128 * 3600) / 8 KBytes (5760)
# sub bufferThreshold { 57600 }

# sub canDirectStream { 0 }

# sub parseHeaders {
#     my $class = shift;
#     $log->info("parseHeaders");
#     $class->SUPER::parseHeaders;
# }

# # not needed I think
# #sub requestString {

# # needed?
# #sub sysread {

# # not needed since cannot direct stream...
# #sub parseDirectHeaders {


# #work!
# sub getMetadataFor{
#     my ( $class, $client, $url, $forceCurrent ) = @_;
#     my $r = $class->SUPER::getMetadataFor($client, $url, $forceCurrent);
# # for some reason HTTP::getMetadataFor does not set duration/bitrate
#     $r->{'bitrate'} = 128_000;
#     $r->{'duration'} = 60; #test to se if track start playing
#     #NOW: 'song' does not contain bitrate / duration. BUT I think it did when we only implemnted scanURL and notihg else...
#     #NEXT: go back to only implement scanURL / buffer sub and check that it really start playing...
#WORK: No meta data though / no seek
#     #NEXT enable remote logging and DONT use sveriges radio protocol handler and inspect how it function for HTTP base class
#WORK: Metadata and seek got from stream a second after start
# #    $log->info(Data::Dump::dump($r));
#     return $r;
# }

sub scanUrl {
    my ($class, $url, $args) = @_;
    $log->info("scanUrl");
    $args->{'cb'}->($args->{'song'}->currentTrack());
}

# sub getIcon {
#     my ( $class, $url, $noFallback ) = @_;
#     $log->info("getIcon");
#    $class->SUPER::getIcon($url, $noFallback);
# }

# sub canSeek {
#     my ( $class, $client, $song ) = @_;
#     $log->info("canSeek");
#     $class->SUPER::canSeek($client, $song);
# }

# sub canSeekError {
#     my ( $class, $client, $song ) = @_;
#     $log->info("canSeekError");
#     $class->SUPER::canSeekError($client, $song);
# }

# sub getSeekData {
#     my ( $class, $client, $song, $newtime ) = @_;
#     $log->info("getSeekData");
#     $class->SUPER::getSeekData($client, $song, $newtime);
# }

# sub getSeekDataByPosition {
#     my ($class, $client, $song, $bytesReceived) = @_;
#     $log->info("getSeekDataByPosition");
#     $class->SUPER::getSeekDataByPosition($client, $song, $bytesReceived);
# }

#since scan url was not used from base HTTP we probably need to implement the other functions in HTTP base? check qobuz and see whats overlap between qobuz protocolhandler and http...
1;

# Jag tycker ändå att det verkar som om man inte behöver instanciera samma functioner som HTTP utan bara scanURL så den skall returnera rätt
# istf fel (sverigesradio://)

# Verkar som scan url anropas först sedan RemoteStream:open -> RemotStream:request (som anorpar parseHeader funktionen)
#-> new funktionen sedan getIcon o getMetadatafor o en halv sekund senare canSeek o canSeekError
#Remotestream:open anropar remotestream request som anropaer ProtocolHandler:requestString()! (verkar iof ok utan)
# sedan ProtocolHandler -> parseHeaders
#

# [17-03-10 13:09:16.1481] Plugins::SverigesRadio::ProtocolHandler::scanUrl (87) scanUrl
# [17-03-10 13:09:16.1484] Plugins::SverigesRadio::ProtocolHandler::canSeek (99) canSeek
# [17-03-10 13:09:16.1486] Plugins::SverigesRadio::ProtocolHandler::canSeekError (105) canSeekError
# [17-03-10 13:09:16.1488] Slim::Player::Protocols::HTTP::canSeekError (815) bitrate unknown for: sverigesradio://sverigesradio.se/topsy/ljudfil/6018142.mp3
# [17-03-10 13:09:16.1494] Slim::Formats::RemoteStream::open (70) Opening connection to sverigesradio://sverigesradio.se/topsy/ljudfil/6018142.mp3: [sverigesradio.se on port 80 with path /topsy/ljudfil/6018142.mp3 with timeout 15]
# [17-03-10 13:09:16.1672] Slim::Formats::RemoteStream::request (141) Request: GET /topsy/ljudfil/6018142.mp3 HTTP/1.0
# Cache-Control: no-cache
# Connection: close
# Accept: */*
# Host: sverigesradio.se
# User-Agent: iTunes/4.7.1 (Linux; N; Debian; x86_64-linux; EN; utf8) SqueezeCenter, Squeezebox Server, Logitech Media Server/7.9.0/1484464959
# Icy-Metadata: 1

# [17-03-10 13:09:16.2093] Slim::Formats::RemoteStream::request (148) Response: HTTP/1.1 302 Found
# [17-03-10 13:09:16.2103] Plugins::SverigesRadio::ProtocolHandler::parseHeaders (59) parseHeaders
# [17-03-10 13:09:16.2108] Slim::Formats::RemoteStream::request (209) Opened stream!
# [17-03-10 13:09:16.2109] Plugins::SverigesRadio::ProtocolHandler::new (31) fungerade att skapa stream med prefix sverigesradio
# [17-03-10 13:09:16.2119] Plugins::SverigesRadio::ProtocolHandler::getIcon (93) getIcon
# [17-03-10 13:09:16.2122] Plugins::SverigesRadio::ProtocolHandler::getIcon (93) getIcon
# [17-03-10 13:09:16.2127] Plugins::SverigesRadio::ProtocolHandler::getMetadataFor (81) {
#   artist   => undef,
#   bitrate  => 128_000,
#   cover    => "html/images/radio.png",
#   duration => 60,
#   icon     => "html/images/radio.png",
#   title    => "\"Not 7\" av Jonas Rasmussen",
#   type     => "MP3 Radio",
# }
# [17-03-10 13:09:16.2626] Plugins::SverigesRadio::ProtocolHandler::canSeek (99) canSeek
# [17-03-10 13:09:16.2629] Plugins::SverigesRadio::ProtocolHandler::canSeekError (105) canSeekError
# [17-03-10 13:09:16.2631] Slim::Player::Protocols::HTTP::canSeekError (815) bitrate unknown for: sverigesradio://sverigesradio.se/topsy/ljudfil/6018142.mp3
# [17-03-10 13:09:16.2638] Plugins::SverigesRadio::ProtocolHandler::getIcon (93) getIcon
# [17-03-10 13:09:16.2641] Plugins::SverigesRadio::ProtocolHandler::getIcon (93) getIcon
# [17-03-10 13:09:16.2646] Plugins::SverigesRadio::ProtocolHandler::getMetadataFor (81) {
#   artist   => undef,
#   bitrate  => 128_000,
#   cover    => "html/images/radio.png",
#   duration => 60,
#   icon     => "html/images/radio.png",
#   title    => "\"Not 7\" av Jonas Rasmussen",
#   type     => "MP3 Radio",
# }
# [17-03-10 13:09:16.2652] Plugins::SverigesRadio::ProtocolHandler::getIcon (93) getIcon
# [17-03-10 13:09:16.2654] Plugins::SverigesRadio::ProtocolHandler::getIcon (93) getIcon
# [17-03-10 13:09:16.2658] Plugins::SverigesRadio::ProtocolHandler::getMetadataFor (81) {
#   artist   => undef,
#   bitrate  => 128_000,
#   cover    => "html/images/radio.png",
#   duration => 60,
#   icon     => "html/images/radio.png",
#   title    => "\"Not 7\" av Jonas Rasmussen",
#   type     => "MP3 Radio",
# }
