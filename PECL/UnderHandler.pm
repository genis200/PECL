use IO::Select;
use IO::Socket::INET;
use strict;
use warnings;

package PECL::UnderHandler;


sub new {
	my $self = {};
	bless($self);
	shift;
	$self->{child} = shift;
	$self->{selector} = IO::Select->new();
	$self->{penguins} = {};
	$self->{callBacks} = {noHandles => undef};
	return $self;
}
sub add {
	$_[0]->{penguins}->{fileno($_[1]->{socket})} = $_[1];
	$_[0]->{selector}->add(fileno($_[1]->{socket}));
}
sub del {
	$_[0]->{selector}->remove(fileno($_[1]->{socket}));
	$_[0]->{callBacks}->{noHandles}->($_[0]) if(!$_[0]->{selector}->count() && !$_[0]->{penguins}->{fileno($_[1]->{socket})}->{alive} && $_[0]->{callBacks}->{noHandles});
	delete($_[0]->{penguins}->{fileno($_[1]->{socket})});
	
}
sub doLoop {
	my $self = shift;
	while(1){
		my @ready = $self->{selector}->can_read(1);
		foreach my $penguin (values($self->{penguins})) {
			next if(!$penguin->{player}->{loggedIn});
			foreach my $key (keys($penguin->{jobs})){
				next if(!(time() - $penguin->{jobs}->{$key}->{lastExecuted} >=  $penguin->{jobs}->{$key}->{timer}));
				$penguin->{jobs}->{$key}->{callBack}->($penguin);
				if(!$penguin->{jobs}->{$key}->{callBack}){
					delete($penguin->{jobs}->{$key});
					next;
				}
				$penguin->{jobs}->{$key}->{lastExecuted} = time();
			}
		}
		foreach my $ready (@ready){
			$self->processData($self->{penguins}->{$ready}->{socket}, $self->{penguins}->{$ready});
		}
	}
}
sub processData {
	my($self, $ready, $penguin) = @_;
	if(!$ready){
		return;
	}
	my $fullData = '';
	while(substr($fullData, -1, 1) ne chr(0)){
		$ready->recv(my $data, 99999999, 0);
		return $penguin->disconnect(1) if($data eq '' && $fullData eq '');
		$fullData .= $data;
	}	
	$penguin->handleData(split(chr(0), $fullData));
}
1;
