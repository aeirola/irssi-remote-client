package Irssi::UI::TextDest;
# https://github.com/shabble/irssi-docs/wiki/TextDest

sub new {
	my $class = shift;
	my %args = @_;
	my $self = bless {
			window => $args{window}
		}, $class;
	return $self;
}

1;

