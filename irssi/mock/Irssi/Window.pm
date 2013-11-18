package Irssi::Window;

use Irssi::WindowItem;

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
