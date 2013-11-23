package Irssi::TextUI::TextBuffer;
# https://github.com/shabble/irssi-docs/wiki/Textbuffer
# https://github.com/shabble/irssi-docs/blob/master/Irssi/TextUI/TextBuffer.pod

use Irssi::TextUI::Line;

sub new {
	my $class = shift;
	my %args = @_;

	my $cur_line;
	my $prev_line;
	my $time = 1;
	for my $line (@{$args{lines}}) {
		$prev_line = $cur_line;
		$cur_line = Irssi::TextUI::Line->new('text' => $line, 'time' => $time, 'prev' => $prev_line);
		$prev_line->{_next} = $cur_line;
		$time++;
	}

	my $self = bless {
		cur_line => $cur_line
		}, $class;
	return $self;
}

1;
