package Irssi::TextUI::LineInfo;
# https://github.com/shabble/irssi-docs/wiki/LineInfo
# https://github.com/shabble/irssi-docs/blob/master/Irssi/TextUI/LineInfo.pod

sub new {
	my $class = shift;
	my %args = @_;

	my $self = bless {
		time => $args{time} || 1
		}, $class;
	return $self;
}

1;
