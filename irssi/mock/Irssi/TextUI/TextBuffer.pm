package Irssi::TextUI::TextBuffer;
# https://github.com/shabble/irssi-docs/wiki/Textbuffer
# https://github.com/shabble/irssi-docs/blob/master/Irssi/TextUI/TextBuffer.pod

use Irssi::TextUI::Line;

sub new {
	my $class = shift;
	my %args = @_;

	my $line;
	if ($args{lines}) {
		$line = Irssi::TextUI::Line->new('text' => $args{lines}[0]);
	}

	my $self = bless {
		cur_line => $line
		}, $class;
	return $self;
}

1;
