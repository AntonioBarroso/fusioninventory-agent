package FusionInventory::Agent::Task::Inventory::HPUX::Controllers;

use strict;
use warnings;

use parent 'FusionInventory::Agent::Task::Inventory::Module';

use FusionInventory::Agent::Tools;

sub isEnabled {
    my (%params) = @_;
    return 0 if !$params{category}->{controller};
    return canRun('ioscan');
}

sub doInventory {
    my (%params) = @_;

    my $inventory = $params{inventory};
    my $logger    = $params{logger};

    foreach my $type (qw/ext_bus fc psi/) {
        foreach my $controller (_getControllers(
            command => "ioscan -kFC $type",
            logger  => $logger
        )) {
            $inventory->addEntry(
                section => 'CONTROLLERS',
                entry   => $controller
            );
        }
    }
}

sub _getControllers {
    my $handle = getFileHandle(@_);
    return unless $handle;

    my @controllers;
    while (my $line = <$handle>) {
        my @info = split(/:/, $line);
        push @controllers, {
            TYPE => $info[17]
        };
    }
    close $handle;

    return @controllers;
}

1;
