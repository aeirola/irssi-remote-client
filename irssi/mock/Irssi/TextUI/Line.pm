package Irssi::TextUI::Line;
# https://github.com/shabble/irssi-docs/wiki/Line
# https://github.com/shabble/irssi-docs/blob/master/Irssi/TextUI/Line.pod

use Irssi::TextUI::LineInfo;

sub new {
	my $class = shift;
	my %args = @_;
	my $info = Irssi::TextUI::LineInfo->new('time' => $args{time});

	my $self = bless {
		info => $info,
		_text => $args{text},
		_next => $args{next},
		_prev => $args{prev},
		}, $class;
	return $self;
}


sub get_text {
	return shift->{_text};
}

sub next {
	return shift->{_next};
}

sub prev {
	return shift->{_prev};
}

1;
