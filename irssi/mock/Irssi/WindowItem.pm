package Irssi::WindowItem;

sub new {
	my $class = shift;
	my ($type, $name) = @_;
	my $self = bless {
		type => '$type',
		name => '$name'
		}, $class;
	return $self;
}

1;
