package Irssi::UI::Window;

use Irssi::WindowItem;
# https://github.com/shabble/irssi-docs/wiki/Window
# https://github.com/shabble/irssi-docs/blob/master/Irssi/UI/Window.pod

sub new {
	my $class = shift;
	my ($refnum, $name) = @_;
	my $self = bless {
		refnum => $refnum,
		name => $name
		}, $class;
	return $self;
}

sub items {
	@items = [Irssi::WindowItem->new('', '', '')];
	return $items;
};

sub view {

}

1;
