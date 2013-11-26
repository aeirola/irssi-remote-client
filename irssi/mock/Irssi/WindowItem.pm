package Irssi::WindowItem;
# https://github.com/shabble/irssi-docs/wiki/Windowitem
# https://github.com/shabble/irssi-docs/blob/master/Irssi/Windowitem.pod

sub new {
	my $class = shift;
	my $args = @_;
	my $self = bless {
		name => $args{name}
		}, $class;
	$self->{type} = undef;
	$self->{_commands} = [];
	return $self;
}

sub command {
	my ($self, $command) = @_;
	push(@{$self->{_commands}}, $command);
}

1;
