package Irssi::WindowItem;
# https://github.com/shabble/irssi-docs/wiki/Windowitem
# https://github.com/shabble/irssi-docs/blob/master/Irssi/Windowitem.pod

use Irssi::TextUI::TextBufferView;

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
