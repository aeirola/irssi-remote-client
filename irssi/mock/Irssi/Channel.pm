package Irssi::Channel;
use parent 'Irssi::WindowItem';

sub new {
	my $class = shift;
	my $self = $class->SUPER::new(@_);

	my %args = @_;
	$self->{type} = 'CHANNEL';
	$self->{topic} = $args{topic};
	return $self;
}

sub nicks {
	return shift->{_nicks};
}

1;
