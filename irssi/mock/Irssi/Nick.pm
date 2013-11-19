package Irssi::Nick;
# https://github.com/shabble/irssi-docs/wiki/Nick
# https://github.com/shabble/irssi-docs/blob/master/Irssi/Nick.pod

sub new {
	my $class = shift;
	my %args = @_;
	my $self = bless {
			type => 'NICK',
			nick => $args{nick}
		}, $class;
	return $self;
}

1;
