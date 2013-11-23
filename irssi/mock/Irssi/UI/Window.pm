package Irssi::UI::Window;
# https://github.com/shabble/irssi-docs/wiki/Window

use Irssi::Channel;
use Irssi::Query;
use Irssi::WindowItem;
use Irssi::TextUI::TextBufferView;

sub new {
	my $class = shift;
	my %args = @_;
	my $self = bless {
			refnum => $args{refnum},
			name => $args{name},
		}, $class;

	my $type = $args{type};
	my $item;
	if (!defined($type)) {
		$item = Irssi::WindowItem->new();
	} elsif ($type eq "CHANNEL") {
		$item = Irssi::Channel->new('name' => $args{name}, 'topic' => $args{topic}, 'nicks' => $args{nicks});
	} elsif ($type eq "QUERY") {
		$item = Irssi::Query->new();
	} else {
		$item = Irssi::WindowItem->new();
	}
	$self->{_items} = $item;

	my $view = Irssi::TextUI::TextBufferView->new('lines' => $args{lines});
	$self->{_view} = $view;

	return $self;
}

sub items {
	return shift->{_items};
};

sub view {
	return shift->{_view};
}

sub print {

}

1;
