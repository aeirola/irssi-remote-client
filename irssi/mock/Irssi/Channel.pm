package Irssi::Channel;
use parent 'Irssi::WindowItem';

use Irssi::Nick;

sub new {
	my $class = shift;
	my $self = $class->SUPER::new(@_);

	my %args = @_;
	$self->{type} = 'CHANNEL';
	$self->{topic} = $args{topic};

	my @nicknames;
	for my $nickName (@{$args{nicks}}) {
		push(@nicknames, Irssi::Nick->new('nick' => $nickName));
	}
	$self->{_nicknames} = \@nicknames;

	return $self;
}

sub nicks {
	return @{shift->{_nicknames}};
}

1;
