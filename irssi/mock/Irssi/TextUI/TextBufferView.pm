package Irssi::TextUI::TextBufferView;
# https://github.com/shabble/irssi-docs/wiki/TextBufferView
# https://github.com/shabble/irssi-docs/blob/master/Irssi/TextUI/TextBufferView.pod

use Irssi::TextUI::TextBuffer;

sub new {
	my $class = shift;
	my %args = @_;
	my $buffer = Irssi::TextUI::TextBuffer->new('lines' => $args{lines});
	my $self = bless {
		buffer => $buffer
		}, $class;
	return $self;
}

1;
