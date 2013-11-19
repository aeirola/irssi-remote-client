package Irssi::Query;
use parent 'Irssi::WindowItem';

sub new {
	my $class = shift;
	my $self = $class->SUPER::new(@_);

	my %args = @_;
	$self->{type} = 'QUERY';
	return $self;
}

1;
