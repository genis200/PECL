use strict;
use warnings;
use Data::Dumper;
use XML::Simple;
use File::Slurp;
use Scalar::Util;
use IO::Socket::INET;
use Digest::MD5;
use JSON;

package PECL::Penguin;

sub new {
	shift;
	my $self = {};
	bless($self);

	$self->{socket} = undef;
	$self->{alive} = 1; # This is set to 0 before the penguin is destroyed, for UnderHandler calls.
	$self->{player} = 	{
							userName => '',
							password => '',
							server => undef,
							loggedIn => 0,
							isLogin => 1,
							xmlMode => 1,
							playerID => 0,
							loginKey => '',
							confirmKey => '',
							rawPlayer => '',
							
						};
	$self->{jobs} =		{	
#							timerJob => {lastExecuted => time(), timer => 5, callBack => \&null} # timerJob => Name of Job, lastExecuted => unix timestamp that the job was last executed, timer => number of seconds between each execution, callback => function to call when job is complete. NOTE: THESE SHOULD BE DEFINED IN SCRIPT!
						};
	
	$self->{handlers} = {
							xml => {rndK => \&handleRandomKey, ALL => undef},
							xt => {e => \&handleGameError, l => \&handleSuccessfulLogin, loggedIn => undef, ALL => undef},
						};
	
	
	
	$self->{servers} = JSON::from_json(File::Slurp::read_file('./PECL/JSON/servers.json'));
	$self->{rooms} = JSON::from_json(File::Slurp::read_file('./PECL/JSON/rooms.json'));
	
	my %attributes = @_;
	$self->{underHandler} = $attributes{underHandler};
	delete($attributes{underHandler});
	foreach my $key (keys(%attributes)){
		$self->{player}->{$key} = $attributes{$key};
	}
	
	$self->doLogin();
	
	
	return $self;
}
sub doLogin {
	my $self = shift;
	print "Connecting to login server...\n\n";
	$self->createSocket('204.75.167.177', 3724);
}
sub handleData {
	my $self = shift;
	my @data = @_;
	
	foreach my $data (@data) {
		if($self->{player}->{xmlMode}) { $self->handleXML($data); next;};
		$self->handleXt($data);
	}
}
sub handleXML {
	my $self = shift;
	my $rawData = shift;
	
	return $self->send('<msg t="sys"><body action="verChk" r="0"><ver v="153" /></body></msg>'.chr(0).'<msg t="sys"><body action="rndK" r="-1"></body></msg>') if(index($rawData, 'policy') != -1);
	my $data = XML::Simple::XMLin($rawData);
	$self->{handlers}->{xml}->{$data->{body}->{action}}->($self, $rawData, $data) if($self->{handlers}->{xml}->{$data->{body}->{action}});
	$self->{handlers}->{xml}->{ALL}->($self, $rawData, $data) if($self->{handlers}->{xml}->{ALL});
}
sub handleXt {
	my $self = shift;
	my $data = shift;
	my @packet = split('%', $data);
	shift(@packet);
	$self->{handlers}->{xt}->{$packet[1]}->($self, $data, @packet) if($packet[1] && $self->{handlers}->{xt}->{$packet[1]});
	$self->{handlers}->{xt}->{ALL}->($self, $data, @packet) if($self->{handlers}->{xt}->{ALL});
}
sub handleGameError {
	my($self, $data, @packet) = @_;
	
	die("Error logging in. Error ID: $packet[3]\n\n") if(!$self->{player}->{loggedIn});
	print "In-game error recieved. Error ID: $packet[3]\n\n";
}
sub handleSuccessfulLogin{
	my($self,$data, @packet) = @_;
	
	if($self->{player}->{isLogin}){
		$self->{player}->{rawData} = $packet[3];
		my @loginData = split('\|', $packet[3]);
		$self->{player}->{playerID} = $loginData[0];
		$self->{player}->{loginKey} = $loginData[3];
		$self->{player}->{confirmKey} = $packet[4];
		$self->{player}->{xmlMode} = 1;
		$self->{player}->{isLogin} = 0;
		$self->disconnect();
		$self->createSocket($self->{servers}->{$self->{player}->{server}}->{IP}, $self->{servers}->{$self->{player}->{server}}->{Port});
		return print "Successfully logged into login server...Now connecting to $self->{player}->{server}...\n\n";
	}
	$self->send("%xt%s%j#js%-1%$self->{player}->{playerID}%$self->{player}->{loginKey}%en%");
	$self->send('%xt%s%g#gi%-1%');
	$self->{player}->{loggedIn} = 1;
	print "Successfully logged into $self->{player}->{server}!\n\n";
	$self->{handlers}->{xt}->{loggedIn}->($self) if($self->{handlers}->{xt}->{loggedIn});
}
sub handleRandomKey {
	my($self, undef, $data) = @_;
	$self->{player}->{xmlMode} = 0;

	return $self->send('<msg t="sys"><body action="login" r="0"><login z="w1"><nick><![CDATA['.$self->{player}->{userName}.']]></nick><pword><![CDATA['.$self->getLoginHash($self->{player}->{password}, $data->{body}->{k}).']]></pword></login></body></msg>') if($self->{player}->{isLogin});
	$self->send('<msg t="sys"><body action="login" r="0"><login z="w1"><nick><![CDATA['.$self->{player}->{rawData}.']]></nick><pword><![CDATA['.$self->encryptPassword(Digest::MD5::md5_hex($self->{player}->{loginKey}.$data->{body}->{k})).$self->{player}->{loginKey}.'#'.$self->{player}->{confirmKey}.']]></pword></login></body></msg>');
}

sub getLoginHash {
	my $self = shift;
    my $password = shift;
    my $rndK     = shift;
    
    return $self->encryptPassword(Digest::MD5::md5_hex(uc($self->encryptPassword(Digest::MD5::md5_hex($password))).$rndK.'a1ebe00441f5aecb185d0ec178ca2305Y(02.>\'H}t":E1_root'));
}
sub encryptPassword {
	my $self = shift;
    my $password = shift;
    return substr($password, 16, 16).substr($password, 0, 16);
}
sub createSocket {
	my($self, $ip, $port) = @_;
	$self->{socket} = IO::Socket::INET->new(PeerAddr => $ip, PeerPort => $port, Blocking => 0);
	$self->{underHandler}->add($self);
}
sub send {
	my $self = shift;
	my $data = shift;
	$self->{socket}->send($data.chr(0), 0);
}
sub disconnect {
	my $self = shift;
	my $destroy = shift // 0;
	$self->{alive} = 0 if($destroy);
	$self->{underHandler}->del($self);
	print $self->{player}->{userName}." has been disconnected.\n\n";
	$self->destroy() if($destroy);
}
sub destroy {
	my $self = shift;
	$self = undef;
}

#########################################
# 			In-Game Functions			#
#########################################


sub joinRoom {
	my($self, $roomID, $x, $y) = @_;
	$x = $x // 0;
	$y = $y // 0;
	
	$self->send("%xt%s%j#jr%-1%$roomID%$x%$y%");
}



1;
