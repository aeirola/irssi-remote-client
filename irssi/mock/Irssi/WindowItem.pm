package Irssi::WindowItem;
# https://github.com/shabble/irssi-docs/wiki/Windowitem
# https://github.com/shabble/irssi-docs/blob/master/Irssi/Windowitem.pod

use Irssi::TextUI::TextBufferView;

sub new {
	my $class = shift;
	my $args = @_;
	my $self = bless {
		name => $args{name}
		}, $class;
	$self->{type} = undef;
	return $self;
}

1;
